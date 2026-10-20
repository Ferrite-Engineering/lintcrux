// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/diagnostics/diagnostics_report.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/features/yosys/widgets/yosys_diagnostics_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/yosys/yosys_diagnostics_provider.dart';

/// Right-side drawer surfacing per-tab diagnostics.
///
/// Opened via [open] as a right-aligned NON-MODAL [OverlayEntry] — the WaveCrux
/// Tab Diagnostics drawer pattern — from Cmd/Ctrl+Shift+I, the Tools menu, and
/// the command palette. The former modal-`Dialog` mount installed a full-screen
/// barrier that blocked every surface outside the drawer while it was open; the
/// overlay entry leaves the underlying chrome fully interactive, and Escape
/// closes it.
class TabDiagnosticsDrawer extends ConsumerWidget {
  /// Creates a [TabDiagnosticsDrawer].
  ///
  /// [onClose] backs the header's close button. Null when the drawer is
  /// hosted somewhere that dismisses it another way (a test, or a future
  /// docked placement).
  const TabDiagnosticsDrawer({super.key, this.onClose});

  /// Dismisses the drawer. See the close button in the header.
  final VoidCallback? onClose;

  /// Opens the drawer as a right-aligned non-modal overlay.
  ///
  /// Inserts an [OverlayEntry] into the ACTIVE tab's navigator overlay
  /// ([ActiveTab.navigatorFor]) rather than pushing a modal dialog route,
  /// so the drawer is built under the tab's one provider scope and reads
  /// the tab's report (a root-scope mount would render the "no project
  /// loaded" empty state even with a tab active). When another tab becomes
  /// active the drawer moves to that tab's overlay, so it keeps following
  /// the active tab. With no workspace above [context] (the web viewer) it
  /// goes on the root overlay and shows its own empty state.
  ///
  /// Returns when the drawer is closed (close via Escape or the close
  /// button, the no-tabs-remaining auto-dismiss, or diagnostics turned off).
  ///
  /// Re-entrancy guarded via the suite-shared [ModalGuard]
  /// (Cmd/Ctrl+Shift+I auto-repeat, or the menu while the drawer is
  /// already up, must not stack a second drawer). One key for the window:
  /// there is one drawer, and it follows the active tab.
  static Future<void> open(BuildContext context) {
    return ModalGuard.run('tabDiagnostics', () async {
      final drawer = _TabDiagnosticsDrawerPlacement(context)..show();
      await drawer.closed;
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final report = ref.watch(tabDiagnosticsReportProvider);
    return Drawer(
      width: 380,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.diagnosticsTabDrawerTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  // Escape closes the drawer, and used to be the ONLY way to.
                  // A non-modal overlay with no visible dismiss reads as stuck:
                  // there is no scrim to click away and nothing on screen says
                  // Escape works. A keyboard-only exit is a shortcut, not an
                  // affordance.
                  if (onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l10n.diagnosticsCloseDrawer,
                      onPressed: onClose,
                    ),
                  Consumer(
                    builder: (context, ref, _) {
                      final yosysState = ref.watch(yosysDiagnosticsProvider);
                      return IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: l10n.diagnosticsCopyTabReport,
                        onPressed: report == null
                            ? null
                            : () => Clipboard.setData(
                                ClipboardData(
                                  text: _buildReportText(
                                    report,
                                    yosysState,
                                  ),
                                ),
                              ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: report == null
                  ? Center(child: Text(l10n.diagnosticsNoProjectLoaded))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _Section(
                          title: l10n.diagnosticsSectionProjectInfo,
                          rows: [
                            _row('path', report.projectPath),
                            _row('source files', '${report.sourceFileCount}'),
                            if (report.lastRunWallMs != null)
                              _row('last run', '${report.lastRunWallMs} ms'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _Section(
                          title: l10n.diagnosticsSectionEngines,
                          rows: [
                            for (final engine in report.engines)
                              ..._engineRows(engine),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _Section(
                          title: l10n.diagnosticsSectionViolationStats,
                          rows: [
                            for (final engine in report.engines) ...[
                              _row(engine.engineId, ''),
                              for (final s in Severity.values)
                                if (engine.severityCounts[s] != null)
                                  _row(
                                    '  ${s.name}',
                                    '${engine.severityCounts[s]}',
                                  ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        const YosysDiagnosticsSection(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// One row per value the report measured for [engine]; an absent value
  /// produces no row rather than an empty or stand-in one.
  List<MapEntry<String, String>> _engineRows(EngineDiagnostics engine) {
    final id = engine.engineId;
    return [
      if (engine.binary != null) _row('$id binary', engine.binary!),
      if (engine.version != null) _row('$id version', engine.version!),
      if (engine.durationMs != null)
        _row('$id duration', '${engine.durationMs} ms'),
    ];
  }

  MapEntry<String, String> _row(String k, String v) => MapEntry(k, v);
}

/// Keeps the drawer's one overlay entry on the active tab's navigator.
///
/// The entry is built under whichever tab's scope owns that navigator, so
/// following the active tab means moving the entry: when the workspace's
/// active tab changes (a switch, or the drawer's own tab closing) the entry
/// is re-inserted into the new active tab's overlay after the frame that
/// built it. No tab left closes the drawer.
class _TabDiagnosticsDrawerPlacement {
  _TabDiagnosticsDrawerPlacement(BuildContext callerContext)
    : _navigators = callerContext
          .getInheritedWidgetOfExactType<WorkspaceRootScope>()
          ?.tabNavigators,
      _rootOverlay = _rootOverlayOf(callerContext);

  /// The routerDelegate NAVIGATOR's own context (the dispatch path hands it
  /// over) has its Overlay as a descendant, not an ancestor, so an
  /// ancestor-only Overlay.of lookup finds nothing there: resolve the
  /// overlay through the navigator itself in that case.
  static OverlayState _rootOverlayOf(BuildContext context) {
    final navigator =
        context is StatefulElement && context.state is NavigatorState
        ? context.state as NavigatorState
        : Navigator.maybeOf(context, rootNavigator: true);
    return navigator?.overlay ?? Overlay.of(context, rootOverlay: true);
  }

  final crux.CruxTabNavigators? _navigators;
  final OverlayState _rootOverlay;
  final Completer<void> _closed = Completer<void>();
  ProviderSubscription<AsyncValue<Workspace>>? _subscription;
  OverlayEntry? _entry;
  crux.TabId? _tab;
  bool _syncScheduled = false;

  /// The ROOT container: the root overlay sits above every tab scope. Not a
  /// tab's container, which closes with its tab.
  ProviderContainer get _root =>
      ProviderScope.containerOf(_rootOverlay.context, listen: false);

  /// Completes when the drawer has closed.
  Future<void> get closed => _closed.future;

  void show() {
    _place(animateIn: true);
    if (_navigators != null && !_closed.isCompleted) {
      _subscription = _root.listen<AsyncValue<Workspace>>(
        workspaceProvider,
        (_, _) => _scheduleSync(),
      );
    }
  }

  void close() {
    _subscription?.close();
    _subscription = null;
    _entry?.remove();
    _entry = null;
    if (!_closed.isCompleted) _closed.complete();
  }

  void _place({required bool animateIn}) {
    final navigators = _navigators;
    final workspace = _root.read(workspaceProvider).value;
    final active = workspace?.activeTabId;
    if (navigators != null && workspace != null && active == null) {
      close(); // the no-tabs auto-dismiss
      return;
    }
    final navigator = navigators != null && active != null
        ? navigators.navigatorFor(active)
        : null;
    _entry?.remove();
    _tab = navigator == null ? null : active;
    final entry = OverlayEntry(
      builder: (_) =>
          _TabDiagnosticsDrawerHost(onClose: close, animateIn: animateIn),
    );
    _entry = entry;
    (navigator?.overlay ?? _rootOverlay).insert(entry);
  }

  void _scheduleSync() {
    if (_syncScheduled || _closed.isCompleted) return;
    _syncScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _syncScheduled = false;
        if (_closed.isCompleted) return;
        final active = _root.read(workspaceProvider).value?.activeTabId;
        if (active != _tab) _place(animateIn: false);
      })
      ..ensureVisualUpdate();
  }
}

/// Hosts [TabDiagnosticsDrawer] inside the overlay entry: right-aligned
/// slide-in transition, an Escape-to-close shortcut, and the
/// diagnostics-off auto-dismiss. It is built under the tab scope of the
/// navigator its entry is on, so the drawer reads that tab's report
/// without a scope of its own. Mirrors WaveCrux's
/// `_TabDiagnosticsDrawerHost`.
class _TabDiagnosticsDrawerHost extends ConsumerStatefulWidget {
  const _TabDiagnosticsDrawerHost({
    required this.onClose,
    required this.animateIn,
  });

  /// Removes the overlay entry and completes the open future.
  final VoidCallback onClose;

  /// False when the drawer moves to another tab: it is already open, so it
  /// neither slides in again nor takes focus.
  final bool animateIn;

  @override
  ConsumerState<_TabDiagnosticsDrawerHost> createState() =>
      _TabDiagnosticsDrawerHostState();
}

class _TabDiagnosticsDrawerHostState
    extends ConsumerState<_TabDiagnosticsDrawerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  final FocusScopeNode _scopeNode = FocusScopeNode(
    debugLabel: 'TabDiagnosticsDrawerHost',
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _offset =
        Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        );
    if (!widget.animateIn) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
    // Take keyboard focus explicitly: an `autofocus` request is ignored
    // when the underlying route's scope already holds focus (an overlay
    // entry is a sibling of the routes, not inside one), which would
    // leave the Escape binding below unreachable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scopeNode.requestFocus();
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
    if (!mounted) return;
    widget.onClose();
  }

  void _scheduleClose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_close());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Closes when diagnostics are turned off in Settings while the drawer
    // is open, rather than leaving a surface the gate now refuses. (Following
    // the active tab and the no-tabs auto-dismiss are the placement's.)
    if (!ref.watch(diagnosticsEnabledProvider)) {
      _scheduleClose();
      return const SizedBox.shrink();
    }

    final content = TabDiagnosticsDrawer(onClose: _close);

    // Escape-to-close binds at this host's level so the key is consumed
    // even when no inner widget has focus.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              unawaited(_close());
              return null;
            },
          ),
        },
        child: FocusScope(
          node: _scopeNode,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SlideTransition(
              position: _offset,
              // The full height of the overlay it is on: the tab's area,
              // or the window on the root overlay.
              child: SizedBox(height: double.infinity, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the structured plain-text report for clipboard paste.
/// Includes the standard tab report plus a "Yosys Diagnostics" tail
/// when the sidecar store has captured any.
String _buildReportText(
  TabDiagnosticsReport report,
  YosysDiagnosticsState yosys,
) {
  final buf = StringBuffer(report.toPlainText());
  if (yosys.diagnostics.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('## Yosys Diagnostics');
    for (final d in yosys.diagnostics) {
      final cite = d.filePath == null
          ? '<yosys>'
          : (d.line == null
                ? d.filePath
                : (d.column == null
                      ? '${d.filePath}:${d.line}'
                      : '${d.filePath}:${d.line}:${d.column}'));
      buf.writeln('  [${d.severity.name}] $cite — ${d.message}');
    }
  }
  return buf.toString();
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});
  final String title;
  final List<MapEntry<String, String>> rows;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    row.key,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.value,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
