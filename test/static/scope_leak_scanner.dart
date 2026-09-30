// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Resolved-AST provider read-graph scanner backing
// `per_tab_provider_scope_leak_test.dart` (open-core) and the Pro overlay's
// copy. Kept as a separate library so both tests share the exact same
// extraction semantics and so the shape fixtures can exercise the primitives
// directly.
//
// The scan resolves every library under the source roots with
// `package:analyzer` and works on elements, not on text. It replaces the
// earlier regex scanner, which could not see a per-tab read behind a stored
// `Ref` field, a helper object, an extension method on `Ref`, or a
// runtime-selected provider family.
//
// ANALYSIS MODEL
//
//  1. PROVIDER REGISTRY. A top-level variable is a provider when its static
//     type, or any supertype, is declared in a riverpod library. That is a
//     type test, so it covers hand-written providers, generated providers and
//     families alike, and does not depend on the variable being named
//     `…Provider`. Each provider is keyed by `<library uri>::<name>`, stable
//     across the two analysis contexts a cross-repo scan needs.
//
//  2. BODIES AND BINDINGS. A provider's build logic is whatever supplies it:
//     its own initializer (an inline closure, a referenced top-level function,
//     or a `Notifier` class named by a `Foo.new` tear-off), the generated
//     part of a `@riverpod` declaration, AND — this is the LintCrux-specific
//     part — every `xProvider.overrideWith(builder)` binding anywhere in the
//     source roots. LintCrux's canonical defect is a store DECLARED as an
//     open-core no-op but BOUND, at ROOT, to a builder that reads
//     `currentProjectProvider`; the leak lives in the binding, not the
//     declaration, so binding builders are folded into the provider's read
//     set. `overrideWithValue` is excluded (it takes a pre-built value, not a
//     `Ref`-receiving builder).
//
//  3. READS. A read is a `watch`/`read`/`listen`/`refresh`/`invalidate`
//     invocation whose *receiver's static type* is riverpod's `Ref` or
//     `WidgetRef`. Testing the receiver's type rather than the token `ref`
//     makes a read through a stored `Ref` field visible. Reads are collected
//     over the call graph, not just the provider's own body, so a read hidden
//     in a helper object, an extension method on `Ref`, or a private notifier
//     method is reached. Each read edge records the repo-relative path where
//     the `ref.watch` textually sits, so a leak carried by a Pro binding of an
//     open-core-declared provider is attributed to the Pro repo.
//
//     The analysis is a may-analysis: a run-time selection between two
//     providers contributes both.
//
//  4. TAINT CLOSURE. A provider is tainted if it reads a per-tab provider or
//     any other tainted provider. Every tainted provider that is not itself
//     per-tab is a violation.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;

/// One provider-to-provider read edge: the target provider key, the helper
/// declarations the read was found behind (empty when it is written in the
/// provider's own body), and the repo-relative path where the read sits.
class ProviderRead {
  /// Creates a read edge.
  ProviderRead(this.target, this.via, this.path);

  /// The read provider's registry key.
  final String target;

  /// The helper chain the read was reached through, outermost first.
  final List<String> via;

  /// Repo-relative path of the file the `ref.watch` call textually occurs in.
  final String path;
}

/// A registered provider: its symbol, the repo-relative path of the library
/// declaring it, and the declarations/expressions supplying its build logic.
class ProviderInfo {
  /// Creates a provider record.
  ProviderInfo(this.key, this.name, this.path);

  /// `<library uri>::<name>` registry key.
  final String key;

  /// The `xProvider` symbol.
  final String name;

  /// Repo-relative path of the declaring library.
  final String path;

  /// Declaration keys (functions / notifier classes / generated parts)
  /// supplying this provider's build logic.
  final Set<String> bodies = <String>{};

  /// Own initializer plus every `overrideWith` binding builder, each paired
  /// with the path of the file it lives in.
  final List<_Source> _sources = <_Source>[];
}

/// A detected scope leak.
class ScopeLeak {
  /// Creates a leak record.
  ScopeLeak(this.symbol, this.path, this.reach, this.via);

  /// The leaking provider symbol.
  final String symbol;

  /// The file that carries the leaking read (declaration or binding).
  final String path;

  /// Reach chain from this provider down to the per-tab seed it depends on.
  final List<String> reach;

  /// Helper declarations the first hop's read was found behind, if any.
  final List<String> via;
}

/// An expression contributing build logic to a provider, tagged with the
/// repo-relative path it lives in.
class _Source {
  _Source(this.expr, this.path);
  final Expression expr;
  final String path;
}

/// The Dart SDK the analyzer should resolve `dart:` libraries against. Under
/// `flutter test` the running executable is the Flutter tester, whose
/// directory is not an SDK, so the bundled `dart-sdk` is located explicitly.
String? _dartSdkPath() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (flutterRoot != null) p.join(flutterRoot, 'bin', 'cache', 'dart-sdk'),
    p.dirname(p.dirname(Platform.resolvedExecutable)),
  ];
  for (final candidate in candidates) {
    if (File(p.join(candidate, 'lib', 'core', 'core.dart')).existsSync()) {
      return candidate;
    }
  }
  return null;
}

/// The resolved provider read-graph over a set of source roots.
class ScopeGraph {
  ScopeGraph._();

  /// Registered providers keyed by `<library uri>::<name>`.
  final Map<String, ProviderInfo> providers = <String, ProviderInfo>{};

  /// Libraries that failed to resolve (repo-relative paths).
  final List<String> unresolved = <String>[];

  final Map<String, _Decl> _decls = <String, _Decl>{};
  final Map<String, ResolvedUnitResult> _units = <String, ResolvedUnitResult>{};
  final Map<String, Map<String, String>> _generated =
      <String, Map<String, String>>{};
  final Map<String, List<_Source>> _pendingBindings = <String, List<_Source>>{};
  final Map<String, _Scan> _scans = <String, _Scan>{};
  Map<String, List<ProviderRead>>? _reads;

  /// Resolves every `.dart` file under [roots] and builds the graph.
  static Future<ScopeGraph> resolve(List<Directory> roots) async {
    final files = <String>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final e in root.listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) {
          files.add(p.normalize(e.absolute.path));
        }
      }
    }
    final graph = ScopeGraph._();
    if (files.isEmpty) return graph;
    final collection = AnalysisContextCollection(
      includedPaths: files,
      sdkPath: _dartSdkPath(),
    );
    for (final file in files) {
      final result = await collection
          .contextFor(file)
          .currentSession
          .getResolvedUnit(file);
      if (result is! ResolvedUnitResult) {
        graph.unresolved.add(p.relative(file));
        continue;
      }
      graph._units[p.normalize(result.path)] = result;
      result.unit.accept(_UnitVisitor(graph, result));
    }
    graph
      .._linkGenerated()
      .._linkBindings();
    return graph;
  }

  /// The symbol for [key], or the key's tail if unregistered.
  String nameOf(String key) =>
      providers[key]?.name ?? key.substring(key.indexOf('::') + 2);

  /// The registry key for the (first) provider named [name].
  String? keyOf(String name) {
    for (final e in providers.entries) {
      if (e.value.name == name) return e.key;
    }
    return null;
  }

  /// The helper chain recorded for the first hop of [reach], if the read was
  /// not written in that provider's own body.
  List<String> viaFor(List<String> reach) {
    if (reach.length < 2) return const <String>[];
    for (final r in reads()[reach[0]] ?? const <ProviderRead>[]) {
      if (r.target == reach[1]) return r.via;
    }
    return const <String>[];
  }

  /// The repo-relative path carrying the leaking read for [reach] — the file
  /// where `<reach[0]>`'s read of `<reach[1]>` textually sits. Falls back to
  /// the provider's declaration path.
  String pathFor(List<String> reach) {
    if (reach.length >= 2) {
      for (final r in reads()[reach[0]] ?? const <ProviderRead>[]) {
        if (r.target == reach[1]) return r.path;
      }
    }
    return providers[reach.first]?.path ?? reach.first;
  }

  /// Provider keys appearing as per-tab override targets in the library at
  /// [path], optionally restricted to the top-level variable named [within].
  ///
  /// Resolves both inline `xProvider.overrideWith(…)` entries and bare
  /// references to named `final Override proX = xProvider.overrideWith(…)`
  /// consts declared elsewhere in the resolved tree (the shape
  /// `proTabOverrides` uses).
  Set<String> overrideTargets(String path, String? within) {
    final unit = _units[p.normalize(File(path).absolute.path)];
    if (unit == null) return <String>{};
    AstNode scope = unit.unit;
    if (within != null) {
      for (final d in unit.unit.declarations) {
        if (d is TopLevelVariableDeclaration &&
            d.variables.variables.any((v) => v.name.lexeme == within)) {
          scope = d;
        }
      }
    }
    final out = <String>{};
    scope.accept(_OverrideVisitor(this, out, <Element>{}));
    return out;
  }

  /// The initializer expression of a named top-level `Override` const, or null
  /// if [element] is not one that is resolvable in this tree.
  Expression? overrideConstInitializer(Element? element) {
    var target = element;
    if (target is GetterElement) target = target.variable;
    if (target is! TopLevelVariableElement) return null;
    final type = target.type;
    if (type is! InterfaceType || type.element.name != 'Override') return null;
    final source = target.firstFragment.libraryFragment.source.fullName;
    final unit = _units[p.normalize(source)];
    if (unit == null) return null;
    for (final d in unit.unit.declarations) {
      if (d is! TopLevelVariableDeclaration) continue;
      for (final v in d.variables.variables) {
        if (v.name.lexeme == target.name) return v.initializer;
      }
    }
    return null;
  }

  /// Every provider's read set, following the call graph out of its sources.
  Map<String, List<ProviderRead>> reads() {
    final cached = _reads;
    if (cached != null) return cached;
    final out = <String, List<ProviderRead>>{};
    for (final info in providers.values) {
      final found = <String, ProviderRead>{};
      final seen = <String>{...info.bodies};
      final queue = <_Frame>[];
      for (final source in info._sources) {
        final own = _Scan();
        source.expr.accept(_ReadVisitor(this, own));
        for (final target in own.reads) {
          found.putIfAbsent(
            target,
            () => ProviderRead(target, const <String>[], source.path),
          );
        }
        for (final callee in own.callees) {
          if (!seen.add(callee)) continue;
          queue.add(_Frame(callee, <String>[_decls[callee]?.name ?? callee]));
        }
      }
      // A body IS the provider's own code, so it adds no hop.
      for (final k in info.bodies) {
        queue.add(_Frame(k, const <String>[]));
      }
      while (queue.isNotEmpty) {
        final frame = queue.removeLast();
        final scan = _scan(frame.decl);
        final declPath = _decls[frame.decl]?.path ?? info.path;
        for (final target in scan.reads) {
          found.putIfAbsent(
            target,
            () => ProviderRead(target, frame.via, declPath),
          );
        }
        for (final callee in scan.callees) {
          if (!seen.add(callee)) continue;
          queue.add(
            _Frame(callee, <String>[
              ...frame.via,
              _decls[callee]?.name ?? callee,
            ]),
          );
        }
      }
      out[info.key] = found.values.toList();
    }
    return _reads = out;
  }

  _Scan _scan(String declKey) {
    final cached = _scans[declKey];
    if (cached != null) return cached;
    // Insert before walking so a recursive declaration terminates.
    final scan = _scans[declKey] = _Scan();
    _decls[declKey]?.node.accept(_ReadVisitor(this, scan));
    return scan;
  }

  void _linkGenerated() {
    for (final info in providers.values) {
      final library = info.key.substring(0, info.key.indexOf('::'));
      final decl = _generated[library]?[info.name];
      if (decl != null) info.bodies.add(decl);
    }
  }

  void _linkBindings() {
    for (final entry in _pendingBindings.entries) {
      final info = providers[entry.key];
      if (info == null) continue;
      for (final source in entry.value) {
        info._sources.add(source);
        source.expr.accept(_BodyReferenceVisitor(info));
      }
    }
  }

  void _noteGenerated(String library, String provider, String declKey) {
    _generated.putIfAbsent(library, () => <String, String>{})[provider] =
        declKey;
  }

  void _noteBinding(String providerKey, Expression builder, String path) {
    _pendingBindings
        .putIfAbsent(providerKey, () => <_Source>[])
        .add(_Source(builder, path));
  }
}

/// Fixed-point taint propagation. Returns, for every tainted provider, a
/// shortest reach path ending at the per-tab seed it depends on.
Map<String, List<String>> taintClosure(
  Map<String, List<ProviderRead>> reads,
  Set<String> perTab,
) {
  final reach = <String, List<String>>{};
  for (final entry in reads.entries) {
    for (final read in entry.value) {
      if (read.target == entry.key || !perTab.contains(read.target)) continue;
      reach[entry.key] = <String>[entry.key, read.target];
      break;
    }
  }
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in reads.entries) {
      if (reach.containsKey(entry.key)) continue;
      for (final read in entry.value) {
        if (read.target == entry.key) continue;
        final downstream = reach[read.target];
        if (downstream == null) continue;
        reach[entry.key] = <String>[entry.key, ...downstream];
        changed = true;
        break;
      }
    }
  }
  return reach;
}

/// Formats the failure report for [violations].
String formatLeakReport(
  List<ScopeLeak> violations, {
  required bool openCore,
}) {
  final sorted = [...violations]..sort((a, b) => a.symbol.compareTo(b.symbol));
  final buf = StringBuffer()
    ..writeln(
      'Per-tab provider scope leak(s) detected in '
      '${openCore ? 'open-core' : 'the Pro overlay'}:',
    )
    ..writeln();
  for (final v in sorted) {
    buf
      ..writeln('  ${v.symbol}')
      ..writeln('    in ${v.path}')
      ..writeln('    per-tab reach: ${v.reach.join(' -> ')}');
    if (v.via.isNotEmpty) {
      buf.writeln('    read reached through: ${v.via.join(' > ')}');
    }
    buf.writeln();
  }
  buf
    ..writeln(
      'Each provider above is hoisted to the ROOT container and will read '
      'the empty root-scope versions of those per-tab providers, silently '
      'producing wrong output in every tab.',
    )
    ..writeln(
      'Fix by adding `<symbol>.overrideWith(<fn|Notifier.new>)` to '
      '`lintcruxTabOverridesFactory` (open-core) or `proTabOverrides` (Pro).',
    )
    ..writeln(
      'If the provider is intentionally root-scoped (an app-global '
      'service), add it to the allowlist with a reason.',
    );
  return buf.toString();
}

class _Frame {
  _Frame(this.decl, this.via);
  final String decl;
  final List<String> via;
}

class _Decl {
  _Decl(this.name, this.node, this.path);
  final String name;
  final AstNode node;
  final String path;
}

class _Scan {
  final Set<String> reads = <String>{};
  final Set<String> callees = <String>{};
}

bool _isRiverpodLibrary(Uri? uri) =>
    uri != null && uri.toString().contains('riverpod');

/// Riverpod library types that are NOT providers, so a top-level variable of
/// one of these must not be registered as a provider. `Override` is the one
/// that matters in practice: LintCrux's `proTabOverrides` lists named
/// `final Override proXOverride = xProvider.overrideWith(…)` consts, and
/// without this exclusion each such const — riverpod-typed, with an
/// `overrideWith` builder that reads per-tab state — is misread as a
/// per-tab-leaking provider.
const Set<String> _nonProviderRiverpodTypes = <String>{
  'Override',
  'ProviderContainer',
  'ProviderScope',
  'ProviderSubscription',
  'ProviderObserver',
};

/// True when [type] is, or inherits from, a provider type declared by
/// riverpod (excluding the riverpod types that are not providers).
bool _isProviderType(DartType? type) {
  if (type is! InterfaceType) return false;
  if (_nonProviderRiverpodTypes.contains(type.element.name)) return false;
  if (_isRiverpodLibrary(type.element.library.uri)) return true;
  for (final supertype in type.element.allSupertypes) {
    if (_isRiverpodLibrary(supertype.element.library.uri)) return true;
  }
  return false;
}

/// True when [type] is riverpod's `Ref` or `WidgetRef`, however reached.
bool _isRefType(DartType? type) {
  if (type is! InterfaceType) return false;
  bool isRef(InterfaceElement element) {
    final name = element.name;
    return _isRiverpodLibrary(element.library.uri) &&
        (name == 'Ref' || name == 'WidgetRef');
  }

  if (isRef(type.element)) return true;
  for (final supertype in type.element.allSupertypes) {
    if (isRef(supertype.element)) return true;
  }
  return false;
}

/// True when [element] is a `Ref` member invoked without an explicit receiver
/// — the shape a `Ref` extension method takes.
bool _isImplicitRefReceiver(Element? element) {
  final enclosing = element?.enclosingElement;
  if (enclosing is InterfaceElement) return _isRefType(enclosing.thisType);
  if (enclosing is ExtensionElement) return _isRefType(enclosing.extendedType);
  return false;
}

const Set<String> _refMethods = <String>{
  'watch',
  'read',
  'listen',
  'listenManual',
  'refresh',
  'invalidate',
};

const Set<String> _overrideMethods = <String>{
  'overrideWith',
  'overrideWithBuild',
};

/// The registry key for a provider element, or null if not a top-level
/// provider variable.
String? _providerKey(Element? element) {
  var target = element;
  if (target is GetterElement) target = target.variable;
  if (target is SetterElement) target = target.variable;
  if (target is! TopLevelVariableElement) return null;
  if (!_isProviderType(target.type)) return null;
  final name = target.name;
  if (name == null) return null;
  return '${target.library.uri}::$name';
}

/// A stable key for a scannable declaration: its source file and name offset.
String? _declKey(Element? element) {
  if (element == null) return null;
  final fragment = element.firstFragment;
  final source = fragment.libraryFragment?.source.fullName;
  final offset = fragment.nameOffset;
  if (source == null || offset == null) return null;
  return '$source@$offset';
}

/// Registers provider definitions, every scannable declaration, and every
/// `overrideWith` binding in one unit.
class _UnitVisitor extends RecursiveAstVisitor<void> {
  _UnitVisitor(this.graph, this.result);

  final ScopeGraph graph;
  final ResolvedUnitResult result;

  String get _path =>
      p.relative(result.libraryElement.firstFragment.source.fullName);

  void _record(Element? element, String name, AstNode node) {
    final key = _declKey(element);
    if (key == null) return;
    graph._decls.putIfAbsent(key, () => _Decl(name, node, _path));
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      final element = variable.declaredFragment?.element;
      final key = _providerKey(element);
      if (key == null) continue;
      final info = graph.providers.putIfAbsent(
        key,
        () => ProviderInfo(key, element!.name!, _path),
      );
      final initializer = variable.initializer;
      if (initializer != null) {
        info._sources.add(_Source(initializer, info.path));
        initializer.accept(_BodyReferenceVisitor(info));
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_overrideMethods.contains(node.methodName.name)) {
      final receiver = node.realTarget;
      if (receiver is Identifier) {
        final key = _providerKey(receiver.element);
        final args = node.argumentList.arguments;
        if (key != null && args.isNotEmpty) {
          graph._noteBinding(key, args.first, _path);
        }
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final element = node.declaredFragment?.element;
    final name = element?.name ?? '<function>';
    _record(element, name, node);
    _noteIfGenerated(node.metadata, name, element);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final element = node.declaredFragment?.element;
    _record(element, element?.name ?? '<method>', node);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _record(node.declaredFragment?.element, '<constructor>', node);
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    final name = element?.name ?? '<class>';
    _record(element, name, node);
    _noteIfGenerated(node.metadata, name, element);
    super.visitClassDeclaration(node);
  }

  /// A `@riverpod` function or class generates `<name>Provider` into the same
  /// library's `.g.dart` part; record the association so the generated
  /// variable picks up the annotated declaration as its body.
  void _noteIfGenerated(
    NodeList<Annotation> metadata,
    String name,
    Element? element,
  ) {
    final annotated = metadata.any((a) {
      final n = a.name.name;
      return n == 'riverpod' || n == 'Riverpod';
    });
    if (!annotated || name.isEmpty) return;
    final key = _declKey(element);
    if (key == null) return;
    graph._noteGenerated(
      result.libraryElement.uri.toString(),
      '${name[0].toLowerCase()}${name.substring(1)}Provider',
      key,
    );
  }
}

/// Attaches the declarations a build expression names — `Foo.new` for a
/// notifier class, a bare identifier for a top-level build function — as the
/// provider's bodies.
class _BodyReferenceVisitor extends RecursiveAstVisitor<void> {
  _BodyReferenceVisitor(this.info);

  final ProviderInfo info;

  void _add(Element? element) {
    var target = element;
    if (target is ConstructorElement) target = target.enclosingElement;
    final key = _declKey(target);
    if (key != null) info.bodies.add(key);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element is LocalFunctionElement ||
        element is TopLevelFunctionElement ||
        element is ConstructorElement) {
      _add(element);
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitConstructorReference(ConstructorReference node) {
    _add(node.constructorName.element);
    super.visitConstructorReference(node);
  }
}

/// Collects `ref.*` provider reads and outgoing call-graph edges from one
/// declaration.
class _ReadVisitor extends RecursiveAstVisitor<void> {
  _ReadVisitor(this.graph, this.scan);

  final ScopeGraph graph;
  final _Scan scan;

  void _addCallee(Element? element) {
    final key = _declKey(element);
    if (key != null && graph._decls.containsKey(key)) scan.callees.add(key);
  }

  /// True when [receiver] is the `ref` of a STORED callback — a formal
  /// parameter of a nested closure that is not the provider's own build
  /// closure. Such a `ref` is bound by whoever invokes the callback later (a
  /// tab-scoped widget, for a menu entry's `onActivate`), so a read through it
  /// is not a build-time dependency of the enclosing provider. A `ref`
  /// captured from the build scope (e.g. inside a `ref.listen` callback whose
  /// own parameters are `(prev, next)`) is NOT a formal parameter here and so
  /// is still counted.
  bool _isStoredCallbackRef(Expression? receiver) {
    if (receiver is! SimpleIdentifier) return false;
    final element = receiver.element;
    if (element == null) return false;
    for (var n = receiver.parent; n != null; n = n.parent) {
      if (n is! FunctionExpression) continue;
      final params = n.parameters?.parameters ?? const <FormalParameter>[];
      final declaresRef = params.any(
        (param) => param.declaredFragment?.element == element,
      );
      if (declaresRef) return !_isProviderBuildClosure(n);
    }
    return false;
  }

  /// True when [closure] is the build closure of a provider — passed directly
  /// to a provider constructor, `overrideWith`, or a family factory. Its `ref`
  /// parameter IS the provider's build ref.
  bool _isProviderBuildClosure(FunctionExpression closure) {
    var parent = closure.parent;
    if (parent is NamedExpression) parent = parent.parent;
    if (parent is! ArgumentList) return false;
    final invocation = parent.parent;
    if (invocation is InstanceCreationExpression) {
      return _isProviderType(invocation.staticType);
    }
    if (invocation is MethodInvocation) {
      final name = invocation.methodName.name;
      if (_overrideMethods.contains(name) || name == 'family') return true;
      return _isProviderType(invocation.staticType);
    }
    if (invocation is FunctionExpressionInvocation) {
      return _isProviderType(invocation.staticType);
    }
    return false;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final receiver = node.realTarget;
    final onRef = receiver != null
        ? _isRefType(receiver.staticType)
        : _isImplicitRefReceiver(node.methodName.element);
    if (_refMethods.contains(node.methodName.name) &&
        onRef &&
        node.argumentList.arguments.isNotEmpty &&
        !_isStoredCallbackRef(receiver)) {
      node.argumentList.arguments.first.accept(
        _ProviderArgumentVisitor(graph, scan, <String>{}),
      );
    }
    _addCallee(node.methodName.element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _addCallee(node.propertyName.element);
    super.visitPropertyAccess(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _addCallee(node.identifier.element);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _addCallee(node.constructorName.element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _addCallee(node.element);
    super.visitFunctionExpressionInvocation(node);
  }
}

/// Resolves the provider(s) an argument expression denotes: a plain reference,
/// a family application, a conditional, or a helper that returns a provider.
class _ProviderArgumentVisitor extends RecursiveAstVisitor<void> {
  _ProviderArgumentVisitor(this.graph, this.scan, this.guard);

  final ScopeGraph graph;
  final _Scan scan;
  final Set<String> guard;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final key = _providerKey(node.element);
    if (key != null) scan.reads.add(key);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final key = _declKey(node.methodName.element);
    if (key != null && guard.add(key)) {
      graph._decls[key]?.node.accept(
        _ProviderArgumentVisitor(graph, scan, guard),
      );
    }
    super.visitMethodInvocation(node);
  }
}

/// Collects per-tab override targets from an override list, following bare
/// references to named `Override` consts to their target provider.
class _OverrideVisitor extends RecursiveAstVisitor<void> {
  _OverrideVisitor(this.graph, this.out, this.guard);

  final ScopeGraph graph;
  final Set<String> out;
  final Set<Element> guard;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    const overrides = <String>{
      'overrideWith',
      'overrideWithValue',
      'overrideWithBuild',
    };
    if (overrides.contains(node.methodName.name)) {
      final receiver = node.realTarget;
      if (receiver is Identifier) {
        final key = _providerKey(receiver.element);
        if (key != null) out.add(key);
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    final initializer = graph.overrideConstInitializer(element);
    if (initializer != null && element != null && guard.add(element)) {
      initializer.accept(_OverrideVisitor(graph, out, guard));
    }
    super.visitSimpleIdentifier(node);
  }
}
