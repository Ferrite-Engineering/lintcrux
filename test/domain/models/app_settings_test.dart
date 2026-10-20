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
      expect(off.panelLayout, base.panelLayout);
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

    test('copyWith — flat-core forwarder updates the inner CoreSettings', () {
      const base = AppSettings();
      final next = base.copyWith(themeMode: AppThemeMode.light);
      expect(next.themeMode, AppThemeMode.light);
      // panelLayout is unchanged.
      expect(next.panelLayout, base.panelLayout);
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
      const a = AppSettings(autoCheckForUpdates: false);
      const b = AppSettings(autoCheckForUpdates: false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith — panelLayout field round-trips', () {
      const base = AppSettings();
      const tweaked = PanelLayoutState(
        ruleBrowserVisible: false,
        ruleBrowserWidth: 280,
      );
      final next = base.copyWith(panelLayout: tweaked);
      expect(next.panelLayout, tweaked);
      expect(next.core, base.core);
    });

    test('== rejects differing panelLayout', () {
      const a = AppSettings();
      const b = AppSettings(
        panelLayout: PanelLayoutState(ruleBrowserVisible: false),
      );
      expect(a, isNot(b));
    });

    // The four CXP settings are not here: the shared runtime owns and saves
    // them (`cruxCxpSettingsProvider`), and `AppSettings` carrying a second
    // copy is how an unrelated settings save once overwrote them.
    test('toString names none of the CXP settings', () {
      final text = const AppSettings().toString();
      expect(text, isNot(contains('cxpServer')));
      expect(text, isNot(contains('CrossProbe')));
    });
  });
}
