// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/persistence/diagnostics_enabled_settings_codec.dart';
import 'package:lintcrux/services/persistence/diagnostics_enabled_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

ProviderContainer _containerWith(SharedPreferences prefs) {
  final container = ProviderContainer(
    overrides: [
      diagnosticsEnabledSettingsServiceProvider.overrideWithValue(
        SettingsService<bool>(
          const DiagnosticsEnabledSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('DiagnosticsEnabledSettingsCodec', () {
    test('defaults to off when nothing is stored', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        await const DiagnosticsEnabledSettingsCodec().load(prefs),
        isFalse,
      );
    });

    test('round-trips both values', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = DiagnosticsEnabledSettingsCodec();
      await codec.save(prefs, true);
      expect(await codec.load(prefs), isTrue);
      await codec.save(prefs, false);
      expect(await codec.load(prefs), isFalse);
    });

    test("uses CoreSettingsCodec's key, so a whole-model codec adopts it", () {
      expect(
        DiagnosticsEnabledSettingsCodec.prefsKey,
        'settings.diagnosticsEnabled',
      );
    });

    test('a non-bool stored under the key falls back to off', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DiagnosticsEnabledSettingsCodec.prefsKey: 'yes',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        await const DiagnosticsEnabledSettingsCodec().load(prefs),
        isFalse,
      );
    });
  });

  group('AppSettingsNotifier ↔ diagnostics persistence', () {
    test('setDiagnosticsEnabled persists through the service', () async {
      final prefs = await SharedPreferences.getInstance();
      _containerWith(
        prefs,
      ).read(appSettingsProvider.notifier).setDiagnosticsEnabled(enabled: true);
      await _settle();
      expect(prefs.getBool(DiagnosticsEnabledSettingsCodec.prefsKey), isTrue);
    });

    test('a persisted "on" survives a relaunch', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DiagnosticsEnabledSettingsCodec.prefsKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = _containerWith(prefs);

      expect(container.read(appSettingsProvider).diagnosticsEnabled, isFalse);
      await _settle();
      await _settle();
      expect(container.read(appSettingsProvider).diagnosticsEnabled, isTrue);
    });

    test('a switch flipped before the restore lands is not undone', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        DiagnosticsEnabledSettingsCodec.prefsKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = _containerWith(prefs);
      container
          .read(appSettingsProvider.notifier)
          .setDiagnosticsEnabled(enabled: false);
      await _settle();
      await _settle();
      expect(container.read(appSettingsProvider).diagnosticsEnabled, isFalse);
    });
  });
}
