// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail against the "per-tab provider scope leak" bug class,
// scanning the open-core `lib/`. Shares its resolved-AST engine with the Pro
// overlay's copy (`scope_leak_scanner.dart`); the source roots and the repo
// whose violations are reported differ per repo.
//
// LintCrux gives every open tab its own child `ProviderContainer`, and a tab is
// bound 1:1 to a `.lintcrux` project. A provider is per-tab IFF it is
// overridden per tab — in open-core via `lintcruxTabOverridesFactory`
// (`lib/features/workspace/providers/tab_overrides_factory.dart`), in the Pro
// overlay via `proTabOverrides`. Widgets in a tab's subtree read providers from
// that child container.
//
// THE BUG CLASS:
// A provider whose body (directly or transitively) reads a per-tab provider
// (currentProjectProvider, violationStoreProvider, selectedViolationProvider,
// …) but which is NOT itself made per-tab is hoisted to the ROOT container and
// reads the EMPTY root-scope versions of those providers. The symptom is
// silent: no exception, just wrong output for every tab (a project-keyed store
// resolving "no project open" while a tab plainly shows one; a diagnostics
// report reading zero violations). LintCrux's canonical instance was the six
// project-keyed Pro stores once registered at ROOT while keying off
// `currentProjectProvider`.
//
// WHY UNIT TESTS DON'T CATCH IT:
// Every provider unit test builds a single FLAT `ProviderContainer` with the
// per-tab dependency overridden inline. With no parent container there is no
// fallthrough, so the scoping defect is structurally invisible. This is why
// the guard is static and source-driven.
//
// ANALYSIS MODEL: see `scope_leak_scanner.dart`. The shapes it must resolve —
// a read behind a stored `Ref`, a helper object, an extension method on `Ref`,
// a run-time-selected family, and a two-hop transitive chain — are pinned by
// `scope_leak_shapes/shapes.dart` and asserted below, so a future
// simplification cannot quietly reopen a closed blind spot.
//
// When this test fails it has almost certainly found a real latent bug. The
// fix is one line in `lintcruxTabOverridesFactory` (`xProvider.overrideWith(
// …)`) or, for a Pro-bound provider, in `proTabOverrides`. Add to the
// allowlist below ONLY for a provider that is intentionally root-scoped, with
// a documented reason.
//
// COST AND HOW TO RUN
// Resolving the tree costs roughly ten seconds per source root, which is why
// this file carries a raised timeout. It runs in the default suite.

@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'scope_leak_scanner.dart';

/// Providers that read per-tab state but are *intentionally* root-scoped, with
/// the reason they are exempt. Keep this list empty if at all possible — an
/// entry here is a permanent hole in the guard.
///
/// The two entries below are the app's single, root-hosted CXP endpoint (one
/// socket per process). Both resolve the ACTIVE tab's container per request
/// through `ActiveTabContainerHandle`; the direct `ref.read` of the per-tab
/// providers is the empty-workspace fallback only, taken when no tab is open.
/// This is a genuine app-global service, not the per-tab scope-leak class the
/// guard exists to catch.
const Map<String, String> allowlist = <String, String>{
  'cxpRequestHandlerProvider':
      'Root-hosted CXP inbound handler. Resolves the ACTIVE tab container per '
      'request through ActiveTabContainerHandle; the direct ref.read of the '
      'per-tab providers is the empty-workspace fallback only.',
  'cxpServerLifecycleProvider':
      'Root-hosted CXP server (one socket per app). Inbound mutations resolve '
      'the ACTIVE tab container through ActiveTabContainerHandle; the direct '
      'ref.read of the per-tab notifiers is the empty-workspace fallback only.',
};

/// Source roots contributing provider definitions to the read-graph. The Pro
/// overlay's `lib/` is included when this repo is checked out as the
/// `lintcrux` submodule of the Pro overlay, so a taint chain crossing the repo
/// boundary still resolves; a standalone open-core checkout scans open-core
/// only.
List<Directory> _sourceRoots() {
  final roots = <Directory>[Directory('lib')];
  final proLib = Directory('../lib');
  if (proLib.existsSync() && File('../lib/overrides.dart').existsSync()) {
    roots.add(proLib);
  }
  return roots;
}

const _coreOverridesFile =
    'lib/features/workspace/providers/tab_overrides_factory.dart';

bool _isOpenCorePath(String path) =>
    !path.startsWith('..${Platform.pathSeparator}') && !path.startsWith('../');

/// The per-tab seed set: the open-core `lintcruxTabOverridesFactory` symbols,
/// unioned with the Pro `proTabOverrides` symbols when the Pro overlay is
/// present. `proTabOverrides` lists named `Override` consts by identifier; the
/// scanner follows each to its target provider.
Set<String> _perTabSeedSet(ScopeGraph graph) {
  final seeds = graph.overrideTargets(_coreOverridesFile, null);
  expect(
    seeds,
    isNotEmpty,
    reason: 'open-core per-tab override file is missing or changed shape',
  );
  if (File('../lib/overrides.dart').existsSync()) {
    seeds.addAll(
      graph.overrideTargets('../lib/overrides.dart', 'proTabOverrides'),
    );
  }
  return seeds;
}

void main() {
  late final ScopeGraph graph;

  setUpAll(() async {
    expect(
      Directory('lib').existsSync(),
      isTrue,
      reason: 'run this test from the package root (flutter test)',
    );
    graph = await ScopeGraph.resolve(_sourceRoots());
  });

  test('resolution covered the tree', () {
    expect(
      graph.unresolved,
      isEmpty,
      reason:
          'these libraries did not resolve, so any provider they declare is '
          'invisible to the scan — run `flutter pub get` and '
          '`flutter gen-l10n`',
    );
    expect(
      graph.providers.length,
      greaterThan(70),
      reason:
          'sanity: far fewer providers than expected were registered, which '
          'means the registry, not the tree, changed',
    );
  });

  test(
    'no open-core provider reads per-tab state (directly or transitively) '
    'without being scoped per-tab',
    () {
      final perTab = _perTabSeedSet(graph);
      expect(
        perTab.length,
        greaterThan(10),
        reason:
            'sanity: expected a sizeable per-tab seed set; did the override '
            'file shape or path change?',
      );
      expect(
        perTab.map(graph.nameOf),
        containsAll(<String>[
          'currentProjectProvider',
          'violationStoreProvider',
          'selectedViolationProvider',
          'violationViewModeProvider',
          'tabDiagnosticsReportProvider',
        ]),
      );

      final reach = taintClosure(graph.reads(), perTab);

      final violations = <ScopeLeak>[];
      for (final entry in reach.entries) {
        if (perTab.contains(entry.key)) continue;
        final provider = graph.providers[entry.key]!;
        if (allowlist.containsKey(provider.name)) continue;
        // Attribute to the file carrying the leaking read, and report only
        // what this repo owns; the Pro overlay runs its own scanner over
        // its own `lib/`.
        final path = graph.pathFor(entry.value);
        if (!_isOpenCorePath(path)) continue;
        violations.add(
          ScopeLeak(
            provider.name,
            path,
            <String>[for (final k in entry.value) graph.nameOf(k)],
            graph.viaFor(entry.value),
          ),
        );
      }

      if (violations.isNotEmpty) {
        fail(formatLeakReport(violations, openCore: true));
      }
    },
  );

  test('scope-leak allowlist entries still exist as providers', () {
    final known = graph.providers.values.map((i) => i.name).toSet();
    for (final symbol in allowlist.keys) {
      expect(
        known,
        contains(symbol),
        reason:
            'allowlisted provider `$symbol` no longer exists — remove or '
            'update its entry in the allowlist.',
      );
    }
  });

  test('taint closure propagates through intermediate providers', () {
    // Guards the guard: a two-hop chain (leaf -> middle -> per-tab seed) must
    // flag BOTH hops. A direct-reads-only scan flags `middle` and lets `leaf`
    // through.
    final reads = <String, List<ProviderRead>>{
      'middle': <ProviderRead>[ProviderRead('seed', const <String>[], 'x')],
      'leaf': <ProviderRead>[ProviderRead('middle', const <String>[], 'x')],
      'unrelated': <ProviderRead>[ProviderRead('root', const <String>[], 'x')],
      // A self-read must not taint (a notifier reading its own provider).
      'self': <ProviderRead>[ProviderRead('self', const <String>[], 'x')],
    };

    final reach = taintClosure(reads, <String>{'seed'});

    expect(reach.keys, containsAll(<String>['middle', 'leaf']));
    expect(reach.keys, isNot(contains('unrelated')));
    expect(reach.keys, isNot(contains('self')));
    expect(
      reach['leaf'],
      <String>['leaf', 'middle', 'seed'],
      reason: 'the reported reach must name every hop down to the seed',
    );
  });

  group('reach analysis resolves indirect reads', () {
    late final ScopeGraph shapes;
    late final Map<String, List<ProviderRead>> reads;

    setUpAll(() async {
      shapes = await ScopeGraph.resolve(<Directory>[
        Directory('test/static/scope_leak_shapes'),
      ]);
      expect(shapes.unresolved, isEmpty);
      reads = shapes.reads();
    });

    Set<String> readsOf(String provider) {
      final key = shapes.keyOf(provider);
      expect(key, isNotNull, reason: '`$provider` was not registered');
      return <String>{
        for (final r in reads[key] ?? const <ProviderRead>[])
          shapes.nameOf(r.target),
      };
    }

    // A `Ref` captured on a field is still a `Ref`; matching on the receiver's
    // type rather than the identifier `ref` is what makes this visible.
    test('through a Ref stored on a field', () {
      expect(readsOf('storedRefProvider'), contains('seedProvider'));
    });

    test('through a helper object taking a Ref', () {
      expect(readsOf('helperObjectProvider'), contains('seedProvider'));
    });

    test('through an extension method on Ref', () {
      expect(readsOf('extensionProvider'), contains('seedProvider'));
    });

    // May-analysis: a run-time choice between providers contributes every
    // candidate, so the per-tab one cannot hide behind the branch.
    test('through a run-time provider selection', () {
      expect(readsOf('runtimeSelectedProvider'), contains('seedProvider'));
    });

    test('through a family applied to a run-time argument', () {
      expect(readsOf('familyArgProvider'), contains('familyProvider'));
    });

    // The root-hosted-store defect shape: a store bound by an `overrideWith`
    // whose builder reads a per-tab provider. The read lives in the binding,
    // not the declaration.
    test('through an overrideWith binding builder', () {
      expect(readsOf('boundStoreProvider'), contains('seedProvider'));
    });

    test('and reports the helper chain it travelled', () {
      final key = shapes.keyOf('helperObjectProvider')!;
      final read = reads[key]!.firstWhere(
        (r) => shapes.nameOf(r.target) == 'seedProvider',
      );
      expect(read.via, isNotEmpty);
    });

    test('without over-reporting a provider that reads only root state', () {
      expect(readsOf('decoyProvider'), isNot(contains('seedProvider')));
    });

    test('and the closure reaches a two-hop chain', () {
      final seed = shapes.keyOf('seedProvider')!;
      final reach = taintClosure(reads, <String>{seed});
      expect(reach.keys, contains(shapes.keyOf('leafProvider')));
      expect(reach.keys, isNot(contains(shapes.keyOf('decoyProvider'))));
    });

    // The binding read must be attributed to the file the `overrideWith`
    // builder lives in, so cross-repo ownership stays correct.
    test('and attributes a binding read to the binding file', () {
      final key = shapes.keyOf('boundStoreProvider')!;
      final read = reads[key]!.firstWhere(
        (r) => shapes.nameOf(r.target) == 'seedProvider',
      );
      expect(p.basename(read.path), 'shapes.dart');
    });
  });
}
