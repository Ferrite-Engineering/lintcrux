// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail against a `Ref` captured by a closure that outlives
// the build which created it.
//
// THE BUG CLASS IN ONE LINE:
// `Provider((ref) { ref.watch(a); return Foo(supplier: () => ref.watch(b)); })`
// hands `Foo` a closure that runs whenever `Foo` decides to run it, and by
// then the provider may have rebuilt: `ref.watch` on a disposed `Ref` throws
// `UnmountedRefException` out of whatever call path invoked the closure, far
// from the provider that caused it.
//
// WHAT IS FLAGGED, with no lifetime analysis at all:
// inside a provider build (an `(ref) { … }` / `(ref) => …` body, including an
// `overrideWith` binding builder), a function expression that uses `ref` and
// is not invoked in place: it is passed as an argument, stored, or returned.
// The provider is then classified by whether it can be disposed while the
// closure is live: a body that watches or listens can rebuild, and a
// scoped / family / autoDispose / override-bound provider can be disposed.
// Those are violations. A `ref.read`-only body on a root provider is allowed,
// and the allowance names the invariant it rests on, so that adding one
// `ref.watch` to such a body is caught by the next run of the guard.
//
// WHAT IS DELIBERATELY NOT FLAGGED:
// - a closure handed to a Riverpod lifecycle hook (`ref.onDispose(…)`): the
//   sibling scanner `lifecycle_ref_scanner.dart` owns that shape;
// - a closure handed to `ref.listen` / `ref.listenSelf`: Riverpod cancels the
//   listener with the provider, so the closure never outlives the `Ref`;
// - a closure handed to a synchronous iteration method (`map`, `where`,
//   `fold`, …) that runs it before the call returns.

import 'dart:io';

import 'lifecycle_ref_scanner.dart'
    show balancedSpan, dartFiles, stripCommentsAndStrings;

/// One closure found capturing `ref` inside a provider build.
class CapturedRefClosure {
  /// Creates a finding.
  const CapturedRefClosure({
    required this.path,
    required this.line,
    required this.provider,
    required this.handedTo,
    required this.violation,
    required this.detail,
  });

  /// File the closure was found in.
  final String path;

  /// 1-based line of the closure's first token.
  final int line;

  /// The provider (or override target) whose build contains the closure.
  final String provider;

  /// What the closure was handed to: a constructor or call name, `return`,
  /// or an assignment target.
  final String handedTo;

  /// `true` when the provider can rebuild or be disposed while the closure
  /// is live; `false` for the allowed `ref.read`-only root-provider shape.
  final bool violation;

  /// The reason, in words fit for the failure report.
  final String detail;
}

/// A provider build: `(ref) { … }` or `(ref) => …`, or an `overrideWith`
/// binding builder with the same shape.
final RegExp _buildRe = RegExp(
  r'\(\s*(?:ref|_ref)\s*\)\s*(?:async\s*\*?\s*)?(\{|=>)',
);

/// A function expression: a parameter list followed by `=>` or a block,
/// not preceded by an identifier (which would make it a call or a
/// declaration) and not a control-flow head.
final RegExp _closureRe = RegExp(
  r'(?<![\w$)\]])\(([^()]*)\)\s*(?:async\s*\*?\s*)?(=>|\{)',
);

final RegExp _controlHeadRe = RegExp(r'(if|for|while|switch|catch|case)\s*$');

final RegExp _refUseRe = RegExp(r'(?<![\w$.])(ref|_ref)\s*\.');
final RegExp _refRebuildRe = RegExp(
  r'(?<![\w$.])(ref|_ref)\s*\.\s*(watch|listen)\s*\(',
);
final RegExp _disposableRe = RegExp(
  r'autoDispose|\.family\b|\.overrideWith\s*\(',
);
final RegExp _providerNameRe = RegExp(r'(\w+)\s*=\s*[^=;]*$');
final RegExp _overrideTargetRe = RegExp(r'(\w+)\s*\.\s*overrideWith\s*\(\s*$');

/// Calls that run their closure argument before returning.
const Set<String> _synchronousCalls = <String>{
  'map',
  'where',
  'whereType',
  'any',
  'every',
  'fold',
  'reduce',
  'forEach',
  'firstWhere',
  'lastWhere',
  'singleWhere',
  'indexWhere',
  'removeWhere',
  'retainWhere',
  'expand',
  'sort',
  'putIfAbsent',
  'update',
  'updateAll',
  'generate',
  'takeWhile',
  'skipWhile',
  'followedBy',
  'join',
  'contains',
  'select',
  'listen',
  'listenSelf',
  'onDispose',
  'onCancel',
  'onResume',
  'onAddListener',
  'onRemoveListener',
  'setState',
  'run',
  'runZoned',
  'unmodifiable',
  'of',
  'from',
  // `AsyncValue` mappers run their closure before returning.
  'when',
  'whenData',
  'whenOrNull',
  'maybeWhen',
  'maybeMap',
  'mapOrNull',
};

/// Scans every non-generated Dart file under [roots].
List<CapturedRefClosure> scanCapturedRefClosures(List<Directory> roots) {
  final found = <CapturedRefClosure>[];
  for (final root in roots) {
    for (final file in dartFiles(root)) {
      found.addAll(scanCapturedSource(file.readAsStringSync(), file.path));
    }
  }
  found.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });
  return found;
}

/// Scans one source [src] attributed to [path].
List<CapturedRefClosure> scanCapturedSource(String src, String path) {
  final stripped = stripCommentsAndStrings(src);
  final found = <CapturedRefClosure>[];
  for (final build in _buildRe.allMatches(stripped)) {
    final bodyStart = build.end - 1;
    final String body;
    if (build.group(1) == '{') {
      final span = balancedSpan(stripped, bodyStart, '{', '}');
      if (span == null) continue;
      body = span;
    } else {
      body = _arrowBody(stripped, build.end);
    }
    final header = _statementHead(stripped, build.start);
    final provider = _providerFor(header);
    final rebuilds = _refRebuildRe.hasMatch(body);
    final disposable = _disposableRe.hasMatch(header);
    for (final closure in _closureRe.allMatches(body)) {
      // The closure must not open a control-flow head.
      final before = body.substring(0, closure.start);
      if (_controlHeadRe.hasMatch(before.trimRight())) continue;
      final String text;
      if (closure.group(2) == '{') {
        final span = balancedSpan(body, closure.end - 1, '{', '}');
        if (span == null) continue;
        text = span;
      } else {
        text = _arrowBody(body, closure.end);
      }
      if (!_refUseRe.hasMatch(text)) continue;
      final handedTo = _handedTo(before);
      if (handedTo == null) continue;
      if (_synchronousCalls.contains(handedTo.split('.').last)) continue;
      final line = _lineOf(stripped, build.start + closure.start);
      final violation = rebuilds || disposable;
      final why = rebuilds
          ? 'the body watches or listens, so the provider can rebuild'
          : disposable
          ? 'the provider is scoped, a family, autoDispose or an override '
                'binding, so it can be disposed'
          : 'allowed: the body only reads and the provider is a root '
                'provider, so its Ref lives as long as the container; adding '
                'a single ref.watch to the body turns this into the bug';
      found.add(
        CapturedRefClosure(
          path: path,
          line: line,
          provider: provider,
          handedTo: handedTo,
          violation: violation,
          detail:
              'closure capturing `ref` handed to `$handedTo` in `$provider`: '
              '$why',
        ),
      );
    }
  }
  return found;
}

/// The text of an `=>` body starting at [from]: up to the `;`, `,` or
/// closing bracket that ends it at depth zero.
String _arrowBody(String src, int from) {
  var depth = 0;
  for (var i = from; i < src.length; i++) {
    final ch = src[i];
    if (ch == '(' || ch == '[' || ch == '{') depth++;
    if (ch == ')' || ch == ']' || ch == '}') {
      if (depth == 0) return src.substring(from, i);
      depth--;
    }
    if ((ch == ';' || ch == ',') && depth == 0) return src.substring(from, i);
  }
  return src.substring(from);
}

/// The statement text preceding [at]: back to the previous `;` or `}` at
/// the same nesting, which is where a provider declaration begins.
String _statementHead(String src, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final ch = src[i];
    if (ch == ')' || ch == ']') depth++;
    if (ch == '(' || ch == '[') {
      if (depth == 0) continue;
      depth--;
    }
    if (depth == 0 && (ch == ';' || ch == '}' || ch == '{')) {
      return src.substring(i + 1, at);
    }
  }
  return src.substring(0, at);
}

String _providerFor(String header) {
  final override = _overrideTargetRe.firstMatch(header);
  if (override != null) return '${override.group(1)}.overrideWith';
  final named = _providerNameRe.firstMatch(header);
  return named?.group(1) ?? '<provider>';
}

/// What a closure starting after [before] is handed to: the enclosing
/// call's name, `return`, or the assignment target. `null` when the closure
/// stands alone (invoked in place, or a statement expression).
String? _handedTo(String before) {
  final trimmed = before.trimRight();
  if (trimmed.endsWith('return')) return 'return';
  if (trimmed.endsWith('=')) {
    final target = RegExp(r'([\w.]+)\s*=$').firstMatch(trimmed);
    return target == null ? 'assignment' : '${target.group(1)} =';
  }
  if (trimmed.endsWith(':') || trimmed.endsWith(',') || trimmed.endsWith('(')) {
    // Walk back to the unmatched `(` that opens the enclosing call.
    var depth = 0;
    for (var i = trimmed.length - 1; i >= 0; i--) {
      final ch = trimmed[i];
      if (ch == ')' || ch == ']' || ch == '}') depth++;
      if (ch == '(' || ch == '[' || ch == '{') {
        if (depth == 0) {
          // The call name, past any explicit type arguments (`map<int>(`).
          final call = RegExp(
            r'([\w.]+)(?:<[^<>]*>)?\s*$',
          ).firstMatch(trimmed.substring(0, i));
          return call?.group(1) ?? 'call';
        }
        depth--;
      }
    }
    return 'call';
  }
  return null;
}

int _lineOf(String src, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < src.length; i++) {
    if (src.codeUnitAt(i) == 0x0a) line++;
  }
  return line;
}

/// Formats the failure report for [found].
String formatCapturedRefReport(List<CapturedRefClosure> found) {
  final buf = StringBuffer()
    ..writeln(
      'A closure captures `ref` and outlives the build that created it:',
    )
    ..writeln();
  for (final f in found) {
    buf.writeln('  ${f.path}:${f.line}  ${f.detail}');
  }
  buf
    ..writeln()
    ..writeln(
      'Fix: cache the value through `ref.listen` (it cancels on dispose and '
      'its last delivered value stays readable) or resolve the value in the '
      'build and close over the value, so the closure touches no `Ref`.',
    );
  return buf.toString();
}
