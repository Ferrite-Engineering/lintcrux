// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/panel_layout_state.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:lintcrux/features/workspace/widgets/lintcrux_docks.dart';

/// The LintCrux four-pane IDE layout.
///
/// A thin adapter over the cross-suite [CruxIdeLayout] (from `crux_ide_layout`)
/// with LintCrux's pane assignment:
///
/// ```text
/// ┌────────────┬───────────────────────────────┬──────────────┐
/// │   Rule     │                               │  Violation   │
/// │  Browser   │   Violation List / Source     │   Details    │
/// │  (left)    │   (center)                    │   (right)    │
/// │            │                               │              │
/// │            ├───────────────────────────────┤              │
/// │            │   Run Log (bottom)            │              │
/// └────────────┴───────────────────────────────┴──────────────┘
/// ```
///
/// The widget is layout-only: each pane is a builder slot the caller fills
/// with the actual panel content (rule browser tree, violation table,
/// inspector pane, run-log scroller).
///
/// Visibility and pixel sizes are projected from the shared
/// [panelLayoutProvider] onto the shared widget via [_LintcruxIdePanelLayout] +
/// [_LintcruxIdePanelLayoutSink]; `CruxIdeLayout` owns the `IdeController`, the
/// resizer theme, and the bidirectional visibility/size sync that persists
/// drag-to-resize / drag-to-collapse back through the notifier (and so through
/// the settings codec).
class LintcruxIdeLayout extends ConsumerWidget {
  /// Creates a [LintcruxIdeLayout]. All four pane builders are required
  /// so the layout is never empty.
  const LintcruxIdeLayout({
    required this.ruleBrowserBuilder,
    required this.violationsBuilder,
    required this.violationDetailsBuilder,
    required this.runLogBuilder,
    super.key,
  });

  /// Builder for the left rule-browser pane.
  final IdePaneBuilder ruleBrowserBuilder;

  /// Builder for the center violation-list / source-preview pane.
  final IdePaneBuilder violationsBuilder;

  /// Builder for the right violation-details pane.
  final IdePaneBuilder violationDetailsBuilder;

  /// Builder for the bottom run-log pane.
  final IdePaneBuilder runLogBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);
    // Collapsed regions leave a slim restore bar along their edge
    // (JetBrains tool-window model — the suite panel-reopen canon).
    return LintcruxDockRestoreBars(
      child: CruxIdeLayout(
        layout: _LintcruxIdePanelLayout(state),
        sink: _LintcruxIdePanelLayoutSink(notifier),
        leftBuilder: ruleBrowserBuilder,
        centerBuilder: violationsBuilder,
        rightBuilder: violationDetailsBuilder,
        bottomBuilder: runLogBuilder,
      ),
    );
  }
}

/// Read-side adapter: LintCrux's [PanelLayoutState] → [IdePanelLayout]
/// (rule browser→left, violation details→right, run log→bottom; pixel sizes).
class _LintcruxIdePanelLayout implements IdePanelLayout {
  const _LintcruxIdePanelLayout(this._state);

  final PanelLayoutState _state;

  @override
  bool get leftVisible => _state.ruleBrowserVisible;

  @override
  PaneSize? get leftSize => _state.ruleBrowserWidth != null
      ? PaneSize.pixel(_state.ruleBrowserWidth!)
      : null;

  @override
  bool get rightVisible => _state.violationDetailsVisible;

  @override
  PaneSize? get rightSize => _state.violationDetailsWidth != null
      ? PaneSize.pixel(_state.violationDetailsWidth!)
      : null;

  @override
  bool get bottomVisible => _state.runLogVisible;

  @override
  PaneSize? get bottomSize =>
      _state.runLogHeight != null ? PaneSize.pixel(_state.runLogHeight!) : null;
}

/// Write-side adapter: drag-to-collapse / drag-to-resize → the LintCrux
/// [PanelLayoutNotifier], which persists via the settings codec.
///
/// `CruxIdeLayout` feeds visibility/size deltas back synchronously from inside
/// the `IdeController`'s change notification — which can fire while the widget
/// tree is building (e.g. when a View-menu toggle drives
/// `didUpdateWidget` → `controller.hide()` → the controller's
/// `onPaneStateChanged`). The LintCrux notifier's setters mutate provider
/// state synchronously, so each call is deferred to a microtask to land the
/// mutation after the current build, the same way NetCrux's `Future`-returning
/// setters defer past their first `await`. (Persistence is unchanged — the
/// settings codec still captures the value.)
class _LintcruxIdePanelLayoutSink implements IdePanelLayoutSink {
  const _LintcruxIdePanelLayoutSink(this._notifier);

  final PanelLayoutNotifier _notifier;

  @override
  void setLeftVisible({required bool visible}) => scheduleMicrotask(
    () => _notifier.setRuleBrowserVisible(visible: visible),
  );

  @override
  void setRightVisible({required bool visible}) => scheduleMicrotask(
    () => _notifier.setViolationDetailsVisible(visible: visible),
  );

  @override
  void setBottomVisible({required bool visible}) => scheduleMicrotask(
    () => _notifier.setRunLogVisible(visible: visible),
  );

  @override
  void setLeftSize(double pixels) =>
      scheduleMicrotask(() => _notifier.setRuleBrowserWidth(pixels));

  @override
  void setRightSize(double pixels) =>
      scheduleMicrotask(() => _notifier.setViolationDetailsWidth(pixels));

  @override
  void setBottomSize(double pixels) =>
      scheduleMicrotask(() => _notifier.setRunLogHeight(pixels));
}
