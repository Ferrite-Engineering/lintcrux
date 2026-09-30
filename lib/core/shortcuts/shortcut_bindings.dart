// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';

/// The cross-suite [KeymapCodec] configured for LintCrux's action set and
/// schema id. Shared by the persistence store and keymap Export/Import.
final KeymapCodec<LintcruxAction> lintCruxKeymapCodec = KeymapCodec(
  actions: LintcruxAction.values,
  schema: 'lintcrux.keymap',
);

/// Returns platform-aware default key bindings for every [LintcruxAction].
///
/// Uses Cmd (meta) on macOS and Ctrl on Linux, Windows, and web — the
/// same modifier convention every modern IDE on those platforms uses.
///
/// The returned map covers every action with a default accelerator;
/// actions documented as menu/palette-only carry no entry (see the
/// `menuOnly` set in `test/core/shortcuts/shortcut_bindings_test.dart`).
Map<LintcruxAction, ShortcutActivator> defaultBindings() {
  final isMac = defaultTargetPlatform == TargetPlatform.macOS;
  return {
    // ── File ─────────────────────────────────────────────────────────
    LintcruxAction.openProject: SingleActivator(
      LogicalKeyboardKey.keyO,
      meta: isMac,
      control: !isMac,
    ),
    LintcruxAction.openSources: SingleActivator(
      LogicalKeyboardKey.keyO,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    LintcruxAction.resetWorkspace: SingleActivator(
      LogicalKeyboardKey.keyR,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // ── App ──────────────────────────────────────────────────────────
    LintcruxAction.quit: SingleActivator(
      LogicalKeyboardKey.keyQ,
      meta: isMac,
      control: !isMac,
    ),
    LintcruxAction.openSettings: SingleActivator(
      LogicalKeyboardKey.comma,
      meta: isMac,
      control: !isMac,
    ),
    // ── Run ──────────────────────────────────────────────────────────
    LintcruxAction.runAllEngines: const SingleActivator(LogicalKeyboardKey.f5),
    // Esc, matching the suite-wide cancel/stop convention (WaveCrux,
    // NetCrux, SimCrux all use Esc). LintCrux was the lone outlier on
    // Shift+F5 and moved to match. F5 stays for
    // Run All Engines above.
    LintcruxAction.cancelRun: const SingleActivator(LogicalKeyboardKey.escape),
    // ── View ─────────────────────────────────────────────────────────
    // Cmd/Ctrl+Shift+K (suite-consistent with WaveCrux). NOT Cmd/Ctrl+T —
    // that is newTab's chord below; binding both here meant toggleTheme's
    // accelerator never fired (newTab shadowed it) and, once conflicts became
    // visible, would have shown a spurious fresh-install warning.
    LintcruxAction.toggleTheme: SingleActivator(
      LogicalKeyboardKey.keyK,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // ── Search / palette ─────────────────────────────────────────────
    LintcruxAction.openCommandPalette: SingleActivator(
      LogicalKeyboardKey.keyP,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    LintcruxAction.focusSearch: SingleActivator(
      LogicalKeyboardKey.keyF,
      meta: isMac,
      control: !isMac,
    ),
    // ── Multi-project workspace ──────────────────────────────────────
    // The two chords SimCrux already ships for the same pair:
    // Cmd/Ctrl+P opens the project switcher (VSCode "Quick Open"
    // style) and Cmd/Ctrl+Shift+F opens cross-project search. Both
    // slots are free — openCommandPalette holds Cmd/Ctrl+Shift+P and
    // focusSearch holds plain Cmd/Ctrl+F above.
    //
    // reopenRecentProject stays unbound, as it is in SimCrux: the
    // switcher already lists recents with one-click reopen, so the
    // action is a menu shortcut to a surface that has its own chord.
    LintcruxAction.switchProject: SingleActivator(
      LogicalKeyboardKey.keyP,
      meta: isMac,
      control: !isMac,
    ),
    LintcruxAction.searchAcrossProjects: SingleActivator(
      LogicalKeyboardKey.keyF,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // ── Remote / cross-probe ─────────────────────────────────────────
    // Cmd/Ctrl+Shift+X — the suite-wide cross-probe panel accelerator
    // (matches WaveCrux / NetCrux / SimCrux). No
    // collision: no other default binding uses X.
    LintcruxAction.openCrossProbePanel: SingleActivator(
      LogicalKeyboardKey.keyX,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // F1 = About, the suite-wide convention (WaveCrux / NetCrux /
    // SimCrux all bind it).
    LintcruxAction.openAbout: const SingleActivator(LogicalKeyboardKey.f1),
    // ── Diagnostics (WaveCrux parity) ───
    // Cmd/Ctrl+Shift+I — "Inspect tab" — opens the Tab Diagnostics
    // drawer; Cmd/Ctrl+Shift+M — "Memory" — opens the App Diagnostics
    // dialog. Both match WaveCrux's defaults; neither slot was taken.
    LintcruxAction.openTabDiagnostics: SingleActivator(
      LogicalKeyboardKey.keyI,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    LintcruxAction.openAppDiagnostics: SingleActivator(
      LogicalKeyboardKey.keyM,
      meta: isMac,
      control: !isMac,
      shift: true,
    ),
    // ── Workspace / pane / tab ───────────────────────────
    LintcruxAction.newTab: SingleActivator(
      LogicalKeyboardKey.keyT,
      meta: isMac,
      control: !isMac,
    ),
    LintcruxAction.closeTab: SingleActivator(
      LogicalKeyboardKey.keyW,
      meta: isMac,
      control: !isMac,
    ),
    LintcruxAction.nextTab: const SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
    ),
    LintcruxAction.previousTab: const SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
      shift: true,
    ),
    LintcruxAction.splitPaneRight: SingleActivator(
      LogicalKeyboardKey.backslash,
      meta: isMac,
      control: !isMac,
    ),
    // closePane / focusOtherPane use a chord (Cmd/Ctrl+K …) that
    // SingleActivator can't express, so they stay unbound at
    // the keyboard layer — reachable via the command palette and the
    // platform menu bar only. A follow-on chord-handler can register
    // them properly.
    // newWorkspace / saveWorkspaceAs / openWorkspace /
    // exportTabAsSession / moveTabToOtherPane: no default keyboard
    // accelerator — reachable via the menu bar and command palette.
  };
}
