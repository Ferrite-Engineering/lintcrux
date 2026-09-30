// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/domain/models/panel_layout_state.dart';

void main() {
  group('AppSettings', () {
    test(
      'default constructor returns a CoreSettings.defaults() composition',
      () {
        const settings = AppSettings();
        expect(settings.core, const CoreSettings.defaults());
        expect(settings.recentProjects, isEmpty);
        expect(settings.panelLayout, const PanelLayoutState());
      },
    );

    test('forwarders delegate to CoreSettings', () {
      const settings = AppSettings();
      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.locale, 'en');
      expect(settings.diagnosticsEnabled, isFalse);
      expect(settings.restoreTabsOnLaunch, isTrue);
    });

    test('autoCheckForUpdates defaults to on', () {
      // The suite-wide default: a beta user finds out a newer build exists
      // without having to go looking for it.
      expect(const AppSettings().autoCheckForUpdates, isTrue);
    });

    test('copyWith — autoCheckForUpdates round-trips', () {
      const base = AppSettings();
      final off = base.copyWith(autoCheckForUpdates: false);
      expect(off.autoCheckForUpdates, isFalse);
      expect(
        off.copyWith(autoCheckForUpdates: true).autoCheckForUpdates,
        isTrue,
      );
      // Nothing else moved.
      expect(off.core, base.core);
      expect(off.recentProjects, base.recentProjects);
    });

    test('autoCheckForUpdates participates in equality and hashCode', () {
      const base = AppSettings();
      final off = base.copyWith(autoCheckForUpdates: false);
      expect(off, isNot(base));
      expect(off.hashCode, isNot(base.hashCode));
      expect(off, base.copyWith(autoCheckForUpdates: false));
    });

    test('toString names autoCheckForUpdates', () {
      expect(const AppSettings().toString(), contains('autoCheckForUpdates'));
    });

    test('copyWith — LintCrux-specific recentProjects override', () {
      const base = AppSettings();
      final next = base.copyWith(recentProjects: const ['/tmp/foo.lintcrux']);
      expect(next.recentProjects, ['/tmp/foo.lintcrux']);
      // Core is unchanged.
      expect(next.core, base.core);
    });

    test('copyWith — flat-core forwarder updates the inner CoreSettings', () {
      const base = AppSettings();
      final next = base.copyWith(themeMode: AppThemeMode.light);
      expect(next.themeMode, AppThemeMode.light);
      // recentProjects is unchanged.
      expect(next.recentProjects, base.recentProjects);
    });

    test('copyWith — explicit core override wins over flat forwarders', () {
      const base = AppSettings();
      // When `core` is provided, the flat forwarders are ignored.
      const explicitCore = CoreSettings.defaults();
      final next = base.copyWith(
        core: explicitCore,
        themeMode: AppThemeMode.light, // ignored — core wins
      );
      expect(next.core, explicitCore);
      expect(next.themeMode, AppThemeMode.dark);
    });

    test('== and hashCode treat equal field values as equal', () {
      const a = AppSettings(recentProjects: ['/x', '/y']);
      const b = AppSettings(recentProjects: ['/x', '/y']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('== rejects differing recentProjects order', () {
      const a = AppSettings(recentProjects: ['/x', '/y']);
      const b = AppSettings(recentProjects: ['/y', '/x']);
      expect(a, isNot(b));
    });

    test('maxRecentProjects is the documented cap', () {
      expect(AppSettings.maxRecentProjects, 10);
    });

    test('copyWith — panelLayout field round-trips', () {
      const base = AppSettings();
      const tweaked = PanelLayoutState(
        ruleBrowserVisible: false,
        ruleBrowserWidth: 280,
      );
      final next = base.copyWith(panelLayout: tweaked);
      expect(next.panelLayout, tweaked);
      expect(next.recentProjects, base.recentProjects);
      expect(next.core, base.core);
    });

    test('== rejects differing panelLayout', () {
      const a = AppSettings();
      const b = AppSettings(
        panelLayout: PanelLayoutState(ruleBrowserVisible: false),
      );
      expect(a, isNot(b));
    });

    test('defaults cxpServerEnabled=true and cxpServerPort=54324', () {
      const settings = AppSettings();
      expect(settings.cxpServerEnabled, isTrue);
      expect(settings.cxpServerPort, AppSettings.defaultCxpServerPort);
      expect(AppSettings.defaultCxpServerPort, 54324);
    });

    test('copyWith — cxpServerEnabled / cxpServerPort round-trip', () {
      const base = AppSettings();
      final next = base.copyWith(
        cxpServerEnabled: false,
        cxpServerPort: 60000,
      );
      expect(next.cxpServerEnabled, isFalse);
      expect(next.cxpServerPort, 60000);
      // Other fields preserved.
      expect(next.recentProjects, base.recentProjects);
      expect(next.core, base.core);
    });

    test('== rejects differing cxpServerEnabled / cxpServerPort', () {
      const a = AppSettings();
      const b = AppSettings(cxpServerEnabled: false);
      const c = AppSettings(cxpServerPort: 60000);
      expect(a, isNot(b));
      expect(a, isNot(c));
    });
  });
}
