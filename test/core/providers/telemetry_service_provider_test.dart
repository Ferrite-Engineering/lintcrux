// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart'
    show betaPeriodProvider, kBetaPeriod;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_config.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_storage.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_strings.dart';
import 'package:lintcrux/features/settings/screens/settings_screen.dart';
import 'package:lintcrux/features/telemetry/lintcrux_telemetry_overrides.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;

import '../../support/telemetry_test_store.dart';

/// LintCrux's half of the telemetry gate.
///
/// The 12-cell `beta × dev × consent` gating matrix and the traffic-level
/// beta-inert test live in `crux_telemetry` — they exercise the gate itself,
/// which is shared. What cannot move, and is asserted here, is that **this
/// build** is wired so the gate actually holds:
///
///  * the real `kBetaPeriod` / `kTelemetryDev` constants this release ships
///    with leave telemetry waiting on consent through LintCrux's own
///    configuration, and an unanswered disclosure sends nothing;
///  * `betaPeriodProvider` — which a product may override for badging
///    reasons — neither starts nor stops collection;
///  * with the beta pinned on, neither consent surface mounts.
///
/// The matrix is re-run here anyway, over LintCrux's own container, because
/// the package's version proves the gate is right and this one proves LintCrux
/// is plugged into it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TelemetryTestStore store;

  setUp(() => store = TelemetryTestStore());

  /// The root container `bootstrap` builds, minus the network.
  ProviderContainer lintcruxContainer({List<Override> extra = const []}) {
    final container = ProviderContainer(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(lintcruxTelemetryConfig),
        telemetryStorageProvider.overrideWithValue(store),
        telemetryHttpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('{}', 202)),
        ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group("LintCrux's side of the telemetry gate", () {
    test(
      'the shipping build is past the beta: telemetry waits on consent',
      () async {
        // The flip that activated telemetry is this constant, and nothing
        // else. With it off, an installation that has not answered the
        // disclosure buffers until its stored answer is read back — and, once
        // that answer turns out to be "not yet", keeps buffering while the
        // disclosure asks. Nothing is sent either way: `unset` is never
        // consent.
        expect(kBetaPeriod, isFalse);
        expect(kTelemetryDev, isFalse);

        final container = lintcruxContainer();
        expect(
          container.read(telemetryServiceProvider),
          isA<PendingTelemetryService>(),
        );
        await container.read(telemetryConsentReadyProvider.future);
        expect(container.read(telemetryEnabledProvider), isFalse);
        expect(
          container.read(telemetryServiceProvider),
          isA<PendingTelemetryService>(),
        );
        expect(container.read(telemetryGateProvider), TelemetryGate.closed);
      },
    );

    test('with the beta pinned on, an explicit `enabled` consent stays '
        'inert', () async {
      // The dark launch, pinned explicitly now that the shipping default is
      // past it: during a beta nothing is collected whatever the user said.
      final container = lintcruxContainer(
        extra: [telemetryBetaPeriodProvider.overrideWithValue(true)],
      );
      container.read(telemetryConsentStoreProvider.notifier).state =
          TelemetryConsentState.enabled;
      await container.read(telemetryConsentReadyProvider.future);

      expect(container.read(telemetryEnabledProvider), isFalse);
      expect(
        container.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );
    });

    test('telemetry does not key off betaPeriodProvider', () async {
      // LintCrux ships desktop-only, so it has no mobile-store badging
      // override of `betaPeriodProvider` today; WaveCrux overrides it on
      // iOS/Android so a store build does not advertise a public beta (App
      // Store Review Guideline 2.2). This asserts the property that makes such
      // an override safe to add here later: `telemetryBetaPeriodProvider`
      // reads the `kBetaPeriod` constant, not the provider, so a badging
      // decision can neither start nor stop collection. A provider that still
      // claims the beta leaves a consented installation live.
      final container = lintcruxContainer(
        extra: [betaPeriodProvider.overrideWithValue(true)],
      );
      container.read(telemetryConsentStoreProvider.notifier).state =
          TelemetryConsentState.enabled;
      await container.read(telemetryConsentReadyProvider.future);

      expect(container.read(telemetryEnabledProvider), isTrue);
      expect(
        container.read(telemetryServiceProvider),
        isA<LiveTelemetryService>(),
      );
    });

    testWidgets(
      'during beta with no dev flag, neither consent surface mounts',
      (tester) async {
        // The dark launch covers the UI too. A beta build must not show the
        // first-launch disclosure or the Settings → Privacy category: there is
        // nothing to consent to, and asking would advertise collection this
        // build is structurally incapable of doing.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cruxTelemetryConfigProvider.overrideWithValue(
                lintcruxTelemetryConfig,
              ),
              cruxTelemetryStringsProvider.overrideWith(
                (ref) =>
                    LintcruxTelemetryStrings(lookupL10N(const Locale('en'))),
              ),
              telemetryStorageProvider.overrideWithValue(store),
              telemetryBetaPeriodProvider.overrideWithValue(true),
              telemetryDevModeProvider.overrideWithValue(false),
              telemetryHttpClientProvider.overrideWithValue(
                MockClient((_) async => http.Response('{}', 202)),
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: [L10N.delegate],
              supportedLocales: L10N.supportedLocales,
              home: TelemetryConsentGate(child: SettingsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TelemetryConsentDisclosure), findsNothing);
        expect(find.text('Privacy'), findsNothing);
        expect(find.byKey(const Key('settingsTelemetrySwitch')), findsNothing);
      },
    );
  });

  group('the full gating matrix (beta × dev × tri-state consent)', () {
    // Twelve cells. The only two that transmit are post-beta + `enabled`, and
    // dev-flag + (`enabled` or `unset`) — `unset` counts as enabled under the
    // dev flag so end-to-end staging verification needs no UI, and `disabled`
    // never transmits under any combination.
    const cells =
        <({bool beta, bool dev, TelemetryConsentState consent, bool on})>[
          (
            beta: true,
            dev: false,
            consent: TelemetryConsentState.unset,
            on: false,
          ),
          (
            beta: true,
            dev: false,
            consent: TelemetryConsentState.enabled,
            on: false,
          ),
          (
            beta: true,
            dev: false,
            consent: TelemetryConsentState.disabled,
            on: false,
          ),
          (
            beta: true,
            dev: true,
            consent: TelemetryConsentState.unset,
            on: true,
          ),
          (
            beta: true,
            dev: true,
            consent: TelemetryConsentState.enabled,
            on: true,
          ),
          (
            beta: true,
            dev: true,
            consent: TelemetryConsentState.disabled,
            on: false,
          ),
          (
            beta: false,
            dev: false,
            consent: TelemetryConsentState.unset,
            on: false,
          ),
          (
            beta: false,
            dev: false,
            consent: TelemetryConsentState.enabled,
            on: true,
          ),
          (
            beta: false,
            dev: false,
            consent: TelemetryConsentState.disabled,
            on: false,
          ),
          (
            beta: false,
            dev: true,
            consent: TelemetryConsentState.unset,
            on: true,
          ),
          (
            beta: false,
            dev: true,
            consent: TelemetryConsentState.enabled,
            on: true,
          ),
          (
            beta: false,
            dev: true,
            consent: TelemetryConsentState.disabled,
            on: false,
          ),
        ];

    for (final cell in cells) {
      // Post-beta and unanswered is the disclosure on screen: the launch's
      // events wait for its answer rather than being discarded, and still
      // nothing transmits. Every other `on: false` cell is a real no.
      final waits =
          !cell.beta &&
          !cell.dev &&
          cell.consent == TelemetryConsentState.unset;
      test(
        'beta=${cell.beta} dev=${cell.dev} consent=${cell.consent.name} '
        '→ ${cell.on
            ? "live"
            : waits
            ? "pending"
            : "no-op"}',
        () async {
          final container = lintcruxContainer(
            extra: [
              telemetryBetaPeriodProvider.overrideWithValue(cell.beta),
              telemetryDevModeProvider.overrideWithValue(cell.dev),
            ],
          );
          container.read(telemetryConsentStoreProvider.notifier).state =
              cell.consent;
          // These cells state the SETTLED behaviour. Under the dev flag
          // `unset` counts as consent only once the store has read its
          // persisted value back — before that a stored refusal wears the same
          // value, which is how a `disabled` installation once transmitted.
          await container.read(telemetryConsentReadyProvider.future);

          expect(container.read(telemetryEnabledProvider), cell.on);
          expect(
            container.read(telemetryServiceProvider),
            cell.on
                ? isA<LiveTelemetryService>()
                : waits
                ? isA<PendingTelemetryService>()
                : isA<NoopTelemetryService>(),
          );
        },
      );
    }
  });

  group("LintCrux's envelope wiring", () {
    test('reports the lintcrux slug and a Worker-legal envelope', () async {
      // The product slug is the one field `crux_telemetry` cannot supply, and
      // a slug the Worker does not know rejects every batch LintCrux ever
      // sends with a 400 the client never sees.
      final container = lintcruxContainer(
        extra: [telemetryAppVersionProvider.overrideWith((_) async => '0.6.0')],
      );

      final envelope = await container.read(
        telemetryEnvelopeResolverProvider,
      )();

      expect(envelope, isNotNull);
      expect(envelope!.product, 'lintcrux');
      expect(envelope.userAgent, 'LintCrux/0.6.0');
      expect(kTelemetryOperatingSystems, contains(envelope.os));
      expect(kTelemetryFormFactors, contains(envelope.formFactor));
      expect(kTelemetryLicenseTiers, contains(envelope.licenseTier));
      expect(
        kTelemetryInstallationIdPattern.hasMatch(envelope.installationId),
        isTrue,
      );
    });

    test('the installation id persists under the suite-fixed key', () async {
      final id = await lintcruxContainer().read(
        telemetryInstallationIdProvider.future,
      );

      expect(store.values['telemetry.installationId'], id);
      expect(kTelemetryInstallationIdKey, 'telemetry.installationId');
      expect(kTelemetryConsentKey, 'telemetry.consent');
    });

    test('the endpoint is the production suite ingest', () {
      // Not a dev build, so not the staging dataset. The path selects the
      // dataset; nothing LintCrux sends can move it.
      expect(
        lintcruxContainer().read(telemetryEndpointProvider).toString(),
        'https://telemetry.edacrux.app/v1/events',
      );
    });

    test('the desktop storage adapter is the file-backed one', () {
      // The deliberate LintCrux deviation from WaveCrux: the headless binary
      // has to read the same decision, and `shared_preferences` is a plugin it
      // cannot load. If this ever goes back to a preferences-backed store,
      // `lintcrux --ci` silently stops honoring the consent the user gave.
      // (The browser has no headless surface and no `dart:io`; it gets the
      // preference store — see lintcrux_web_telemetry_storage_test.dart.)
      expect(
        lintcruxTelemetryStorageFor(web: false),
        isA<LintcruxTelemetryStorage>(),
      );
      // p.join, not a literal: this asserts the *host's* real path, and on a
      // Windows runner that legitimately uses backslashes. A hardcoded POSIX
      // tail passes on macOS and Linux and fails on Windows for a reason that
      // has nothing to do with what the test is checking.
      expect(
        const LintcruxTelemetryStorage().filePath,
        endsWith(p.join('crux', 'telemetry', 'lintcrux.json')),
      );
    });
  });

  group('the seam itself', () {
    test('can be overridden with a recording fake', () {
      final recorder = RecordingTelemetryService();
      final container = ProviderContainer(
        overrides: [telemetryServiceProvider.overrideWithValue(recorder)],
      );
      addTearDown(container.dispose);

      container
          .read(telemetryServiceProvider)
          .record(TelemetryEvent('sarif.imported'));

      expect(recorder.events, hasLength(1));
      expect(recorder.events.first.name, 'sarif.imported');
    });
  });
}
