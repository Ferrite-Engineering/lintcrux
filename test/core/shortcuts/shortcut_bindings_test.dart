// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings.dart';

void _useMacOS() {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

void _useLinux() {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

void main() {
  group('defaultBindings — macOS', () {
    test('Cmd is the modifier for File and App actions', () {
      _useMacOS();
      final b = defaultBindings();
      final open = b[LintcruxAction.openProject]! as SingleActivator;
      expect(open.meta, isTrue);
      expect(open.control, isFalse);
      expect(open.trigger, LogicalKeyboardKey.keyO);

      final quit = b[LintcruxAction.quit]! as SingleActivator;
      expect(quit.meta, isTrue);
      expect(quit.control, isFalse);
    });

    test('command palette is Cmd+Shift+P on macOS', () {
      _useMacOS();
      final palette =
          defaultBindings()[LintcruxAction.openCommandPalette]!
              as SingleActivator;
      expect(palette.meta, isTrue);
      expect(palette.shift, isTrue);
      expect(palette.trigger, LogicalKeyboardKey.keyP);
    });

    test('Cross-Probe panel is Cmd+Shift+X on macOS', () {
      _useMacOS();
      // Suite-wide default — matches WaveCrux / NetCrux / SimCrux.
      final crossProbe =
          defaultBindings()[LintcruxAction.openCrossProbePanel]!
              as SingleActivator;
      expect(crossProbe.meta, isTrue);
      expect(crossProbe.control, isFalse);
      expect(crossProbe.shift, isTrue);
      expect(crossProbe.trigger, LogicalKeyboardKey.keyX);
    });

    test('Open Sources is the shifted variant of Open Project', () {
      _useMacOS();
      final src =
          defaultBindings()[LintcruxAction.openSources]! as SingleActivator;
      expect(src.meta, isTrue);
      expect(src.shift, isTrue);
      expect(src.trigger, LogicalKeyboardKey.keyO);
    });
  });

  group('defaultBindings — Linux', () {
    test('Ctrl is the modifier on non-macOS', () {
      _useLinux();
      final b = defaultBindings();
      final open = b[LintcruxAction.openProject]! as SingleActivator;
      expect(open.control, isTrue);
      expect(open.meta, isFalse);
      expect(open.trigger, LogicalKeyboardKey.keyO);
    });

    test('command palette is Ctrl+Shift+P', () {
      _useLinux();
      final palette =
          defaultBindings()[LintcruxAction.openCommandPalette]!
              as SingleActivator;
      expect(palette.control, isTrue);
      expect(palette.shift, isTrue);
      expect(palette.trigger, LogicalKeyboardKey.keyP);
    });
  });

  group('defaultBindings — modifier-independent shortcuts', () {
    test('Run All Engines is F5 on every platform', () {
      _useMacOS();
      final run =
          defaultBindings()[LintcruxAction.runAllEngines]! as SingleActivator;
      expect(run.trigger, LogicalKeyboardKey.f5);
      expect(run.control, isFalse);
      expect(run.meta, isFalse);
      expect(run.shift, isFalse);
    });

    test('Cancel Run is Esc on every platform', () {
      _useMacOS();
      final cancel =
          defaultBindings()[LintcruxAction.cancelRun]! as SingleActivator;
      // Suite-wide cancel/stop convention; no modifier, distinct from Run All
      // Engines' F5.
      expect(cancel.trigger, LogicalKeyboardKey.escape);
      expect(cancel.shift, isFalse);
      expect(cancel.control, isFalse);
      expect(cancel.meta, isFalse);
    });

    test('About is bare F1 on every platform (suite-wide convention)', () {
      _useMacOS();
      final about =
          defaultBindings()[LintcruxAction.openAbout]! as SingleActivator;
      expect(about.trigger, LogicalKeyboardKey.f1);
      expect(about.meta, isFalse);
      expect(about.control, isFalse);
      expect(about.shift, isFalse);
    });

    test('Tab Diagnostics is Cmd/Ctrl+Shift+I (WaveCrux parity)', () {
      _useMacOS();
      final diag =
          defaultBindings()[LintcruxAction.openTabDiagnostics]!
              as SingleActivator;
      expect(diag.trigger, LogicalKeyboardKey.keyI);
      expect(diag.meta, isTrue);
      expect(diag.shift, isTrue);
    });

    test('App Diagnostics is Cmd/Ctrl+Shift+M (WaveCrux parity)', () {
      _useMacOS();
      final diag =
          defaultBindings()[LintcruxAction.openAppDiagnostics]!
              as SingleActivator;
      expect(diag.trigger, LogicalKeyboardKey.keyM);
      expect(diag.meta, isTrue);
      expect(diag.shift, isTrue);
    });
  });

  group('defaultBindings — coverage', () {
    // Actions documented as menu-only (no default keyboard accelerator).
    // The action-label / command-palette surface still picks them up so
    // they remain reachable by name; they just have no global shortcut.
    const menuOnly = <LintcruxAction>{
      // openAbout, openTabDiagnostics, and openAppDiagnostics are not in
      // this set: F1, Cmd/Ctrl+Shift+I and Cmd/Ctrl+Shift+M respectively
      // (WaveCrux parity).
      // Session actions — palette / menu only.
      LintcruxAction.saveSession,
      LintcruxAction.openSession,
      // Desktop SARIF report import (menu / palette / toolbar /
      // welcome only; no default keyboard accelerator).
      LintcruxAction.importSarif,
      LintcruxAction.exportSarif,
      LintcruxAction.exportJson,
      LintcruxAction.exportCsv,
      LintcruxAction.exportHtml,
      LintcruxAction.saveFilterPreset,
      LintcruxAction.manageFilterPresets,
      // Palette / menu only.
      LintcruxAction.importVivadoFilelist,
      // EDAM integration — palette / menu only.
      LintcruxAction.importEdam,
      // Palette / menu only (no default keyboard
      // accelerator). `closePane` and `focusOtherPane` would
      // ideally bind to `Cmd/Ctrl+K W` and `Cmd/Ctrl+K →` chords
      // respectively, but `SingleActivator` can't express a chord;
      // they're palette / menu only at the keyboard layer until a
      // chord-handler lands.
      LintcruxAction.newWorkspace,
      LintcruxAction.saveWorkspaceAs,
      LintcruxAction.openWorkspace,
      LintcruxAction.closePane,
      LintcruxAction.focusOtherPane,
      LintcruxAction.moveTabToOtherPane,
      // Palette / menu only (no default keyboard
      // accelerator).
      LintcruxAction.openWaiverReview,
      LintcruxAction.setBaseline,
      LintcruxAction.clearBaseline,
      LintcruxAction.openBaselineComparison,
      // Trend tracking actions (palette / menu only).
      LintcruxAction.showRuleTrendChart,
      LintcruxAction.showSeverityClassDriftChart,
      LintcruxAction.showProjectTrendChart,
      LintcruxAction.showCalendarHeatmap,
      LintcruxAction.configureTrendRetention,
      // Filter preset & violation bookmark actions
      // (palette / menu / context-menu only — no default keyboard
      // accelerators in the baseline binding set; the row-context
      // toggle for bookmarks is wired separately at the row widget).
      LintcruxAction.openBookmarksManager,
      LintcruxAction.toggleBookmarkForCurrentViolation,
      // Verible auto-fix integration actions
      // (palette / menu / toolbar only; no default keyboard
      // accelerators).
      LintcruxAction.runVeribleDryRun,
      LintcruxAction.applyVeribleFixes,
      LintcruxAction.configureVeribleBinary,
      // Lint run caching actions (palette / menu
      // / settings-section only; no default keyboard accelerators).
      LintcruxAction.clearLintCache,
      LintcruxAction.openLintCacheStats,
      LintcruxAction.forceLintRunWithoutCache,
      // Multi-project workspace actions. switchProject
      // (Cmd+P) and searchAcrossProjects (Cmd+Shift+F) ARE bound, in
      // `defaultBindings()`, matching SimCrux. The rest stay menu /
      // palette only: reopenRecentProject is a shortcut to the switcher,
      // which has its own chord, and the pin / close-all pair are
      // once-a-session commands.
      LintcruxAction.closeActiveProject,
      LintcruxAction.reopenRecentProject,
      LintcruxAction.pinActiveProject,
      LintcruxAction.closeAllProjects,
      // Update mechanism + beta issue reporter. Help-menu /
      // palette / About-box only; neither is frequent enough to earn a
      // chord.
      LintcruxAction.checkForUpdates,
      LintcruxAction.submitIssue,
      // Destructive and menu/palette-only — no accelerator, so it can
      // never fire from a mistyped chord. Matches SimCrux's
      // `closeAllTabs`, which is likewise unbound.
      LintcruxAction.closeAllTabs,
      // Documentation opens a URL in the browser — Help menu / palette only.
      // F1 is About's binding across the suite, and a docs link is not worth
      // a keyboard slot.
      LintcruxAction.openDocumentation,
    };

    test('every non-menu-only action has a default binding', () {
      final b = defaultBindings();
      for (final action in LintcruxAction.values) {
        if (menuOnly.contains(action)) continue;
        expect(b.containsKey(action), isTrue, reason: action.name);
      }
    });

    test('menu-only actions have no default binding', () {
      final b = defaultBindings();
      for (final action in menuOnly) {
        expect(
          b.containsKey(action),
          isFalse,
          reason: '${action.name} must remain menu-only',
        );
      }
    });

    test('every bound activator is a SingleActivator', () {
      for (final entry in defaultBindings().entries) {
        expect(entry.value, isA<SingleActivator>(), reason: entry.key.name);
      }
    });
  });
}
