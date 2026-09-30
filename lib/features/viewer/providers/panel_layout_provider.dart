// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/panel_layout_state.dart';

/// Manages panel visibility and size state for the viewer screen.
///
/// External callers (toolbar buttons, menu items, keyboard shortcut
/// handlers, and the command palette) use the toggle / set methods to
/// drive the panel layout. The viewer screen bidirectionally syncs the
/// underlying `panes.IdeController`:
///
/// - drag-to-resize fires the `setRuleBrowserWidth` / `setRunLogHeight`
///   side mutators via `IdeLayout.onPaneStateChanged` and
///   `IdeLayout.onSizeChanged`.
/// - programmatic toggles applied to `IdeController` via `ref.listen`.
///
/// Initial state comes from the persisted [AppSettings.panelLayout] via
/// the bootstrap override; widget tests that construct their own
/// `ProviderScope` get the model defaults if no override is supplied.
final NotifierProvider<PanelLayoutNotifier, PanelLayoutState>
panelLayoutProvider = NotifierProvider<PanelLayoutNotifier, PanelLayoutState>(
  PanelLayoutNotifier.new,
);

/// Notifier backing [panelLayoutProvider].
class PanelLayoutNotifier extends Notifier<PanelLayoutState> {
  @override
  PanelLayoutState build() => const PanelLayoutState();

  /// Toggles the visibility of the left rule-browser pane.
  void toggleRuleBrowser() =>
      state = state.copyWith(ruleBrowserVisible: !state.ruleBrowserVisible);

  /// Toggles the visibility of the right violation-details pane.
  void toggleViolationDetails() => state = state.copyWith(
    violationDetailsVisible: !state.violationDetailsVisible,
  );

  /// Toggles the visibility of the bottom run-log pane.
  void toggleRunLog() =>
      state = state.copyWith(runLogVisible: !state.runLogVisible);

  /// Sets the rule-browser visibility explicitly. Used by the
  /// `IdeController`→state sync to mirror user drag-to-collapse actions.
  void setRuleBrowserVisible({required bool visible}) =>
      state = state.copyWith(ruleBrowserVisible: visible);

  /// Sets the violation-details visibility explicitly.
  void setViolationDetailsVisible({required bool visible}) =>
      state = state.copyWith(violationDetailsVisible: visible);

  /// Sets the run-log visibility explicitly.
  void setRunLogVisible({required bool visible}) =>
      state = state.copyWith(runLogVisible: visible);

  /// Toggles the docked cross-probe side-panel. Driven by the ⌘/Ctrl+Shift+X
  /// cross-probe action and the toolbar toggle button.
  void toggleCrossProbe() =>
      state = state.copyWith(crossProbeVisible: !state.crossProbeVisible);

  /// Sets the cross-probe side-panel visibility explicitly. Used by the
  /// shared panel's close chevron (`onClose`) and its `onOpenPanel` command.
  void setCrossProbeVisible({required bool visible}) =>
      state = state.copyWith(crossProbeVisible: visible);

  /// Sets the rule-browser pane width (logical pixels). Driven by the
  /// `IdeController`'s drag-resize callback so user drag persists across
  /// launches via the settings codec.
  void setRuleBrowserWidth(double width) =>
      state = state.copyWith(ruleBrowserWidth: width);

  /// Sets the violation-details pane width (logical pixels).
  void setViolationDetailsWidth(double width) =>
      state = state.copyWith(violationDetailsWidth: width);

  /// Sets the run-log pane height (logical pixels).
  void setRunLogHeight(double height) =>
      state = state.copyWith(runLogHeight: height);

  /// Replaces the whole state — used by the bootstrap override to seed
  /// the notifier from the persisted [AppSettings.panelLayout]. Kept as
  /// a method rather than a setter so the standard notifier call
  /// pattern `ref.read(...).replace(next)` reads cleanly at every call
  /// site; the no-op identity guard short-circuits a redundant rebuild
  /// when the persisted state happens to match the in-memory state.
  void replace(PanelLayoutState next) {
    if (state == next) return;
    state = next;
  }
}
