// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_codec.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('RestoreTabsSettingsCodec', () {
    test('defaults to restoring when nothing is stored', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(await const RestoreTabsSettingsCodec().load(prefs), isTrue);
      expect(RestoreTabsSettingsCodec.defaultValue, isTrue);
    });

    test('round-trips false', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = RestoreTabsSettingsCodec();
      await codec.save(prefs, false);
      expect(await codec.load(prefs), isFalse);
    });

    test('round-trips true', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = RestoreTabsSettingsCodec();
      await codec.save(prefs, false);
      await codec.save(prefs, true);
      expect(await codec.load(prefs), isTrue);
    });

    test('reads the key CoreSettingsCodec owns', () async {
      // Load-bearing beyond forward-compatibility: the beta reporter set this
      // preference by hand (`defaults write … flutter.settings.
      // restoreTabsOnLaunch -bool false`, SharedPreferences namespacing under
      // `flutter.`). Reading a different key would leave that user's setting
      // silently ignored, which is the bug.
      expect(
        RestoreTabsSettingsCodec.prefsKey,
        'settings.restoreTabsOnLaunch',
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings.restoreTabsOnLaunch': false,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await const RestoreTabsSettingsCodec().load(prefs), isFalse);
    });

    test('a non-bool stored under the key falls back to the default', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RestoreTabsSettingsCodec.prefsKey: 'no',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await const RestoreTabsSettingsCodec().load(prefs), isTrue);
    });
  });

  group('AppSettingsNotifier ↔ restore-tabs persistence', () {
    ProviderContainer containerOver(SharedPreferences prefs) {
      final container = ProviderContainer(
        overrides: [
          restoreTabsSettingsServiceProvider.overrideWithValue(
            SettingsService<bool>(
              const RestoreTabsSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the model default is "restore"', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);
      expect(container.read(appSettingsProvider).restoreTabsOnLaunch, isTrue);
    });

    test('setRestoreTabsOnLaunch persists through the service', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);

      // Let the notifier's own build-time restore land first, so the write
      // below is not racing a read that is still in flight.
      await _settle();
      container
          .read(appSettingsProvider.notifier)
          .setRestoreTabsOnLaunch(enabled: false);
      await _settle();
      await _settle();

      expect(container.read(appSettingsProvider).restoreTabsOnLaunch, isFalse);
      expect(prefs.getBool(RestoreTabsSettingsCodec.prefsKey), isFalse);
    });

    test('a persisted "off" is restored into the settings model', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RestoreTabsSettingsCodec.prefsKey: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);

      // Synchronous default first — no consumer ever sees a loading state.
      expect(container.read(appSettingsProvider).restoreTabsOnLaunch, isTrue);
      await _settle();
      await _settle();
      expect(container.read(appSettingsProvider).restoreTabsOnLaunch, isFalse);
    });

    test('a toggle made before the restore lands is not overwritten', () async {
      // The build-time restore is asynchronous. Flipping the switch in the
      // first frames must not be silently undone a moment later by the value
      // that happened to be on disk at launch.
      SharedPreferences.setMockInitialValues(<String, Object>{
        RestoreTabsSettingsCodec.prefsKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs);

      container
          .read(appSettingsProvider.notifier)
          .setRestoreTabsOnLaunch(enabled: false);
      await _settle();
      await _settle();
      await _settle();

      expect(container.read(appSettingsProvider).restoreTabsOnLaunch, isFalse);
    });

    test('a settings-store failure never breaks the toggle', () async {
      final container = ProviderContainer(
        overrides: [
          restoreTabsSettingsServiceProvider.overrideWithValue(
            const SettingsService<bool>(_ThrowingCodec()),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(appSettingsProvider.notifier)
          .setRestoreTabsOnLaunch(enabled: false);
      await _settle();
      expect(container.read(appSettingsProvider).restoreTabsOnLaunch, isFalse);
    });
  });

  // `bootstrap` calls this once, before `runApp`, and hands the result to
  // `launchRestoreDecisionProvider`. Keeping the storage read out here — and
  // out of the workspace notifier — is what stops every workspace-touching
  // widget test from hanging on a real-event-loop `SharedPreferences` reply.
  group('loadRestoreTabsOnLaunch', () {
    test('returns the persisted value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        RestoreTabsSettingsCodec.prefsKey: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final value = await loadRestoreTabsOnLaunch(
        service: SettingsService<bool>(
          const RestoreTabsSettingsCodec(),
          prefsOverride: prefs,
        ),
      );
      expect(value, isFalse);
    });

    test('defaults to restoring when nothing is persisted', () async {
      final prefs = await SharedPreferences.getInstance();
      final value = await loadRestoreTabsOnLaunch(
        service: SettingsService<bool>(
          const RestoreTabsSettingsCodec(),
          prefsOverride: prefs,
        ),
      );
      expect(value, isTrue);
    });

    test('defaults to restoring when the store throws', () async {
      final value = await loadRestoreTabsOnLaunch(
        service: const SettingsService<bool>(_ThrowingCodec()),
      );
      expect(value, isTrue);
    });
  });

  test('launchRestoreDecisionProvider defaults to restoring', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(launchRestoreDecisionProvider), isTrue);
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
