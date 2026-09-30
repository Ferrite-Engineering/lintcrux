// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Visibility and size state for the four LintCrux viewer panels.
///
/// The viewer is a four-pane IDE-style layout (rule browser left, violation
/// list/source view center, violation details right, run log bottom). This
/// model is the source of truth for which panes are visible and at what
/// size; the `IdeLayout` widget and the `IdeController` it owns are driven
/// from this state via the bidirectional sync in `ProjectTabContent`'s hosting of `LintcruxIdeLayout`.
///
/// Sizes are stored as logical pixels because `panes.PaneSize` is not a
/// pure-Dart type and would pull a Flutter import into the domain layer.
/// `null` for any size field means "use the panes default", which is what
/// `IdeController` configures via its constructor defaults.
///
/// Mirrors the WaveCrux `PanelLayoutState` design (same field shape, same
/// `copyWith` / `==` / `hashCode` contract) so the persistence codec in
/// `crux_settings` can be lifted across products later. The fields stay
/// LintCrux-specific (rule browser, violation details, run log).
@immutable
class PanelLayoutState {
  /// Creates a [PanelLayoutState]. All defaults match the open-on-launch
  /// experience: three side/bottom panes visible at their default widths.
  const PanelLayoutState({
    this.ruleBrowserVisible = true,
    this.violationDetailsVisible = true,
    this.runLogVisible = true,
    this.crossProbeVisible = false,
    this.ruleBrowserWidth,
    this.violationDetailsWidth,
    this.runLogHeight,
  });

  /// Whether the left rule-browser pane is visible.
  final bool ruleBrowserVisible;

  /// Whether the right violation-details pane is visible.
  final bool violationDetailsVisible;

  /// Whether the bottom run-log pane is visible.
  final bool runLogVisible;

  /// Whether the docked cross-probe side-panel is visible. Transient UI state — deliberately *not* persisted:
  /// it defaults off on every launch and is toggled by the ⌘/Ctrl+Shift+X
  /// cross-probe action + the toolbar toggle button.
  final bool crossProbeVisible;

  /// Logical-pixel width of the rule-browser pane. `null` ⇒ panes default.
  final double? ruleBrowserWidth;

  /// Logical-pixel width of the violation-details pane. `null` ⇒ default.
  final double? violationDetailsWidth;

  /// Logical-pixel height of the run-log pane. `null` ⇒ panes default.
  final double? runLogHeight;

  /// Returns a copy with overridden fields. To explicitly clear a `?`-typed
  /// size field, pass the corresponding `clear*` flag — the standard
  /// `field: null` convention means "don't touch" in `copyWith`.
  PanelLayoutState copyWith({
    bool? ruleBrowserVisible,
    bool? violationDetailsVisible,
    bool? runLogVisible,
    bool? crossProbeVisible,
    double? ruleBrowserWidth,
    double? violationDetailsWidth,
    double? runLogHeight,
    bool clearRuleBrowserWidth = false,
    bool clearViolationDetailsWidth = false,
    bool clearRunLogHeight = false,
  }) {
    return PanelLayoutState(
      ruleBrowserVisible: ruleBrowserVisible ?? this.ruleBrowserVisible,
      violationDetailsVisible:
          violationDetailsVisible ?? this.violationDetailsVisible,
      runLogVisible: runLogVisible ?? this.runLogVisible,
      crossProbeVisible: crossProbeVisible ?? this.crossProbeVisible,
      ruleBrowserWidth: clearRuleBrowserWidth
          ? null
          : (ruleBrowserWidth ?? this.ruleBrowserWidth),
      violationDetailsWidth: clearViolationDetailsWidth
          ? null
          : (violationDetailsWidth ?? this.violationDetailsWidth),
      runLogHeight: clearRunLogHeight
          ? null
          : (runLogHeight ?? this.runLogHeight),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PanelLayoutState &&
        other.ruleBrowserVisible == ruleBrowserVisible &&
        other.violationDetailsVisible == violationDetailsVisible &&
        other.runLogVisible == runLogVisible &&
        other.crossProbeVisible == crossProbeVisible &&
        other.ruleBrowserWidth == ruleBrowserWidth &&
        other.violationDetailsWidth == violationDetailsWidth &&
        other.runLogHeight == runLogHeight;
  }

  @override
  int get hashCode => Object.hash(
    ruleBrowserVisible,
    violationDetailsVisible,
    runLogVisible,
    crossProbeVisible,
    ruleBrowserWidth,
    violationDetailsWidth,
    runLogHeight,
  );

  @override
  String toString() =>
      'PanelLayoutState('
      'ruleBrowserVisible: $ruleBrowserVisible, '
      'violationDetailsVisible: $violationDetailsVisible, '
      'runLogVisible: $runLogVisible, '
      'crossProbeVisible: $crossProbeVisible, '
      'ruleBrowserWidth: $ruleBrowserWidth, '
      'violationDetailsWidth: $violationDetailsWidth, '
      'runLogHeight: $runLogHeight)';
}
