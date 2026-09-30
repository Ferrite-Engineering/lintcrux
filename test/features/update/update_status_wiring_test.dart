// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/update/lintcrux_update_config.dart';
import 'package:lintcrux/services/updates/observed_server_time_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _buildInfo = ApplicationBuildInfo(
  version: '1.0.0',
  buildNumber: '1',
  gitShortSha: 'abc1234',
  os: 'macOS 15.0',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.2',
  dartSdkVersion: '3.12.0',
);

String _manifest({
  String version = '2.0.0',
  bool mandatory = false,
  String? serverTime,
}) => jsonEncode({
  'latest': {
    'version': version,
    'mandatory': mandatory,
    'server_time': ?serverTime,
  },
});

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Builds the production update graph — LintCrux's real config, strings and
/// server-time sink — over a mock HTTP client.
({ProviderContainer container, int Function() requests}) _harness({
  String body = '',
  int status = 200,
  bool autoCheckEnabled = true,
}) {
  var requests = 0;
  final client = MockClient((request) async {
    requests++;
    return http.Response(body.isEmpty ? _manifest() : body, status);
  });

  final container = ProviderContainer(
    overrides: [
      cruxUpdateConfigProvider.overrideWithValue(lintcruxUpdateConfig),
      updateBuildInfoProvider.overrideWith((_) async => _buildInfo),
      updateHttpClientProvider.overrideWithValue(client),
      autoUpdateCheckEnabledProvider.overrideWith(
        (ref) async => ref.watch(appSettingsProvider).autoCheckForUpdates,
      ),
      observedServerTimeSinkProvider.overrideWith(
        (ref) =>
            (serverTime) => ref
                .read(observedServerTimeStoreProvider.notifier)
                .record(serverTime),
      ),
      observedServerTimeProvider.overrideWith(
        (ref) => ref.watch(observedServerTimeStoreProvider),
      ),
      if (!autoCheckEnabled)
        appSettingsProvider.overrideWith(_DisabledAutoCheckNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, requests: () => requests);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // `flutter_test` reports `TargetPlatform.android` by default, and
    // `updateCheckServiceProvider` substitutes a NoopUpdateCheckService on
    // mobile unless `checkOnMobile` is set — which LintCrux deliberately
    // leaves off, having no mobile target. Without this the whole suite
    // would pass vacuously against a service that never fetches anything.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('update status — LintCrux wiring', () {
    test('the launch check runs and surfaces an available update', () async {
      final h = _harness(body: _manifest());
      // Reading the provider constructs the notifier, which fires the launch
      // check through the gated path.
      expect(
        h.container.read(updateStatusProvider),
        isA<UpdateStatusCurrent>(),
      );
      await _settle();
      await _settle();
      await _settle();

      expect(h.requests(), 1);
      final status = h.container.read(updateStatusProvider);
      expect(status, isA<UpdateStatusAvailable>());
      expect((status as UpdateStatusAvailable).info.version, '2.0.0');
    });

    test('a build that is already current resolves to current', () async {
      final h = _harness(body: _manifest(version: '1.0.0'));
      h.container.read(updateStatusProvider);
      await _settle();
      await _settle();
      await _settle();
      expect(
        h.container.read(updateStatusProvider),
        isA<UpdateStatusCurrent>(),
      );
    });

    test('the auto-check toggle suppresses the automatic check', () async {
      final h = _harness(autoCheckEnabled: false);
      h.container.read(updateStatusProvider);
      await _settle();
      await _settle();
      await _settle();

      expect(h.requests(), 0);
      expect(
        h.container.read(updateStatusProvider),
        isA<UpdateStatusCurrent>(),
      );
    });

    test('a manual check runs even with the toggle off', () async {
      // The contract that keeps the Help-menu entry honest: a user who turned
      // automatic checks off can still ask, and gets a real answer.
      final h = _harness(
        autoCheckEnabled: false,
      );
      h.container.read(updateStatusProvider);
      await _settle();
      expect(h.requests(), 0);

      await h.container.read(updateStatusProvider.notifier).checkNow();
      expect(h.requests(), 1);
      expect(
        h.container.read(updateStatusProvider),
        isA<UpdateStatusAvailable>(),
      );
    });

    test('runScheduledCheck honours the toggle; checkNow does not', () async {
      final h = _harness(autoCheckEnabled: false);
      final notifier = h.container.read(updateStatusProvider.notifier);
      await _settle();

      await notifier.runScheduledCheck();
      expect(h.requests(), 0);

      await notifier.checkNow();
      expect(h.requests(), 1);
    });

    test('a transport failure resolves to error, never a throw', () async {
      final h = _harness(status: 500);
      h.container.read(updateStatusProvider);
      await _settle();
      await _settle();
      await _settle();
      expect(h.container.read(updateStatusProvider), isA<UpdateStatusError>());
    });

    test('a malformed manifest fails soft', () async {
      final h = _harness(body: '{ this is not json');
      h.container.read(updateStatusProvider);
      await _settle();
      await _settle();
      await _settle();
      expect(h.container.read(updateStatusProvider), isA<UpdateStatusError>());
    });

    test('a mandatory update is reported as mandatory', () async {
      final h = _harness(body: _manifest(mandatory: true));
      h.container.read(updateStatusProvider);
      await _settle();
      await _settle();
      await _settle();
      final status =
          h.container.read(updateStatusProvider) as UpdateStatusAvailable;
      expect(status.info.mandatory, isTrue);
    });

    test(
      'a successful check records server_time into the persisted store',
      () async {
        // The link that hardens beta expiry: every successful fetch — even one
        // that reports the build is current — advances the trusted watermark.
        final h = _harness(
          body: _manifest(
            version: '1.0.0',
            serverTime: '2026-09-15T12:00:00Z',
          ),
        );
        h.container.read(updateStatusProvider);
        await _settle();
        await _settle();
        await _settle();

        expect(
          h.container.read(observedServerTimeStoreProvider),
          DateTime.parse('2026-09-15T12:00:00Z'),
        );
        expect(
          h.container.read(observedServerTimeProvider),
          DateTime.parse('2026-09-15T12:00:00Z'),
        );
      },
    );
  });
}

/// An [AppSettings] notifier whose automatic update check is off, standing in
/// for a user who turned the Settings → General toggle off in a prior session.
class _DisabledAutoCheckNotifier extends AppSettingsNotifier {
  @override
  AppSettings build() => const AppSettings(autoCheckForUpdates: false);
}
