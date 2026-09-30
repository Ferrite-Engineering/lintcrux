// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/persistence/auto_update_check_settings_codec.dart';
import 'package:lintcrux/services/persistence/auto_update_check_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('AutoUpdateCheckSettingsCodec', () {
    test('defaults to enabled when nothing is stored', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(await const AutoUpdateCheckSettingsCodec().load(prefs), isTrue);
      expect(AutoUpdateCheckSettingsCodec.defaultValue, isTrue);
    });

    test('round-trips false', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = AutoUpdateCheckSettingsCodec();
      await codec.save(prefs, false);
      expect(await codec.load(prefs), isFalse);
    });

    test('round-trips true', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = AutoUpdateCheckSettingsCodec();
      await codec.save(prefs, false);
      await codec.save(prefs, true);
      expect(await codec.load(prefs), isTrue);
    });

    test('uses the shared settings.* key namespace', () async {
      // A later whole-model `SettingsCodec<AppSettings>` has to be able to
      // adopt this key verbatim, or every user's stored preference resets.
      expect(
        AutoUpdateCheckSettingsCodec.prefsKey,
        'settings.autoCheckForUpdates',
      );
      final prefs = await SharedPreferences.getInstance();
      await const AutoUpdateCheckSettingsCodec().save(prefs, false);
      expect(prefs.getBool('settings.autoCheckForUpdates'), isFalse);
    });

    test('a non-bool stored under the key falls back to the default', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AutoUpdateCheckSettingsCodec.prefsKey: 'yes',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await const AutoUpdateCheckSettingsCodec().load(prefs), isTrue);
    });
  });

  group('AppSettingsNotifier ↔ persistence', () {
    test('setAutoCheckForUpdates persists through the service', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          autoUpdateCheckSettingsServiceProvider.overrideWithValue(
            SettingsService<bool>(
              const AutoUpdateCheckSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(appSettingsProvider.notifier)
          .setAutoCheckForUpdates(enabled: false);
      await _settle();

      expect(prefs.getBool(AutoUpdateCheckSettingsCodec.prefsKey), isFalse);
    });

    test('a persisted "off" is restored into the settings model', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AutoUpdateCheckSettingsCodec.prefsKey: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          autoUpdateCheckSettingsServiceProvider.overrideWithValue(
            SettingsService<bool>(
              const AutoUpdateCheckSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Synchronous default first — no consumer ever sees a loading state.
      expect(container.read(appSettingsProvider).autoCheckForUpdates, isTrue);
      await _settle();
      await _settle();
      expect(container.read(appSettingsProvider).autoCheckForUpdates, isFalse);
    });

    test('a settings-store failure never breaks the toggle', () async {
      // No preferences backend: the model still changes, so the user's choice
      // holds for the session even though it will not survive a relaunch.
      final container = ProviderContainer(
        overrides: [
          autoUpdateCheckSettingsServiceProvider.overrideWithValue(
            const SettingsService<bool>(_ThrowingCodec()),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(appSettingsProvider.notifier)
          .setAutoCheckForUpdates(enabled: false);
      await _settle();
      expect(container.read(appSettingsProvider).autoCheckForUpdates, isFalse);
    });
  });
}

class _ThrowingCodec implements SettingsCodec<bool> {
  const _ThrowingCodec();

  @override
  Future<bool> load(SharedPreferences prefs) async =>
      throw StateError('no preferences backend');

  @override
  Future<void> save(SharedPreferences prefs, bool settings) async =>
      throw StateError('no preferences backend');
}
