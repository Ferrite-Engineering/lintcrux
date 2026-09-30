// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/features/auto_reload/widgets/auto_reload_host.dart';
import 'package:lintcrux/features/project/providers/config_load_error_provider.dart';
import 'package:lintcrux/features/remote/providers/violation_selection_emitter.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/viewer/widgets/lintcrux_ide_layout.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/widgets/violation_table.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_docks.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/per_tab_startup_providers.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:lintcrux/services/trends/lint_run_completion_dispatcher_provider.dart';
import 'package:path/path.dart' as p;

/// Per-tab content widget rendered inside `crux.PaneHost`'s
/// `IndexedStack` for every open project tab.
///
/// Hosts the four-pane [LintcruxIdeLayout]:
/// * left  — rule browser (still a localized placeholder; full
///   tree-based browsing is later-phase scope)
/// * center top    — [ViolationTable]
/// * center bottom — [SourcePreviewPane]
/// * right — [InspectorPane]
///
/// On first mount, the tab's `currentProjectProvider` is hydrated from
/// the `projectPath` on its workspace payload if the explicit open
/// flow (`OpenProjectInWorkspace.openProject` /
/// `.openWorkspace`) did not already populate it. Workspace restore
/// on app launch resurrects tab metadata but does not re-load each
/// tab's `.lintcrux` project file by itself — without this hook the
/// tab would render the empty IDE shell forever even though the tab
/// strip shows the project name.
///
/// All child widgets resolve providers via Riverpod's parent-container
/// lookup. The enclosing `UncontrolledProviderScope` (supplied by
/// `crux.PaneHost`) anchors the per-tab provider container, so the
/// existing `ViolationTable`, `InspectorPane`, and `SourcePreviewPane`
/// — which already watch their respective per-tab providers
/// (`violationTableStateProvider`, `selectedViolationProvider`,
/// `currentProjectProvider`, …) — automatically see the active tab's
/// state without any explicit `tabId` wiring.
class ProjectTabContent extends ConsumerStatefulWidget {
  /// Creates a [ProjectTabContent].
  const ProjectTabContent({super.key});

  @override
  ConsumerState<ProjectTabContent> createState() => _ProjectTabContentState();
}

class _ProjectTabContentState extends ConsumerState<ProjectTabContent> {
  bool _hydrationKicked = false;

  /// Live keep-alive subscriptions on the overlay-contributed per-tab
  /// startup providers, taken against THIS tab's container.
  final List<ProviderSubscription<Object?>> _startupSubscriptions =
      <ProviderSubscription<Object?>>[];

  /// The hook list [_startupSubscriptions] were built from, so a rebuild
  /// with an unchanged list does not churn subscriptions.
  List<PerTabStartupHook>? _boundStartupHooks;

  /// Subscribes to every per-tab startup provider, replacing any prior
  /// subscription set when the hook list changes.
  ///
  /// A `read` would be insufficient: an un-listened provider is
  /// disposable, so a listener realized by `read` alone can be collected
  /// again and stop observing this tab before the first run completes.
  /// The subscription is taken on the tab's own `ProviderContainer` so
  /// the listeners resolve this tab's per-tab providers rather than the
  /// empty root-scope instances.
  void _bindStartupHooks(List<PerTabStartupHook> hooks) {
    final bound = _boundStartupHooks;
    if (bound != null && bound.length == hooks.length) {
      var same = true;
      for (var i = 0; i < bound.length; i++) {
        if (!identical(bound[i], hooks[i])) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    for (final sub in _startupSubscriptions) {
      sub.close();
    }
    _startupSubscriptions.clear();
    final container = ProviderScope.containerOf(context, listen: false);
    for (final hook in hooks) {
      // Empty callback on purpose: the subscription exists to pin the
      // provider, not to observe its value.
      _startupSubscriptions.add(container.listen<Object?>(hook, (_, _) {}));
    }
    _boundStartupHooks = List<PerTabStartupHook>.unmodifiable(hooks);
  }

  @override
  void dispose() {
    for (final sub in _startupSubscriptions) {
      sub.close();
    }
    _startupSubscriptions.clear();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Kick once on first frame so the tab id and workspace are both
    // available. `_maybeHydrate` is safe to call multiple times — it
    // short-circuits if the project is already loaded.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeHydrate());
  }

  Future<void> _maybeHydrate() async {
    if (_hydrationKicked) return;
    if (!mounted) return;
    // Bail if the project is already loaded (the explicit-open
    // flow in `OpenProjectInWorkspace.openProject` got there first).
    if (ref.read(currentProjectProvider) != null) {
      _hydrationKicked = true;
      return;
    }
    // Tab id is supplied by the per-tab container's
    // `tabIdProvider.overrideWithValue` (see crux_workspace's
    // `TabContainerManager`). Tests that mount this widget outside a
    // per-tab container will trigger the default body's throw — bail
    // quietly so unit tests don't have to construct workspace plumbing
    // they don't otherwise need.
    final crux.TabId tabId;
    try {
      tabId = ref.read(crux.tabIdProvider);
    } on Object {
      _hydrationKicked = true;
      return;
    }
    // Workspace can still be `AsyncLoading` at the first post-frame
    // tick (the load is genuinely async). Don't flip `_hydrationKicked`
    // until we have a workspace in hand — the `ref.listen` registered
    // in `build` will call back here once the workspace is ready.
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null) return;
    final tab = workspace.tabs.where((t) => t.id == tabId).firstOrNull;
    if (tab == null) {
      // Tab id resolves but no matching workspace tab — workspace was
      // hydrated without this tab id (e.g. lifecycle race after a tab
      // closed). Treat as terminal.
      _hydrationKicked = true;
      return;
    }
    _hydrationKicked = true;
    const service = ProjectFileService();
    try {
      final read = await service.read(tab.payload.projectPath);
      // Anchor relative paths at the `.lintcrux` directory so engines
      // resolve sources regardless of the app's working directory.
      final project = resolveProjectPaths(
        read,
        p.dirname(tab.payload.projectPath),
      );
      if (!mounted) return;
      ref
          .read(currentProjectProvider.notifier)
          .load(project, projectFilePath: tab.payload.projectPath);
      // Restore the tab's persisted filter / sort state from the
      // workspace payload so the violation table opens with the
      // user's last view (preset selection, search text, severity
      // chips, sort column / order) instead of an empty default.
      final tableNotifier = ref.read(violationTableStateProvider.notifier)
        ..setRuleSubstring(tab.payload.ruleSubstring)
        ..setFileGlob(tab.payload.fileGlob)
        ..setSort(tab.payload.sortColumn, ascending: tab.payload.sortAscending);
      tab.payload.activeSeverities.forEach(tableNotifier.toggleSeverity);
      tab.payload.activeEngineIds.forEach(tableNotifier.toggleEngine);
      // Kick off the initial run so the violation table populates
      // without requiring the user to press F5 first. Mirrors the
      // explicit-open flow in OpenProjectInWorkspace.openProject.
      unawaited(ref.read(lintRunProvider.notifier).runAll(project));
    } on ProjectFileException {
      if (!mounted) return;
      // This catch only runs on the workspace-restore hydration path at
      // launch: the explicit File → Open / CLI / session flow populates
      // `currentProjectProvider` first and bails at the guard above, so a
      // failure here is always a silently auto-reopened recent project.
      // When its `.lintcrux` file has since vanished (a deleted temp dir, a
      // moved checkout) we must not slam the user into the full-screen
      // "Couldn't load this project" surface — that hard error is reserved
      // for a file the user explicitly asked to open. Instead we drop the
      // dead tab, which falls back to the empty landing state and, because
      // the workspace auto-saves, evicts the stale entry so it is not
      // re-reopened on the next launch.
      unawaited(ref.read(workspaceProvider.notifier).closeTab(tabId));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Realize this tab's run-completion dispatcher so its `start()` runs
    // and it subscribes to THIS tab's per-tab lint-run lifecycle bus
    // before any run completes. Open-core's default is the no-op
    // dispatcher (harmless); the Pro overlay registers
    // `ProLintRunCompletionDispatcher` per-tab via `extraTabOverridesProvider`
    // so trend tracking snapshots the completing tab's own violation store.
    // This is the per-tab analogue of `_EagerStartupGate` in `app.dart`,
    // which realizes the root-scoped one-shot providers. Watching a plain
    // `Provider` returns a cached instance, so it causes no rebuild churn.
    ref
      ..watch(lintRunCompletionDispatcherProvider)
      // Realize this tab's live selection broadcast (CXP `notify_selection`)
      // against THIS tab's selection. Watching a plain `Provider` returns a
      // cached instance, so it causes no rebuild churn.
      ..watch(violationSelectionEmitterProvider)
      // Re-attempt hydration whenever the workspace document arrives
      // (initial load) or rebuilds. The `_hydrationKicked` flag inside
      // `_maybeHydrate` short-circuits once it actually runs, so this
      // listen-and-retry loop is safe to fire on every workspace change.
      ..listen<AsyncValue<Workspace>>(workspaceProvider, (_, next) {
        if (next.hasValue) {
          unawaited(_maybeHydrate());
        }
      });
    // Pin the overlay-contributed per-tab startup providers to THIS
    // tab's container, so side-effecting listeners (CXP selection
    // emitter, bookmark stale-detection, Verible auto-run) observe this
    // tab's per-tab providers rather than the empty root-scope instances
    // and stay alive for the tab's whole lifetime. The hook list itself
    // is root configuration; re-binding is a no-op when it is unchanged.
    _bindStartupHooks(ref.watch(perTabStartupProvidersProvider));
    final loadError = ref.watch(configLoadErrorProvider);
    if (loadError != null) {
      return _ProjectLoadErrorView(error: loadError);
    }
    // Each region is a CruxDock: Rules and Source render as titled headers
    // (the auto-hiding strip); the right dock tabs Details with the
    // on-demand Cross-Probe panel.
    return AutoReloadHost(
      child: LintcruxIdeLayout(
        ruleBrowserBuilder: (context, _) => const LintcruxLeftDock(),
        violationsBuilder: (context, _) => const ViolationTable(),
        violationDetailsBuilder: (context, _) => const LintcruxRightDock(),
        runLogBuilder: (context, _) => const LintcruxBottomDock(),
      ),
    );
  }
}

/// Empty state rendered in place of the IDE layout when the tab's
/// `.lintcrux` project file could not be loaded (file missing,
/// permission denied, schema invalid, …). The failing path and the
/// loader's reason are rendered verbatim so the user can act on the
/// actual error rather than a generic "something went wrong".
class _ProjectLoadErrorView extends StatelessWidget {
  const _ProjectLoadErrorView({required this.error});

  final ConfigLoadError error;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  color: scheme.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.configLoadFailedTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.configLoadFailedPathLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  error.path,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.configLoadFailedReasonLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  error.reason,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.configLoadFailedHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
