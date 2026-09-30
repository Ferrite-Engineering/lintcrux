// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_config.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_storage.dart';
import 'package:lintcrux/core/telemetry/lintcrux_web_telemetry_storage.dart';
import 'package:lintcrux/features/telemetry/lintcrux_telemetry_overrides.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the browser keeps the usage-statistics decision.
///
/// The desktop adapter is a JSON file so `lintcrux --ci` reads the consent
/// the app wrote. In a browser every one of its `dart:io` calls fails, so
/// once the beta ended the viewer asked for consent on every visit, forgot
/// each answer, and minted a new installation id per session. The browser
/// therefore gets `SharedPreferences` — `localStorage` there, and what the
/// other three products use — while the desktop keeps the file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('which store this build uses', () {
    test('the browser gets the preference store', () {
      expect(
        lintcruxTelemetryStorageFor(web: true),
        isA<LintcruxWebTelemetryStorage>(),
      );
    });

    test('the desktop keeps the file the headless binary reads', () {
      // `lintcrux --ci` loads no plugin, so the file stays the one source of
      // truth off the browser.
      expect(
        lintcruxTelemetryStorageFor(web: false),
        isA<LintcruxTelemetryStorage>(),
      );
      expect(
        (lintcruxTelemetryStorageFor(web: false) as LintcruxTelemetryStorage)
            .filePath,
        const LintcruxTelemetryStorage().filePath,
      );
    });
  });

  group('the browser store', () {
    test('an answer survives a reload', () async {
      // A page load builds a fresh adapter over the same preferences, which
      // is what "the disclosure came back every visit" was about.
      await const LintcruxWebTelemetryStorage().write(
        kTelemetryConsentKey,
        TelemetryConsentState.enabled.name,
      );

      expect(
        await const LintcruxWebTelemetryStorage().read(kTelemetryConsentKey),
        TelemetryConsentState.enabled.name,
      );
    });

    test('the installation id survives too, under the suite-fixed key', () {
      // An id re-minted per session makes distinct installations
      // uncountable.
      const id = '00000000-0000-4000-8000-000000000001';
      return const LintcruxWebTelemetryStorage()
          .write(kTelemetryInstallationIdKey, id)
          .then((_) async {
            final prefs = await SharedPreferences.getInstance();
            expect(prefs.getString('telemetry.installationId'), id);
            expect(
              await const LintcruxWebTelemetryStorage().read(
                kTelemetryInstallationIdKey,
              ),
              id,
            );
          });
    });

    test(
      'a value never written reads null, and a removed one is gone',
      () async {
        const store = LintcruxWebTelemetryStorage();
        expect(await store.read(kTelemetryConsentKey), isNull);

        await store.write(kTelemetryConsentKey, 'disabled');
        await store.remove(kTelemetryConsentKey);

        expect(await store.read(kTelemetryConsentKey), isNull);
      },
    );
  });

  group('the disclosure, in a browser', () {
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(
            lintcruxTelemetryConfig,
          ),
          telemetryStorageProvider.overrideWithValue(
            lintcruxTelemetryStorageFor(web: true),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('is offered when nothing was ever answered', () async {
      final c = container();
      await c.read(telemetryConsentReadyProvider.future);
      expect(c.read(telemetryConsentPromptVisibleProvider), isTrue);
    });

    test('does not come back on the next visit once answered', () async {
      // The previous visit's answer, as the store left it.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry.consent': TelemetryConsentState.disabled.name,
      });

      final c = container();
      await c.read(telemetryConsentReadyProvider.future);

      expect(c.read(telemetryConsentPromptVisibleProvider), isFalse);
      expect(c.read(telemetryEnabledProvider), isFalse);
    });

    test('an answered yes is still yes on the next visit', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry.consent': TelemetryConsentState.enabled.name,
      });

      final c = container();
      await c.read(telemetryConsentReadyProvider.future);

      expect(c.read(telemetryConsentPromptVisibleProvider), isFalse);
      expect(c.read(telemetryEnabledProvider), isTrue);
    });
  });
}
