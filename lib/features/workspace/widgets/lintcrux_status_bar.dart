// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/status_bar_trailing_widgets_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// Window-bottom **status bar** spanning the whole LintCrux workspace.
///
/// LintCrux shipped without a consistent bottom bar; this adds one on the
/// shared cross-suite [CruxStatusBar] chrome so LintCrux's bottom-of-window
/// chrome matches WaveCrux (the canonical) in height, typography, surface, and
/// border. It surfaces the active tab's project name and a live violation
/// summary, plus a small spinner while engines are running.
///
/// The project / violations / run providers are **per-tab**, but this bar
/// mounts in `ViewerScaffold`'s ROOT scope. So it follows the active tab's
/// `ProviderContainer` via [activeTabContainerOf] — watching
/// [workspaceProvider] so it re-resolves on every tab switch — and reads it
/// through [LintcruxTabStatusBar], which subscribes to that container rather
/// than mounting a second scope for it. With no tab open it renders an idle
/// bar, keeping a consistent bottom strip without reading the empty
/// root-scope providers.
class LintcruxStatusBar extends ConsumerWidget {
  /// Creates the workspace status bar.
  const LintcruxStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-resolve the active tab's container whenever the active tab changes.
    ref.watch(workspaceProvider);
    // The Pro extension slot is a root-scoped Provider<List<Widget>> the host
    // overrides with a const list, so reading it here touches no per-tab state.
    final trailing = ref.watch(statusBarTrailingWidgetsProvider);
    final container = activeTabContainerOf(context);
    if (container == null) {
      // An explicitly idle bar, not a blank one. Every product keeps a bottom
      // bar in the no-tab state and says what that state is — the window's
      // bottom edge should not change shape between products showing the same
      // empty canvas. It carries the Pro extension slot too, so the edition
      // badge stays put on the empty canvas as it does in WaveCrux.
      return _IdleStatusBar(trailing: trailing);
    }
    return LintcruxTabStatusBar(container: container, trailing: trailing);
  }
}

/// The status bar for one tab, read from that tab's [container] by
/// subscription.
///
/// **Why not an `UncontrolledProviderScope`.** The tab's own content already
/// mounts one for this container. Riverpod assumes a container has exactly one
/// scope: each scope it is given flushes the container's pending provider
/// rebuilds from inside its own `build`, and the flush notifies every listener
/// of the container. With a second scope here, whichever of the two built
/// first notified widgets in the *other* subtree mid-build, and Flutter's
/// "setState() or markNeedsBuild() called during build" assertion fired —
/// intermittently, by which scope won. So this widget never touches the
/// container while the tree is building: it subscribes after the frame, keeps
/// the latest values its listeners hand it, and rebuilds itself after the
/// frame in which they changed.
///
/// Public so widget tests can bind it to a container of their own.
class LintcruxTabStatusBar extends StatefulWidget {
  /// Creates the status bar for the tab whose container is [container].
  const LintcruxTabStatusBar({
    required this.container,
    this.trailing = const <Widget>[],
    super.key,
  });

  /// The tab's `ProviderContainer`.
  final ProviderContainer container;

  /// The Pro extension slot, rendered after the busy indicator.
  final List<Widget> trailing;

  @override
  State<LintcruxTabStatusBar> createState() => _LintcruxTabStatusBarState();
}

class _LintcruxTabStatusBarState extends State<LintcruxTabStatusBar> {
  /// The container the subscriptions below are open on; `null` until the
  /// first subscribe lands, one frame after mounting or a tab switch.
  ProviderContainer? _bound;
  List<ProviderSubscription<Object?>> _subscriptions =
      const <ProviderSubscription<Object?>>[];
  bool _bindQueued = false;
  bool _rebuildQueued = false;

  LintProject? _project;
  List<Violation> _visible = const <Violation>[];
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _queueBind();
  }

  @override
  void didUpdateWidget(LintcruxTabStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.container, widget.container)) _queueBind();
  }

  @override
  void dispose() {
    _closeSubscriptions();
    super.dispose();
  }

  /// Subscribes to [LintcruxTabStatusBar.container] once the current frame
  /// has finished building. Subscribing flushes any provider that is due a
  /// rebuild, and that flush notifies the tab content's widgets: done during
  /// a build, it is the very assertion this widget exists to avoid.
  void _queueBind() {
    if (_bindQueued) return;
    _bindQueued = true;
    scheduleMicrotask(() {
      _bindQueued = false;
      if (!mounted) return;
      final container = widget.container;
      if (identical(container, _bound)) return;
      _closeSubscriptions();
      _subscriptions = <ProviderSubscription<Object?>>[
        container.listen<LintProject?>(currentProjectProvider, (_, next) {
          _project = next;
          _queueRebuild();
        }, fireImmediately: true),
        container.listen<List<Violation>>(visibleViolationsProvider, (_, next) {
          _visible = next;
          _queueRebuild();
        }, fireImmediately: true),
        container.listen<bool>(
          lintRunProvider.select((s) => s.isRunning),
          (_, next) {
            _running = next;
            _queueRebuild();
          },
          fireImmediately: true,
        ),
      ];
      _bound = container;
    });
  }

  /// Rebuilds after the current frame. A listener here usually runs inside
  /// the tab scope's flush, which is inside that scope's `build`; marking
  /// this widget — not a descendant of that scope — dirty there is what
  /// Flutter asserts against.
  void _queueRebuild() {
    if (_rebuildQueued) return;
    _rebuildQueued = true;
    scheduleMicrotask(() {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
  }

  void _closeSubscriptions() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions = const <ProviderSubscription<Object?>>[];
    _bound = null;
  }

  @override
  Widget build(BuildContext context) {
    // Until the first subscription lands the bar shows the idle state rather
    // than a zero tally it has not read.
    if (_bound == null) return _IdleStatusBar(trailing: widget.trailing);
    return _StatusBarContent(
      project: _project,
      visible: _visible,
      running: _running,
      trailing: widget.trailing,
    );
  }
}

/// Renders the status segments from whatever scope it is mounted in.
///
/// For a window whose violations live in its own ambient scope — the
/// imported-report viewer, which is its own route — and for widget tests
/// that pump it against overridden providers. The workspace bar reads the
/// active tab through [LintcruxTabStatusBar] instead.
class LintcruxStatusBarBody extends ConsumerWidget {
  /// Creates the status-bar body.
  const LintcruxStatusBarBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StatusBarContent(
      project: ref.watch(currentProjectProvider),
      visible: ref.watch(visibleViolationsProvider),
      running: ref.watch(lintRunProvider.select((s) => s.isRunning)),
      trailing: ref.watch(statusBarTrailingWidgetsProvider),
    );
  }
}

/// The bar with no tab behind it: says so, and keeps the extension slot.
class _IdleStatusBar extends StatelessWidget {
  const _IdleStatusBar({required this.trailing});

  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxStatusBar(
      semanticsLabel: l10n.accessibilityStatusBarRegion,
      segments: [CruxStatusSegment(l10n.statusBarNoProject)],
      trailing: trailing,
    );
  }
}

/// The bar for one project: its name, the severity tally over the visible
/// violations, and a spinner while a run is in flight.
class _StatusBarContent extends StatelessWidget {
  const _StatusBarContent({
    required this.project,
    required this.visible,
    required this.running,
    required this.trailing,
  });

  final LintProject? project;
  final List<Violation> visible;
  final bool running;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);

    // The one severity tally in the app, over the filtered/visible set. The
    // violation table used to render the identical string in its own footer
    // strip; that duplicate is gone.
    var errors = 0;
    var warnings = 0;
    var notes = 0;
    var waived = 0;
    for (final v in visible) {
      if (v.isSuppressed) waived++;
      switch (v.severity) {
        case Severity.fatal:
        case Severity.error:
          errors++;
        case Severity.warning:
          warnings++;
        case Severity.note:
          notes++;
        case Severity.none:
          break;
      }
    }

    final name = project?.name;
    return CruxStatusBar(
      // The region name a screen reader announces on entering the bar, the
      // same "Status bar" every product in the suite uses.
      semanticsLabel: l10n.accessibilityStatusBarRegion,
      segments: [
        if (name != null) CruxStatusSegment(name),
        CruxStatusSegment(
          l10n.violationStatusSummary(
            visible.length,
            errors,
            warnings,
            notes,
            waived,
          ),
        ),
      ],
      // Suite grammar: progress first, then the Pro extension slot.
      trailing: [
        if (running)
          CruxStatusBusyIndicator(semanticsLabel: l10n.statusBarBusyLintRun),
        ...trailing,
      ],
    );
  }
}
