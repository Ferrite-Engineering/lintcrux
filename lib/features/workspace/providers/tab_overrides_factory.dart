// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/features/auto_reload/providers/auto_reload_controller.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/issue_reporter/providers/issue_session_context.dart';
import 'package:lintcrux/features/project/providers/config_load_error_provider.dart';
import 'package:lintcrux/features/remote/providers/violation_selection_emitter.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/violations/providers/present_engine_ids_provider.dart';
import 'package:lintcrux/features/violations/providers/saved_filter_presets_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_view_mode_provider.dart';
import 'package:lintcrux/services/bookmarks/bookmarked_violations_count_provider.dart';
import 'package:lintcrux/services/filter_presets/active_filter_preset_provider.dart';
import 'package:lintcrux/services/lint_cache/lint_cache_stats_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/run/lint_run_lifecycle.dart';
import 'package:lintcrux/services/verible/verible_availability_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// Produces the per-tab override list applied on top of
/// `crux_workspace.tabIdProvider` for a freshly-created tab
/// `ProviderContainer`.
///
/// Every provider listed here is **per-tab** under the workspace
/// model: a fresh instance per tab so two tabs viewing two
/// `.lintcrux` projects each carry their own loaded project,
/// violation store, run state, table filter / sort, selection
/// cursor, saved-filter-preset selection, auto-reload watcher set,
/// and pending-reload flag. Inactive tabs' containers are kept alive
/// by [crux.PaneHost]'s `IndexedStack` so switching tabs never
/// re-loads a project or loses state.
///
/// Providers NOT listed here stay root-scoped: they resolve through
/// the standard Riverpod parent-container lookup. Examples:
/// `engineRegistryProvider`, `appSettingsProvider`, `appRouterProvider`,
/// `cliArgsProvider`, `recentProjectsProvider`, `shortcutBindingsProvider`,
/// `appLicenseTierProvider` (when added), the panel-layout state, the
/// workspace provider itself.
///
/// Each entry uses `overrideWith(NotifierType.new)` to give the child
/// container its own instance. This is required even for a provider
/// that only derives from the per-tab providers above: Riverpod does
/// NOT auto-fork an un-overridden provider per child container — it
/// resolves to the single root instance, which would `ref.watch` the
/// ROOT's `violationStoreProvider` (empty/no-op) rather than this tab's.
/// `visibleViolationsProvider` (below) is a case in point.
List<Override> lintcruxTabOverridesFactory(crux.TabId tabId) {
  return <Override>[
    // The current project (loaded `LintProject` model). Each tab
    // owns the project it was opened with.
    currentProjectProvider.overrideWith(CurrentProjectNotifier.new),

    // Per-tab project-load error state. Each tab carries its own
    // load failure so two tabs (one good, one broken) don't share
    // empty-state error chrome.
    configLoadErrorProvider.overrideWith(ConfigLoadErrorNotifier.new),

    // Engine output for this tab. Each tab gets a fresh
    // `InMemoryViolationStore` so two tabs never blend their
    // violations.
    violationStoreProvider.overrideWith((ref) {
      final store = InMemoryViolationStore();
      ref.onDispose(store.dispose);
      return store;
    }),

    // Lint-run orchestrator state for this tab.
    lintRunProvider.overrideWith(LintRunNotifier.new),

    // Lint-run lifecycle bus for this tab. Per-tab so this tab's
    // `LintRunNotifier` emits its run-boundary ticks only to observers
    // scoped to the SAME tab — specifically the Pro trend dispatcher,
    // which (also per-tab) subscribes to this bus and snapshots THIS
    // tab's `violationStoreProvider` on completion. A single shared root
    // bus would let one tab's completion trigger every tab's dispatcher
    // against the wrong (root / empty) violation store — the trend-
    // tracking "records zero data points" defect. The completion EVENT
    // bus (`lintRunCompletionEventBusProvider`) stays root so all tabs'
    // completions still aggregate to the one app-wide trend store.
    lintRunLifecycleBusProvider.overrideWith((ref) {
      final bus = LintRunLifecycleBus();
      ref.onDispose(bus.dispose);
      return bus;
    }),

    // Selection cursor (inspector / source preview).
    selectedViolationProvider.overrideWith(SelectedViolationNotifier.new),

    // Violation-table filter + sort + multi-select state.
    violationTableStateProvider.overrideWith(ViolationTableNotifier.new),

    // Live derived list — re-evaluates inside the child container
    // because it `ref.watch`es the per-tab `violationStoreProvider`
    // and `violationTableStateProvider`.
    visibleViolationsProvider.overrideWith(VisibleViolationsNotifier.new),

    // Engine ids present in the loaded report — drives the per-engine
    // filter chips. Per-tab for the same reason as
    // `visibleViolationsProvider`: it subscribes to the per-tab
    // `violationStoreProvider`'s event stream, so it must bind to this
    // tab's store rather than the root store.
    presentEngineIdsProvider.overrideWith(PresentEngineIdsNotifier.new),

    // Saved filter presets — the tab's project `filterPresets`, written
    // back to its `.lintcrux`. Per-tab so each tab reads its own project
    // and tracks its own active selection.
    savedFilterPresetsProvider.overrideWith(SavedFilterPresetsNotifier.new),

    // Active FilterPreset. Per-tab so two tabs can
    // each apply their own preset (or no preset) independently. The
    // overlay math lives in
    // `lib/services/filter_presets/filter_preset_overlay.dart` and is
    // applied by `VisibleViolationsNotifier`.
    activeFilterPresetProvider.overrideWith(ActiveFilterPresetNotifier.new),

    // File-watcher controller that re-runs engines on source change.
    autoReloadControllerProvider.overrideWith(AutoReloadController.new),

    // "Files changed — re-run?" flag in prompt mode.
    pendingReloadProvider.overrideWith(PendingReloadNotifier.new),

    // Live selection broadcast over CXP. Per-tab so its listener observes
    // this tab's `selectedViolationProvider`; watched from the tab body.
    violationSelectionEmitterProvider.overrideWith(
      ViolationSelectionEmitter.new,
    ),

    // Violation-table view mode (All / Only new / Only resolved). Per-tab
    // so toggling "Only new" in one tab never flips another tab's table.
    // The per-tab `visibleViolationsProvider` derivation reads it.
    violationViewModeProvider.overrideWith(ViolationViewModeNotifier.new),

    // Diagnostics reports. Per-tab because they read the per-tab
    // `currentProjectProvider` / `lintRunProvider` / `violationStoreProvider`;
    // a root-scope instance would always report "no project loaded" /
    // zero violations. The diagnostics dialogs mount inside the active
    // tab's scope (`wrapInActiveTabScope`), so their reads resolve here.
    tabDiagnosticsReportProvider.overrideWith(buildTabDiagnosticsReport),
    appDiagnosticsReportProvider.overrideWith(buildAppDiagnosticsReport),

    // Beta issue reporter's Session State snapshot. Per-tab because it reads
    // the per-tab `currentProjectProvider` / `violationStoreProvider` / table
    // state; a root-scope instance would report "no project loaded, 0
    // violations" for a tab plainly showing a full violations table. The
    // reporter is opened inside the active tab's scope for the same reason
    // (see `LintcruxIssueReporter.open`).
    cruxIssueSessionContextProvider.overrideWith(
      buildLintcruxIssueSessionContext,
    ),

    // Derivations over the project-keyed extension-point stores. The
    // stores themselves are overridden per-tab by the Pro overlay (via
    // `extraTabOverridesProvider` → `proTabOverrides`); these open-core
    // derivations are re-bound here so their `ref.watch` of the store
    // resolves the tab's binding instead of hoisting to the root
    // container's no-op default. In a pure open-core build the tab
    // binding still resolves the root no-op through parent lookup, so
    // this is behavior-neutral without the Pro overlay.
    bookmarkedViolationsCountProvider.overrideWith(
      buildBookmarkedViolationsCount,
    ),
    lintCacheStatsProvider.overrideWith(buildLintCacheStats),
    lintCacheInvalidationsProvider.overrideWith(buildLintCacheInvalidations),
    veribleAvailabilityProvider.overrideWith(buildVeribleAvailability),
  ];
}

/// Open-core → Pro extension-point seam for **per-tab** provider
/// overrides.
///
/// Root-scope Pro overrides live in the Pro `proOverrides` list; providers
/// whose `ref` must resolve a tab's own per-tab state (e.g. the Pro trend
/// dispatcher, whose `ref.read(violationStoreProvider)` must hit the
/// completing tab's `InMemoryViolationStore` rather than the empty root
/// one) belong here instead — a root-scope override of such a provider
/// silently reads the root container's empty state. This is the general
/// per-tab scope-leak class the static guard in `test/static/
/// per_tab_provider_scope_leak_test.dart` exists to catch; see the
/// open-core ARCHITECTURE §10 "Per-tab scope contract" for the full
/// binding rules.
///
/// The default is an empty list. [WorkspaceRoot] reads this provider at
/// `initState` and appends it to `lintcruxTabOverridesFactory(tabId)`
/// (after the open-core list, so later overrides win) when building the
/// [crux.TabContainerManager]. The Pro overlay overrides it via
/// `proOverrides` (`extraTabOverridesProvider.overrideWithValue(
/// proTabOverrides)`). This is the LintCrux analogue of NetCrux's
/// `bootstrap(extraTabOverrides:)` parameter — a provider rather than a
/// bootstrap arg because here the `TabContainerManager` is owned by the
/// [WorkspaceRoot] widget, not constructed in `bootstrap`.
final Provider<List<Override>> extraTabOverridesProvider =
    Provider<List<Override>>((_) => const <Override>[]);
