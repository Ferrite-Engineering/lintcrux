// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/widgets/settings_remote_control_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

class _SeedNotifier extends AppSettingsNotifier {
  _SeedNotifier(this._seed);

  final AppSettings _seed;

  @override
  AppSettings build() => _seed;
}

Widget _wrap({
  required AppSettings seed,
  Locale locale = const Locale('en'),
  List<Override> extra = const [],
}) {
  return ProviderScope(
    overrides: [
      appSettingsProvider.overrideWith(() => _SeedNotifier(seed)),
      ...extra,
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(body: SettingsRemoteControlSection()),
    ),
  );
}

void main() {
  group('SettingsRemoteControlSection', () {
    testWidgets('renders the enabled switch and port field', (tester) async {
      await tester.pumpWidget(_wrap(seed: const AppSettings()));
      await tester.pumpAndSettle();
      // Three switches: the CXP-enabled toggle, the request-attention
      // toggle, and the broadcast-selection toggle.
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(find.byType(TextField), findsOneWidget);
      // Port defaults to 54324.
      expect(find.text('54324'), findsOneWidget);
    });

    testWidgets('toggling the switch updates appSettingsProvider', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(
              () => _SeedNotifier(const AppSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(body: SettingsRemoteControlSection());
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Toggle the CXP-enabled switch (the first one) off.
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingsProvider).cxpServerEnabled,
        isFalse,
      );
    });

    testWidgets('toggling the attention switch updates appSettingsProvider', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(
              () => _SeedNotifier(const AppSettings()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(body: SettingsRemoteControlSection());
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // The request-attention switch is the second (defaults on).
      expect(
        container.read(appSettingsProvider).requestAttentionOnCrossProbe,
        isTrue,
      );
      await tester.tap(find.byType(SwitchListTile).at(1));
      await tester.pumpAndSettle();
      expect(
        container.read(appSettingsProvider).requestAttentionOnCrossProbe,
        isFalse,
      );
    });

    testWidgets(
      'toggling the broadcast-selection switch updates appSettingsProvider',
      (tester) async {
        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appSettingsProvider.overrideWith(
                () => _SeedNotifier(const AppSettings()),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: const [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(body: SettingsRemoteControlSection());
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // The broadcast-selection switch is the third (defaults on).
        expect(
          container.read(appSettingsProvider).broadcastSelectionOnCrossProbe,
          isTrue,
        );
        await tester.tap(find.byType(SwitchListTile).last);
        await tester.pumpAndSettle();
        expect(
          container.read(appSettingsProvider).broadcastSelectionOnCrossProbe,
          isFalse,
        );
      },
    );

    testWidgets('disables the port field when the switch is off', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          seed: const AppSettings(cxpServerEnabled: false),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(
            seed: const AppSettings(),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'lays out Enable → Port → Request-attention → Broadcast-selection → '
      'CXP Status top-to-bottom (WaveCrux canonical order)',
      (tester) async {
        await tester.pumpWidget(_wrap(seed: const AppSettings()));
        await tester.pumpAndSettle();

        final enableDy = tester.getTopLeft(find.text('Enable CXP server')).dy;
        final portDy = tester.getTopLeft(find.byType(TextField)).dy;
        final attentionDy = tester
            .getTopLeft(find.text('Request attention on cross-probe'))
            .dy;
        final broadcastDy = tester
            .getTopLeft(find.text('Broadcast selection automatically'))
            .dy;
        // The CXP Status line closes the section.
        final statusDy = tester.getTopLeft(find.text('CXP Status')).dy;

        expect(enableDy, lessThan(portDy));
        expect(portDy, lessThan(attentionDy));
        expect(attentionDy, lessThan(broadcastDy));
        expect(broadcastDy, lessThan(statusDy));
      },
    );

    testWidgets('CXP Status shows "Stopped" when the server is not running', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(seed: const AppSettings()));
      await tester.pumpAndSettle();
      expect(find.text('CXP Status'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
    });
  });
}
