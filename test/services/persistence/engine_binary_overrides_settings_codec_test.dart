// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/persistence/engine_binary_overrides_settings_codec.dart';
import 'package:lintcrux/services/persistence/engine_binary_overrides_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

const _custom = EngineBinaryOverride(
  source: EngineBinarySource.custom,
  path: '/opt/verilator/bin/verilator',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('EngineBinaryOverridesSettingsCodec', () {
    test('nothing stored reads as no overrides', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        await const EngineBinaryOverridesSettingsCodec().load(prefs),
        isEmpty,
      );
    });

    test('round-trips Custom paths and Bundled choices', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = EngineBinaryOverridesSettingsCodec();
      const saved = <String, EngineBinaryOverride>{
        'verilator': _custom,
        'yosys': EngineBinaryOverride(source: EngineBinarySource.bundled),
      };
      await codec.save(prefs, saved);
      expect(await codec.load(prefs), saved);
    });

    test('an unreadable entry is dropped, the rest survive', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        EngineBinaryOverridesSettingsCodec.prefsKey:
            '{"verilator":{"source":"custom","path":"/opt/v"},'
            '"slang":{"source":"teleported"},"ghdl":7}',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        await const EngineBinaryOverridesSettingsCodec().load(prefs),
        const <String, EngineBinaryOverride>{
          'verilator': EngineBinaryOverride(
            source: EngineBinarySource.custom,
            path: '/opt/v',
          ),
        },
      );
    });

    test('malformed JSON reads as no overrides', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        EngineBinaryOverridesSettingsCodec.prefsKey: '{not json',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        await const EngineBinaryOverridesSettingsCodec().load(prefs),
        isEmpty,
      );
    });
  });

  group('AppSettingsNotifier and engine binary persistence', () {
    ProviderContainer containerOver(
      SharedPreferences prefs, {
      Map<String, EngineBinaryOverride> atLaunch =
          const <String, EngineBinaryOverride>{},
    }) {
      final container = ProviderContainer(
        overrides: [
          engineBinaryOverridesSettingsServiceProvider.overrideWithValue(
            SettingsService<Map<String, EngineBinaryOverride>>(
              const EngineBinaryOverridesSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
          launchEngineBinaryOverridesProvider.overrideWithValue(atLaunch),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a Custom path set in Settings is saved', () async {
      final prefs = await SharedPreferences.getInstance();
      containerOver(prefs)
          .read(appSettingsProvider.notifier)
          .setEngineBinaryOverride('verilator', _custom);
      await _settle();
      await _settle();
      expect(
        await const EngineBinaryOverridesSettingsCodec().load(prefs),
        const <String, EngineBinaryOverride>{'verilator': _custom},
      );
    });

    test('switching back to Auto-detect removes the saved path', () async {
      final prefs = await SharedPreferences.getInstance();
      containerOver(prefs).read(appSettingsProvider.notifier)
        ..setEngineBinaryOverride('verilator', _custom)
        ..setEngineBinaryOverride('verilator', EngineBinaryOverride.autoDetect);
      await _settle();
      await _settle();
      expect(
        await const EngineBinaryOverridesSettingsCodec().load(prefs),
        isEmpty,
      );
    });

    test('the launch snapshot seeds the settings synchronously', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = containerOver(
        prefs,
        atLaunch: const <String, EngineBinaryOverride>{'verilator': _custom},
      );
      // No settle: the first run of a restored tab reads this immediately.
      expect(
        container
            .read(appSettingsProvider)
            .engineBinaryOverrideFor('verilator'),
        _custom,
      );
    });

    test(
      'loadEngineBinaryOverrides reads what a previous session saved',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await const EngineBinaryOverridesSettingsCodec().save(
          prefs,
          const <String, EngineBinaryOverride>{'verilator': _custom},
        );
        expect(
          await loadEngineBinaryOverrides(
            service: SettingsService<Map<String, EngineBinaryOverride>>(
              const EngineBinaryOverridesSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
          const <String, EngineBinaryOverride>{'verilator': _custom},
        );
      },
    );
  });
}
