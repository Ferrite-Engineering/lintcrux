// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';

void main() {
  group('AppSettingsNotifier', () {
    test('initial state is the const AppSettings default', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(appSettingsProvider), const AppSettings());
    });

    test('setThemeMode updates only the theme field', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(appSettingsProvider.notifier).setThemeMode(AppThemeMode.light);
      expect(c.read(appSettingsProvider).themeMode, AppThemeMode.light);
      expect(
        c.read(appSettingsProvider).autoReloadMode,
        const AppSettings().autoReloadMode,
      );
    });

    test('setThemeMode is a no-op when the value matches', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final before = c.read(appSettingsProvider);
      c.read(appSettingsProvider.notifier).setThemeMode(before.themeMode);
      expect(identical(c.read(appSettingsProvider), before), isTrue);
    });

    test('setAutoReloadMode flips between auto / prompt / off', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(appSettingsProvider.notifier)
          .setAutoReloadMode(AutoReloadMode.prompt);
      expect(c.read(appSettingsProvider).autoReloadMode, AutoReloadMode.prompt);
      c
          .read(appSettingsProvider.notifier)
          .setAutoReloadMode(AutoReloadMode.off);
      expect(c.read(appSettingsProvider).autoReloadMode, AutoReloadMode.off);
    });

    test('setDiagnosticsEnabled flips the diagnostics flag', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(appSettingsProvider.notifier).setDiagnosticsEnabled(enabled: true);
      expect(c.read(appSettingsProvider).diagnosticsEnabled, isTrue);
      c
          .read(appSettingsProvider.notifier)
          .setDiagnosticsEnabled(enabled: false);
      expect(c.read(appSettingsProvider).diagnosticsEnabled, isFalse);
    });

    test('replace swaps in a different AppSettings snapshot', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const next = AppSettings(recentProjects: ['/tmp/a.lintcrux']);
      c.read(appSettingsProvider.notifier).replace(next);
      expect(c.read(appSettingsProvider), next);
    });

    test('replace is a no-op when the snapshot is identical', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final before = c.read(appSettingsProvider);
      c.read(appSettingsProvider.notifier).replace(const AppSettings());
      expect(identical(c.read(appSettingsProvider), before), isTrue);
    });

    test('setEngineBinaryOverride stores a per-engine override', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const override = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/opt/verilator/bin/verilator',
      );
      c
          .read(appSettingsProvider.notifier)
          .setEngineBinaryOverride('verilator', override);
      expect(
        c.read(appSettingsProvider).engineBinaryOverrideFor('verilator'),
        override,
      );
    });

    test('setEngineBinaryOverride with autoDetect removes the entry', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      const override = EngineBinaryOverride(
        source: EngineBinarySource.custom,
        path: '/p',
      );
      c.read(appSettingsProvider.notifier)
        ..setEngineBinaryOverride('verilator', override)
        ..setEngineBinaryOverride(
          'verilator',
          EngineBinaryOverride.autoDetect,
        );
      expect(
        c.read(appSettingsProvider).engineBinaryOverrides,
        isEmpty,
      );
    });

    test(
      'engineBinaryOverrideFor defaults to autoDetect for unset engines',
      () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        expect(
          c.read(appSettingsProvider).engineBinaryOverrideFor('verilator'),
          EngineBinaryOverride.autoDetect,
        );
      },
    );

    test('clearEngineBinaryOverrides empties the override map', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(appSettingsProvider.notifier)
        ..setEngineBinaryOverride(
          'verilator',
          const EngineBinaryOverride(
            source: EngineBinarySource.bundled,
          ),
        )
        ..clearEngineBinaryOverrides();
      expect(c.read(appSettingsProvider).engineBinaryOverrides, isEmpty);
    });

    test('setCxpServerEnabled flips the flag', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(appSettingsProvider).cxpServerEnabled, isTrue);
      c.read(appSettingsProvider.notifier).setCxpServerEnabled(enabled: false);
      expect(c.read(appSettingsProvider).cxpServerEnabled, isFalse);
    });

    test('setCxpServerPort accepts valid ports', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(appSettingsProvider.notifier).setCxpServerPort(60000);
      expect(c.read(appSettingsProvider).cxpServerPort, 60000);
    });

    test('setCxpServerPort clamps out-of-range values back to the default', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(appSettingsProvider.notifier);
      for (final bad in <int>[0, -1, 70000, 65536]) {
        notifier.setCxpServerPort(bad);
        expect(
          c.read(appSettingsProvider).cxpServerPort,
          AppSettings.defaultCxpServerPort,
          reason: 'port: $bad',
        );
      }
    });
  });
}
