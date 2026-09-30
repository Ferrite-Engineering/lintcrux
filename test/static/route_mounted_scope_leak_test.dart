// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LintCrux's enablement of the ROUTE-MOUNTED per-tab scope-leak guard.
//
// The rule itself — what it catches, its three accepted forms of re-binding,
// and the seven things it deliberately does NOT catch — lives once in
// crux-shared, next to the scanner it depends on. Read that file first; this
// one only supplies LintCrux's source roots and per-tab seed list.
//
// Why the rule exists, in LintCrux's own terms: a dialog route is a child of
// the Navigator, which sits ABOVE the per-tab `UncontrolledProviderScope`. A
// widget mounted from `showDialog` that reads a per-tab provider through
// `WidgetRef` therefore resolves the ROOT container, where no project is
// loaded. The sibling `per_tab_provider_scope_leak_test` cannot see this: it
// analyses the *provider* graph, and this is a *widget*.
//
// LintCrux had exactly this defect. `_FilterPresetManageDialog` watched
// `savedFilterPresetsProvider` — per-tab, re-bound by
// `lintcruxTabOverridesFactory` — with its own `ref` and no scope on the path,
// so "Manage presets…" rendered "No saved presets yet." over a dropdown that
// was visibly listing several, and its delete affordance wrote to the root
// notifier so nothing disappeared (fixed in `d746cb5`). It was invisible to
// the existing tests because every one of them used a single `ProviderScope`,
// so the dropdown and the dialog shared a container.
//
// LintCrux's re-binding shape is the helper form: `wrapInActiveTabScope(
// context, child)` (`lib/features/workspace/services/active_tab_scope.dart`),
// which the guard resolves one hop and accepts.
//
// The allowlist is deliberately empty. A violation is fixed, not listed.

import 'dart:io';

import '../../crux-shared/packages/crux_workspace/test/static/route_mounted_scope_leak_guard.dart';

void main() {
  defineRouteMountedScopeLeakGuard(
    sourceRoots: _sourceRoots,
    // Same seed sources as the sibling provider guard: the open-core per-tab
    // override factory, unioned with the Pro overlay's `proTabOverrides` when
    // it is present — the Pro list reaches the tab container through
    // `extraTabOverridesProvider`, so a provider re-bound by either list is
    // per-tab in a real tab container.
    seedOverrideSpecs: const [
      'lib/features/workspace/providers/tab_overrides_factory.dart',
      '../lib/overrides.dart#proTabOverrides',
    ],
    bootstrapHint: 'run `flutter pub get` in lintcrux/',
  );
}

/// Open-core `lib/`, plus the Pro overlay's `lib/` when this checkout is the
/// Pro overlay's submodule — so a taint chain crossing the repo boundary
/// still resolves. A standalone open-core checkout scans open-core only.
List<Directory> _sourceRoots() {
  final roots = <Directory>[Directory('lib')];
  final proLib = Directory('../lib');
  if (proLib.existsSync() && File('../lib/overrides.dart').existsSync()) {
    roots.add(proLib);
  }
  return roots;
}
