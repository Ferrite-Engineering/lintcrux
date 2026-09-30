// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart' as crux_telemetry;
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_provider.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';

/// LintCrux-flavored typedef binding `crux_workspace`'s generic
/// `Workspace<P>` to LintCrux's per-tab payload.
typedef Workspace = crux.Workspace<LintcruxTabPayload>;

/// LintCrux-flavored typedef binding `crux_workspace`'s generic
/// `WorkspaceTab<P>` to LintCrux's per-tab payload.
typedef WorkspaceTab = crux.WorkspaceTab<LintcruxTabPayload>;

/// LintCrux-flavored typedef binding `crux_workspace`'s generic
/// `WorkspaceService<P>` to LintCrux's per-tab payload.
typedef WorkspaceService = crux.WorkspaceService<LintcruxTabPayload>;

/// Singleton [WorkspaceService] used by [LintcruxWorkspaceNotifier].
/// Tests override this with a service that points at a temp
/// directory or captures saves.
final Provider<WorkspaceService> workspaceServiceProvider =
    Provider<WorkspaceService>((ref) {
      return WorkspaceService(codec: const LintcruxWorkspaceCodec());
    });

/// Root-scope provider holding LintCrux's workspace document.
///
/// The notifier type is [LintcruxWorkspaceNotifier] — a thin subclass
/// of `crux_workspace`'s [crux.WorkspaceNotifier] that:
///
/// * Resolves the [WorkspaceService] from
///   [workspaceServiceProvider] inside [LintcruxWorkspaceNotifier.build]
///   rather than at construction (Riverpod requirement). A
///   delegating shim is passed to super so the package's `final`
///   service field stays satisfied.
/// * Does NOT add LintCrux-named wrappers over the package's
///   mutation surface. Call sites use the package method names
///   directly: `openTab` / `closeTab` / `reorderTab` /
///   `moveTabToPane` / `setActiveTab` / `setActivePane` /
///   `splitPaneRight` / `closePane` / `focusOtherPane` /
///   `resetWorkspace` / `replaceWith` / `saveAs` / `loadFrom` /
///   `flushPendingSave` / `updateTabPayload` /
///   `updateTabDisplayName`.
final AsyncNotifierProvider<LintcruxWorkspaceNotifier, Workspace>
workspaceProvider = AsyncNotifierProvider<LintcruxWorkspaceNotifier, Workspace>(
  LintcruxWorkspaceNotifier.new,
);

/// LintCrux subclass of [crux.WorkspaceNotifier] handling the late
/// service binding the package expects to be set at construction but
/// LintCrux can only resolve once the notifier is mounted.
class LintcruxWorkspaceNotifier
    extends crux.WorkspaceNotifier<LintcruxTabPayload> {
  /// Creates the notifier. The package's required `service` field is
  /// satisfied by a [_LateBoundWorkspaceService] delegating shim
  /// whose target is bound inside [build].
  LintcruxWorkspaceNotifier() : super(service: _LateBoundWorkspaceService()) {
    _shim = service as _LateBoundWorkspaceService;
  }

  late final _LateBoundWorkspaceService _shim;

  bool _launchRestoreDeclined = false;

  /// One-shot guard on `workspace.restored`. [build] can re-run (provider
  /// invalidation, hot restart) and a second "restored" from the same launch
  /// would inflate the very count the event exists to report.
  bool _emittedRestored = false;

  /// The loaded workspace, or `null` while the notifier is still building or
  /// in error. `AsyncNotifier.state` is typed `AsyncValue<Workspace>` and the
  /// generic parameter defeats `valueOrNull`'s inference here, so the unwrap
  /// is spelled out once.
  Workspace? get stateOrNull {
    final value = state;
    return value is AsyncData<Workspace> ? value.value : null;
  }

  /// The telemetry sink, resolved **per event** rather than cached in
  /// [build].
  ///
  /// It was cached, because several of the overrides below fire during a
  /// `mutate` and must not touch `ref` afterwards — which the `ref.mounted`
  /// guard handles directly, and more honestly. What caching cost is why it is
  /// gone: `telemetryServiceProvider` is not constant for the life of a
  /// session. The consent store publishes `unset` synchronously and reads the
  /// persisted value back asynchronously, so at the moment this notifier
  /// builds — a cold start — the gate has not seen the user's stored answer
  /// yet and resolves the no-op. Holding that froze the first frame's verdict
  /// for the whole session: an installation that had consented recorded
  /// nothing. Every `_emit` below stays unconditional; the read is a map
  /// lookup and the no-op's `record` is still allocation-free.
  void _emit(String name, [Map<String, Object?>? properties]) {
    if (!ref.mounted) return;
    ref
        .read(crux_telemetry.telemetryServiceProvider)
        .record(crux_telemetry.TelemetryEvent(name, properties: properties));
  }

  /// Whether this launch declined to rehydrate the persisted workspace
  /// document because the user turned "Restore tabs on launch" off.
  ///
  /// Read by [ProjectWorkspaceSync]: the crux_workspace document is not the
  /// only thing that can put a tab back. The Pro `ProjectRegistry` persists
  /// its own open-project list, and the sync's registry-originated
  /// activation step opens a tab for the registry's active project when no
  /// tab shows it. Left ungated, that hands the user their tabs back through
  /// the side door on the very launch they asked for a clean start.
  ///
  /// Only meaningful once the notifier has built; `false` before that, which
  /// is the correct reading (nothing has been declined yet).
  bool get launchRestoreDeclined => _launchRestoreDeclined;

  /// Consults the "Restore tabs on launch" preference before the workspace
  /// document is loaded.
  ///
  /// Reads [launchRestoreDecisionProvider] **synchronously**. It must not
  /// await storage here: `SharedPreferences.getInstance()` replies on the
  /// real event loop, which the fake-async zone a `testWidgets` body runs in
  /// never advances, so a future awaited on this path before the first pump
  /// never completes and every workspace-touching widget test times out
  /// instead of failing. `bootstrap` resolves the preference once, before
  /// `runApp`, and overrides the provider with the answer — see the long note
  /// on [launchRestoreDecisionProvider] for the two nearby workarounds that
  /// are also wrong.
  @override
  Future<bool> shouldRestoreOnLaunch() async {
    final restore = ref.read(launchRestoreDecisionProvider);
    _launchRestoreDeclined = !restore;
    return restore;
  }

  @override
  Future<Workspace> build() async {
    final realService = ref.read(workspaceServiceProvider);
    _shim.attach(realService);
    final loaded = await super.build();
    if (!_emittedRestored) {
      _emittedRestored = true;
      // Emitted even when `shouldRestoreOnLaunch` declined, in which case
      // `loaded` is the empty document and the counts are 0 tabs / 1 pane.
      // That is the honest reading: the launch *did* resolve a workspace, and
      // a build that only reported the restoring case would make "how many
      // tabs do people keep" a survey of the people who kept any.
      _emit('workspace.restored', <String, Object?>{
        'tabs': loaded.tabs.length,
        'panes': loaded.panes.length,
      });
    }
    return loaded;
  }

  // ── Telemetry instrumentation ─────────────────────────────────────────────
  //
  // Each override wraps the package method rather than the call sites that
  // reach it, for the reason WaveCrux's equivalents do: LintCrux's workspace
  // mutations are driven from `app.dart`, from `ViewerScaffold`, from the
  // opener service and from the CLI launch path, and a counter maintained at
  // four call sites is a counter that goes stale at the fifth. The overrides
  // also carry the no-op guards the package's own methods have — a "split"
  // that found the workspace already split, or a `closePane` on the sole
  // pane, is not a thing the user did.

  @override
  Future<crux.TabId> openTab({
    required String displayName,
    required LintcruxTabPayload payload,
    crux.PaneId? paneId,
    bool dedupe = true,
  }) async {
    // Resolved BEFORE the call: on a dedupe hit the package short-circuits to
    // `setActiveTab`, which is "the user re-focused a project they already had
    // open" and not a tab open.
    final deduped = dedupe && tabWithSameIdentityAs(payload) != null;
    final id = await super.openTab(
      displayName: displayName,
      payload: payload,
      paneId: paneId,
      dedupe: dedupe,
    );
    if (!deduped) {
      final current = stateOrNull;
      _emit('tab.opened', <String, Object?>{
        'tabs': current?.tabs.length ?? 0,
        'panes': current?.panes.length ?? 0,
      });
    }
    return id;
  }

  @override
  Future<crux.PaneId> splitPaneRight() async {
    final wasSplit = (stateOrNull?.panes.length ?? 0) >= 2;
    final id = await super.splitPaneRight();
    if (!wasSplit) _emit('pane.split');
    return id;
  }

  @override
  Future<void> closePane(crux.PaneId paneId) async {
    final before = stateOrNull;
    final willClose =
        before != null &&
        before.panes.length >= 2 &&
        before.panes.any((pane) => pane.id == paneId);
    await super.closePane(paneId);
    if (willClose) _emit('pane.closed');
  }

  @override
  Future<void> resetWorkspace() async {
    await super.resetWorkspace();
    _emit('workspace.reset');
  }

  @override
  Future<void> saveAs(String path) async {
    // After the await, so a write that threw (the caller surfaces a
    // save-failure dialog) is not counted as a save.
    await super.saveAs(path);
    _emit('workspace.named.saved');
  }

  @override
  Future<Workspace> loadFrom(String path) async {
    final loaded = await super.loadFrom(path);
    _emit('workspace.named.opened', <String, Object?>{
      'tabs': loaded.tabs.length,
      'panes': loaded.panes.length,
    });
    return loaded;
  }
}

/// Delegating [crux.WorkspaceService] passed to
/// [crux.WorkspaceNotifier]'s super constructor.
///
/// The package's notifier holds its service as a `final` field set at
/// construction time, but LintCrux's real service is resolved through
/// [workspaceServiceProvider] which can only be read after the
/// notifier is mounted (`build` time). The shim bridges those two
/// lifetimes: super's constructor sees a fully-typed
/// [crux.WorkspaceService] instance immediately; every call routes
/// through [_delegate] which the subclass binds inside [build] via
/// [attach].
///
/// All methods on the package's service surface are overridden to
/// delegate. The unbound state never reaches a real call site because
/// [build] binds before any mutation can fire.
class _LateBoundWorkspaceService
    extends crux.WorkspaceService<LintcruxTabPayload> {
  _LateBoundWorkspaceService() : super(codec: const LintcruxWorkspaceCodec());

  crux.WorkspaceService<LintcruxTabPayload>? _delegate;

  /// Binds the real service. Called once from
  /// [LintcruxWorkspaceNotifier.build]. Kept as an imperative method
  /// rather than a Dart setter so the call site reads `_shim.attach(...)`
  /// matching the equivalent `_LateBoundWorkspaceService.attach` in
  /// WaveCrux's `WaveCruxWorkspaceNotifier`.
  // ignore: use_setters_to_change_properties
  void attach(crux.WorkspaceService<LintcruxTabPayload> delegate) {
    _delegate = delegate;
  }

  crux.WorkspaceService<LintcruxTabPayload> get _live {
    final d = _delegate;
    if (d == null) {
      throw StateError(
        '_LateBoundWorkspaceService: attach() not yet called. '
        'LintcruxWorkspaceNotifier.build() should bind the real '
        'service before any other method is invoked.',
      );
    }
    return d;
  }

  @override
  Future<Workspace> load() => _live.load();

  @override
  Future<void> save(Workspace workspace) => _live.save(workspace);

  @override
  Future<void> saveToPath(String path, Workspace workspace) =>
      _live.saveToPath(path, workspace);

  @override
  Future<Workspace> loadFromPath(String path) => _live.loadFromPath(path);

  @override
  Future<void> clear() => _live.clear();

  @override
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.lintcrux-session',
  }) => _live.sidecarPathFor(tabId, extension: extension);

  @override
  Future<void> deleteSidecar(
    String tabId, {
    String extension = '.lintcrux-session',
  }) => _live.deleteSidecar(tabId, extension: extension);
}
