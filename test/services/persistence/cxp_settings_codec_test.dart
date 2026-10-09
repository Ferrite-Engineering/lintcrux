// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/persistence/cxp_settings_codec.dart';
import 'package:lintcrux/services/persistence/cxp_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

const _allOff = CxpSettings(
  serverEnabled: false,
  serverPort: 55000,
  requestAttention: false,
  broadcastSelection: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('CxpSettingsCodec', () {
    test("nothing stored reads as AppSettings' defaults", () async {
      final prefs = await SharedPreferences.getInstance();
      final loaded = await const CxpSettingsCodec().load(prefs);
      expect(loaded, const CxpSettings());
      expect(loaded, CxpSettings.of(const AppSettings()));
    });

    test('round-trips every field', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = CxpSettingsCodec();
      await codec.save(prefs, _allOff);
      expect(await codec.load(prefs), _allOff);
    });

    test('a mistyped or out-of-range value falls back for that field '
        'only', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        CxpSettingsCodec.serverEnabledKey: 'no',
        CxpSettingsCodec.serverPortKey: 70000,
        CxpSettingsCodec.requestAttentionKey: false,
      });
      final prefs = await SharedPreferences.getInstance();
      final loaded = await const CxpSettingsCodec().load(prefs);
      expect(loaded.serverEnabled, isTrue);
      expect(loaded.serverPort, AppSettings.defaultCxpServerPort);
      expect(loaded.requestAttention, isFalse);
    });
  });

  group('AppSettingsNotifier and CXP persistence', () {
    ProviderContainer containerOver(
      SharedPreferences prefs, {
      CxpSettings atLaunch = const CxpSettings(),
    }) {
      final container = ProviderContainer(
        overrides: [
          cxpSettingsServiceProvider.overrideWithValue(
            SettingsService<CxpSettings>(
              const CxpSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
          launchCxpSettingsProvider.overrideWithValue(atLaunch),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('turning the CXP server off is saved', () async {
      final prefs = await SharedPreferences.getInstance();
      containerOver(
        prefs,
      ).read(appSettingsProvider.notifier).setCxpServerEnabled(enabled: false);
      await _settle();
      await _settle();
      expect(
        (await const CxpSettingsCodec().load(prefs)).serverEnabled,
        isFalse,
      );
    });

    test('every CXP setter saves the whole set', () async {
      final prefs = await SharedPreferences.getInstance();
      containerOver(prefs).read(appSettingsProvider.notifier)
        ..setCxpServerEnabled(enabled: false)
        ..setCxpServerPort(55000)
        ..setRequestAttentionOnCrossProbe(enabled: false)
        ..setBroadcastSelectionOnCrossProbe(enabled: false);
      await _settle();
      await _settle();
      expect(await const CxpSettingsCodec().load(prefs), _allOff);
    });

    test('the launch snapshot seeds the settings synchronously', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(prefs, atLaunch: _allOff);
      // No settle: the CXP server lifecycle reads this on its first build,
      // and a launch with CXP off must never start the server.
      final settings = container.read(appSettingsProvider);
      expect(settings.cxpServerEnabled, isFalse);
      expect(settings.cxpServerPort, 55000);
      expect(settings.requestAttentionOnCrossProbe, isFalse);
      expect(settings.broadcastSelectionOnCrossProbe, isFalse);
    });

    test('loadCxpSettings reads what a previous session saved', () async {
      final prefs = await SharedPreferences.getInstance();
      await const CxpSettingsCodec().save(prefs, _allOff);
      expect(
        await loadCxpSettings(
          service: SettingsService<CxpSettings>(
            const CxpSettingsCodec(),
            prefsOverride: prefs,
          ),
        ),
        _allOff,
      );
    });
  });
}
