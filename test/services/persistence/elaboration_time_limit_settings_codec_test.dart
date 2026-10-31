// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/elaboration_time_limit.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/persistence/elaboration_time_limit_settings_codec.dart';
import 'package:lintcrux/services/persistence/elaboration_time_limit_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

ProviderContainer _containerWith(SharedPreferences prefs) {
  final container = ProviderContainer(
    overrides: [
      elaborationTimeLimitSettingsServiceProvider.overrideWithValue(
        SettingsService<ElaborationTimeLimit>(
          const ElaborationTimeLimitSettingsCodec(),
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

  group('ElaborationTimeLimitSettingsCodec', () {
    test('defaults to Automatic when nothing is stored', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        await const ElaborationTimeLimitSettingsCodec().load(prefs),
        ElaborationTimeLimit.automatic,
      );
    });

    test('round-trips every choice', () async {
      final prefs = await SharedPreferences.getInstance();
      const codec = ElaborationTimeLimitSettingsCodec();
      for (final limit in ElaborationTimeLimit.values) {
        await codec.save(prefs, limit);
        expect(await codec.load(prefs), limit, reason: limit.name);
      }
    });

    test('an unknown name or a wrong type reads as Automatic', () async {
      for (final stored in <Object>['forever', 3]) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          ElaborationTimeLimitSettingsCodec.prefsKey: stored,
        });
        final prefs = await SharedPreferences.getInstance();
        expect(
          await const ElaborationTimeLimitSettingsCodec().load(prefs),
          ElaborationTimeLimit.automatic,
          reason: '$stored',
        );
      }
    });
  });

  group('AppSettingsNotifier and the Yosys time limit', () {
    test('defaults to Automatic', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(
        _containerWith(prefs).read(appSettingsProvider).elaborationTimeLimit,
        ElaborationTimeLimit.automatic,
      );
    });

    test('setElaborationTimeLimit persists through the service', () async {
      final prefs = await SharedPreferences.getInstance();
      final container = _containerWith(prefs);
      container
          .read(appSettingsProvider.notifier)
          .setElaborationTimeLimit(ElaborationTimeLimit.extended);
      await _settle();
      expect(
        container.read(appSettingsProvider).elaborationTimeLimit,
        ElaborationTimeLimit.extended,
      );
      expect(
        prefs.getString(ElaborationTimeLimitSettingsCodec.prefsKey),
        'extended',
      );
    });

    test('a persisted choice survives a relaunch', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ElaborationTimeLimitSettingsCodec.prefsKey: 'none',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = _containerWith(prefs);
      expect(
        container.read(appSettingsProvider).elaborationTimeLimit,
        ElaborationTimeLimit.automatic,
        reason: 'the model default until the restore lands',
      );
      await _settle();
      await _settle();
      expect(
        container.read(appSettingsProvider).elaborationTimeLimit,
        ElaborationTimeLimit.none,
      );
    });

    test('a choice made before the restore lands is not undone', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ElaborationTimeLimitSettingsCodec.prefsKey: 'none',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = _containerWith(prefs);
      container
          .read(appSettingsProvider.notifier)
          .setElaborationTimeLimit(ElaborationTimeLimit.extended);
      await _settle();
      await _settle();
      expect(
        container.read(appSettingsProvider).elaborationTimeLimit,
        ElaborationTimeLimit.extended,
      );
    });
  });
}
