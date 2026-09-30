// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_config.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_strings.dart';
import 'package:lintcrux/features/beta_expiry/beta_expiry_metrics.dart';
import 'package:lintcrux/features/settings/screens/settings_screen.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

import '../../support/telemetry_test_store.dart';

/// The two consent surfaces, in LintCrux's own copy and at LintCrux's own
/// sizes.
///
/// The widgets themselves are `crux_telemetry`'s and have their own tests over
/// there — directionality, text scale, the pre-armed toggle, the dismissal
/// contract. What is LintCrux's, and asserted here, is:
///
///  * every string on both surfaces resolves in all five shipped locales,
///    with no ARB key falling through to another product's default;
///  * the disclosure lays out without overflow from a narrow phone-sized
///    window up to a desktop one — LintCrux has no phone *layout*, but its
///    window is resizable and a privacy notice that clips its own off switch
///    at 360 dp is the one clipping that matters;
///  * every control clears the 44 dp accessibility floor, on a product whose
///    other chrome sits at 44 dp by convention rather than by enforcement.
// ── harness ──────────────────────────────────────────────────────────────────

/// The delegate set `LintcruxApp` itself installs. The Material / Widgets /
/// Cupertino ones are not optional here: the Settings shell draws an `AppBar`
/// and two `DropdownButton`s, all of which assert on a missing
/// `MaterialLocalizations` in a non-English locale.
const List<LocalizationsDelegate<Object?>> _delegates =
    <LocalizationsDelegate<Object?>>[
      L10N.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A build that *can* transmit: post-beta, so the surfaces mount at all.
  List<Override> surfacesEnabled(TelemetryTestStore store, Locale locale) =>
      <Override>[
        cruxTelemetryConfigProvider.overrideWithValue(lintcruxTelemetryConfig),
        cruxTelemetryStringsProvider.overrideWith(
          (ref) => LintcruxTelemetryStrings(lookupL10N(locale)),
        ),
        telemetryStorageProvider.overrideWithValue(store),
        telemetryBetaPeriodProvider.overrideWithValue(false),
        telemetryDevModeProvider.overrideWithValue(false),
        telemetryUrlLauncherProvider.overrideWithValue((_) async => true),
      ];

  Future<void> pumpDisclosure(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(1280, 900),
    TelemetryTestStore? store,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: surfacesEnabled(store ?? TelemetryTestStore(), locale),
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: _delegates,
          supportedLocales: L10N.supportedLocales,
          home: const TelemetryConsentGate(
            metrics: CruxTelemetryConsentMetrics(
              iconSize: BetaExpiryMetrics.iconSize,
            ),
            child: Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the disclosure renders in every shipped locale', () {
    for (final locale in const <Locale>[
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets(locale.toString(), (tester) async {
        await pumpDisclosure(tester, locale: locale);

        expect(find.byType(TelemetryConsentDisclosure), findsOneWidget);

        final strings = LintcruxTelemetryStrings(lookupL10N(locale));
        // The whole surface, in this locale. The exhaustive lists live on the
        // suite telemetry page now, so what has to be here is the ask, the
        // never-collect claim, and the link that reaches the page — a
        // disclosure showing the ask without the route is an advertisement.
        for (final text in <String>[
          strings.consentTitle,
          strings.consentBody,
          strings.learnMore,
          strings.consentToggleLabel,
          strings.consentContinue,
        ]) {
          expect(
            find.text(text),
            findsOneWidget,
            reason: 'missing on the $locale disclosure: $text',
          );
        }

        // The English default the package falls back to when a product
        // forgets its adapter. Seeing it in a non-English locale means an ARB
        // key did not resolve.
        if (locale.languageCode != 'en') {
          expect(find.text('Help make LintCrux better'), findsNothing);
          expect(find.text('Continue'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('layout constraints', () {
    // LintCrux has no phone layout (it is desktop-only), so the disclosure is
    // always the centred dialog card. These sizes are the window a user can
    // actually drag it to, and the assertion is the same either way: nothing
    // overflows, and the off switch stays on screen.
    for (final entry in const <({String label, Size size})>[
      (label: 'phone-width window', size: Size(360, 640)),
      (label: 'tablet-width window', size: Size(834, 1112)),
      (label: 'desktop window', size: Size(1440, 900)),
      (label: 'short window', size: Size(1024, 400)),
    ]) {
      testWidgets('${entry.label} lays out without overflow', (tester) async {
        await pumpDisclosure(tester, size: entry.size);

        expect(find.byType(TelemetryConsentDisclosure), findsOneWidget);
        // The switch and Continue are pinned below the scrolling lists, so
        // both must be reachable without first reading to the bottom.
        expect(find.byKey(const Key('telemetryConsentSwitch')), findsOneWidget);
        expect(
          find.byKey(const Key('telemetryConsentContinueButton')),
          findsOneWidget,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'a RenderFlex overflow at ${entry.size} would surface here',
        );
      });
    }
  });

  group('44 dp targets', () {
    testWidgets('every disclosure control clears the floor', (tester) async {
      await pumpDisclosure(tester, size: const Size(360, 640));

      for (final key in const <Key>[
        Key('telemetryConsentSwitch'),
        Key('telemetryConsentContinueButton'),
        Key('telemetryConsentLearnMoreButton'),
      ]) {
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(kTelemetryConsentMinTarget),
          reason: '$key is below the 44 dp accessibility floor',
        );
      }
    });

    testWidgets('the floor holds even when the host passes less', (
      tester,
    ) async {
      // `CruxTelemetryConsentMetrics.touchTarget` is a floor, not a default:
      // this is the one screen where the user decides what leaves their
      // machine, and "off" may never be harder to reach than "on".
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: surfacesEnabled(TelemetryTestStore(), const Locale('en')),
          child: const MaterialApp(
            localizationsDelegates: [L10N.delegate],
            supportedLocales: L10N.supportedLocales,
            home: TelemetryConsentGate(
              metrics: CruxTelemetryConsentMetrics(touchTarget: 24),
              child: Scaffold(body: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(find.byKey(const Key('telemetryConsentContinueButton')))
            .height,
        greaterThanOrEqualTo(kTelemetryConsentMinTarget),
      );
    });
  });

  group('the decision round-trips', () {
    testWidgets('Continue with the toggle on stores `enabled`', (tester) async {
      final store = TelemetryTestStore();
      await pumpDisclosure(tester, store: store);

      // Pre-armed on — the suite makes open-core collection default-on with
      // an opt-out, and everything else about the surface is built so that
      // the default is the only thumb on the scale.
      await tester.tap(
        find.byKey(const Key('telemetryConsentContinueButton')),
      );
      await tester.pumpAndSettle();

      expect(store.values[kTelemetryConsentKey], 'enabled');
      expect(find.byType(TelemetryConsentDisclosure), findsNothing);
    });

    testWidgets('flipping the switch off stores `disabled`', (tester) async {
      final store = TelemetryTestStore();
      await pumpDisclosure(tester, store: store);

      await tester.tap(find.byKey(const Key('telemetryConsentSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('telemetryConsentContinueButton')),
      );
      await tester.pumpAndSettle();

      expect(store.values[kTelemetryConsentKey], 'disabled');
    });

    testWidgets('an installation that answered is not asked again', (
      tester,
    ) async {
      final store = TelemetryTestStore(<String, String>{
        kTelemetryConsentKey: TelemetryConsentState.disabled.name,
      });
      await pumpDisclosure(tester, store: store);

      expect(find.byType(TelemetryConsentDisclosure), findsNothing);
    });
  });

  group('Settings → Privacy', () {
    Future<void> pumpSettings(
      WidgetTester tester, {
      required TelemetryTestStore store,
      Locale locale = const Locale('en'),
    }) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: surfacesEnabled(store, locale),
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: _delegates,
            supportedLocales: L10N.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the Privacy category is offered post-beta', (tester) async {
      final store = TelemetryTestStore(<String, String>{
        kTelemetryConsentKey: TelemetryConsentState.enabled.name,
      });
      await pumpSettings(tester, store: store);

      expect(
        find.text(lookupL10N(const Locale('en')).settingsPrivacySection),
        findsOneWidget,
      );
    });

    for (final locale in const <Locale>[
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('the Privacy category is localized in $locale', (
        tester,
      ) async {
        await pumpSettings(tester, store: TelemetryTestStore(), locale: locale);

        expect(
          find.text(lookupL10N(locale).settingsPrivacySection),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the switch reflects and writes the stored decision', (
      tester,
    ) async {
      final store = TelemetryTestStore(<String, String>{
        kTelemetryConsentKey: TelemetryConsentState.enabled.name,
      });
      await pumpSettings(tester, store: store);
      await tester.tap(
        find.text(lookupL10N(const Locale('en')).settingsPrivacySection),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('settingsTelemetrySwitch')));
      await tester.pumpAndSettle();

      // The two surfaces are one setting with two entry points: flipping it
      // here has flipped what the dialog asked about.
      expect(store.values[kTelemetryConsentKey], 'disabled');
    });
  });
}
