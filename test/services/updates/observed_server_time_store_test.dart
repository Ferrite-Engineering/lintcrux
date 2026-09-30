// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/updates/observed_server_time_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('ObservedServerTimeStore', () {
    test('starts null when nothing has been persisted', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(observedServerTimeStoreProvider), isNull);
      await _settle();
      expect(container.read(observedServerTimeStoreProvider), isNull);
    });

    test('record advances the state and persists it as ISO-8601', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final observed = DateTime.utc(2026, 9, 15, 12);
      await container
          .read(observedServerTimeStoreProvider.notifier)
          .record(observed);

      expect(container.read(observedServerTimeStoreProvider), observed);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ObservedServerTimeStore.prefsKey),
        observed.toIso8601String(),
      );
    });

    test('record is monotonic — an earlier observation is ignored', () async {
      // The whole point of the store: a stale cached manifest, a CDN replaying
      // an old response, or a mis-set server clock must never roll the trusted
      // watermark backward, because that would hand back the clock rollback
      // this mechanism exists to defeat.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        observedServerTimeStoreProvider.notifier,
      );

      final later = DateTime.utc(2026, 9, 15, 12);
      final earlier = DateTime.utc(2026, 9);
      await notifier.record(later);
      await notifier.record(earlier);

      expect(container.read(observedServerTimeStoreProvider), later);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(ObservedServerTimeStore.prefsKey),
        later.toIso8601String(),
      );
    });

    test('an equal observation does not re-persist', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(
        observedServerTimeStoreProvider.notifier,
      );
      final t = DateTime.utc(2026, 9, 15, 12);
      await notifier.record(t);
      await notifier.record(t);
      expect(container.read(observedServerTimeStoreProvider), t);
    });

    test('a persisted value is restored on build', () async {
      // The offline-launch case: the app has seen a server time before, is
      // now offline, and must still reckon expiry against that watermark.
      final persisted = DateTime.utc(2026, 9, 15, 12);
      SharedPreferences.setMockInitialValues(<String, Object>{
        ObservedServerTimeStore.prefsKey: persisted.toIso8601String(),
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(observedServerTimeStoreProvider), isNull);
      await _settle();
      await _settle();
      expect(container.read(observedServerTimeStoreProvider), persisted);
    });

    test('a corrupt persisted value is ignored, not fatal', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ObservedServerTimeStore.prefsKey: 'not-a-timestamp',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _settle();
      await _settle();
      expect(container.read(observedServerTimeStoreProvider), isNull);
    });
  });

  group('store → crux_license wiring', () {
    ProviderContainer wired() {
      final container = ProviderContainer(
        overrides: [
          observedServerTimeProvider.overrideWith(
            (ref) => ref.watch(observedServerTimeStoreProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an observation flows into observedServerTimeProvider', () async {
      final container = wired();
      expect(container.read(observedServerTimeProvider), isNull);

      final observed = DateTime.utc(2026, 9, 15, 12);
      await container
          .read(observedServerTimeStoreProvider.notifier)
          .record(observed);

      expect(container.read(observedServerTimeProvider), observed);
    });

    test(
      'CLOCK TAMPERING: a device clock set back cannot defer expiry',
      () async {
        // Reproduces the attack the hardening exists for, end to end through
        // LintCrux's own wiring rather than only the pure `crux_license`
        // helpers: the user winds the device clock back to well before the
        // expiry date, but the app has already observed a server time past it.
        final container = wired();
        final expiryDate = DateTime(2026, 9);
        final deviceNow = DateTime(2026); // rolled back eight months
        final serverTime = DateTime(2026, 9, 2); // past the expiry date

        // Control: on the device clock alone the build looks perfectly fine.
        expect(
          betaExpiryStatusFor(deviceNow, expiry: expiryDate),
          BetaExpiryStatus.active,
        );

        await container
            .read(observedServerTimeStoreProvider.notifier)
            .record(serverTime);
        final trusted = trustedBetaExpiryNow(
          deviceNow,
          observedServerTime: container.read(observedServerTimeProvider),
        );

        expect(trusted, serverTime);
        expect(
          betaExpiryStatusFor(trusted, expiry: expiryDate),
          BetaExpiryStatus.expired,
        );
      },
    );

    test(
      'a fresh install with no observation falls back to the device clock',
      () {
        final container = wired();
        final deviceNow = DateTime(2026);
        expect(container.read(observedServerTimeProvider), isNull);
        expect(
          trustedBetaExpiryNow(
            deviceNow,
            observedServerTime: container.read(observedServerTimeProvider),
          ),
          deviceNow,
        );
      },
    );

    test('a device clock ahead of the watermark still wins', () async {
      // The normal case — time passes between manifest fetches. Taking the
      // maximum must not freeze the clock at the last observation.
      final container = wired();
      final serverTime = DateTime(2026, 9, 15, 9);
      final deviceNow = DateTime(2026, 9, 15, 12);
      await container
          .read(observedServerTimeStoreProvider.notifier)
          .record(serverTime);
      expect(
        trustedBetaExpiryNow(
          deviceNow,
          observedServerTime: container.read(observedServerTimeProvider),
        ),
        deviceNow,
      );
    });
  });
}
