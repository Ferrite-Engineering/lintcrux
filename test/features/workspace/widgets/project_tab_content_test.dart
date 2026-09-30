// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/auto_reload/widgets/auto_reload_host.dart';
import 'package:lintcrux/features/project/providers/config_load_error_provider.dart';
import 'package:lintcrux/features/remote/providers/violation_selection_emitter.dart';
import 'package:lintcrux/features/workspace/widgets/project_tab_content.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

void main() {
  // The four-pane IdeLayout has ~300 dp of min side / bottom panes
  // plus a center pane. Tests need a desktop-sized surface to avoid
  // RenderFlex overflow.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(
      1600,
      1000,
    );
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('ProjectTabContent renders without exception at desktop size', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(body: ProjectTabContent()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ProjectTabContent), findsOneWidget);
  });

  testWidgets(
    'mounting a project tab realizes its selection broadcast and '
    'auto-reload host',
    (tester) async {
      var emitterBuilt = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            violationSelectionEmitterProvider.overrideWith((ref) {
              emitterBuilt++;
              return ViolationSelectionEmitter(ref);
            }),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: ProjectTabContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(emitterBuilt, 1);
      expect(find.byType(AutoReloadHost), findsOneWidget);
    },
  );

  testWidgets('ProjectTabContent locale sweep renders without exception', (
    tester,
  ) async {
    for (final locale in L10N.supportedLocales) {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: const [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: const Scaffold(body: ProjectTabContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Assert a locale-resolved string actually renders (a sweep that
      // only checks takeException passes silently on missing wiring);
      // the Rules dock tab is the stable localized marker in the layout.
      final l10n = L10N.of(tester.element(find.byType(ProjectTabContent)));
      // findsWidgets, not findsOneWidget: some locales (ja) collapse
      // this string with another panel label.
      expect(
        find.text(l10n.dockTabRules),
        findsWidgets,
        reason: 'Rules dock tab title missing for $locale',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'failed for $locale',
      );
    }
  });

  group('ProjectTabContent — project-load error empty state', () {
    testWidgets(
      'renders the error view instead of the IDE layout when '
      'configLoadErrorProvider is set, with the path and reason shown '
      'verbatim',
      (tester) async {
        const error = ConfigLoadError(
          path: '/tmp/broken.lintcrux',
          reason: 'No such file or directory',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              configLoadErrorProvider.overrideWith(() {
                return _SeededConfigLoadErrorNotifier(error);
              }),
            ],
            child: const MaterialApp(
              localizationsDelegates: [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: ProjectTabContent()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final l10n = L10N.of(tester.element(find.byType(ProjectTabContent)));
        expect(find.text(l10n.configLoadFailedTitle), findsOneWidget);
        expect(find.text(l10n.configLoadFailedPathLabel), findsOneWidget);
        expect(find.text('/tmp/broken.lintcrux'), findsOneWidget);
        expect(find.text(l10n.configLoadFailedReasonLabel), findsOneWidget);
        expect(find.text('No such file or directory'), findsOneWidget);
        expect(find.text(l10n.configLoadFailedHint), findsOneWidget);
        // The IDE layout must not be rendered alongside the error view.
        expect(find.byType(Scrollbar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'the error empty state locale sweep renders the path/reason and '
      'localized chrome without exception',
      (tester) async {
        const error = ConfigLoadError(
          path: '/proj/team.lintcrux',
          reason: 'Permission denied',
        );
        for (final locale in L10N.supportedLocales) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                configLoadErrorProvider.overrideWith(() {
                  return _SeededConfigLoadErrorNotifier(error);
                }),
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
                home: const Scaffold(body: ProjectTabContent()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = L10N.of(tester.element(find.byType(ProjectTabContent)));
          expect(
            find.text(l10n.configLoadFailedTitle),
            findsOneWidget,
            reason: 'error title missing for $locale',
          );
          expect(find.text('/proj/team.lintcrux'), findsOneWidget);
          expect(find.text('Permission denied'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: 'failed for $locale',
          );
        }
      },
    );
  });
}

/// Seeds [ConfigLoadErrorNotifier] with a fixed error for a widget test —
/// mirrors the `_SeedProjectNotifier extends CurrentProjectNotifier`
/// pattern used throughout this repo's provider-backed widget tests.
class _SeededConfigLoadErrorNotifier extends ConfigLoadErrorNotifier {
  _SeededConfigLoadErrorNotifier(this._seed);

  final ConfigLoadError _seed;

  @override
  ConfigLoadError? build() => _seed;
}
