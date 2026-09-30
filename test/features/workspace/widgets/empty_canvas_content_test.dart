// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/app_info/about_providers.dart';
import 'package:lintcrux/features/workspace/providers/recent_projects_provider.dart';
import 'package:lintcrux/features/workspace/widgets/empty_canvas_content.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Fixed build metadata for the version-line test, so the assertion does not
/// track the real `pubspec.yaml` version.
const _testBuildInfo = ApplicationBuildInfo(
  version: '9.9.9',
  buildNumber: '7',
  gitShortSha: 'abc1234',
  os: 'macos',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.8',
  dartSdkVersion: '3.12.2',
);

void main() {
  Future<void> pumpContent(
    WidgetTester tester, {
    required Locale locale,
    required List<VoidCallback> callbacks,
    List<String> recentProjects = const <String>[],
    void Function(String path)? onOpenRecent,
    ApplicationBuildInfo? buildInfo,
  }) async {
    final [openProject, openSession, openWorkspace, newProject] = callbacks;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recentProjectsProvider.overrideWithValue(recentProjects),
          if (buildInfo != null)
            aboutBuildInfoProvider.overrideWith((ref) async => buildInfo),
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
          home: Scaffold(
            body: EmptyCanvasContent(
              onOpenProject: openProject,
              onOpenSession: openSession,
              onOpenWorkspace: openWorkspace,
              onNewProject: newProject,
              onOpenRecentProject: onOpenRecent ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders title, subtitle, and primary actions', (tester) async {
    final hits = <String>[];
    await pumpContent(
      tester,
      locale: const Locale('en'),
      callbacks: [
        () => hits.add('open'),
        () => hits.add('session'),
        () => hits.add('workspace'),
        () => hits.add('new'),
      ],
    );
    expect(find.text('Welcome to LintCrux'), findsOneWidget);
    expect(find.text('Open Project…'), findsOneWidget);
    expect(find.text('Open Workspace…'), findsOneWidget);
    expect(find.text('Open Session…'), findsOneWidget);
    expect(find.text('New Project…'), findsOneWidget);
  });

  testWidgets('renders the version line under the subtitle', (tester) async {
    await pumpContent(
      tester,
      locale: const Locale('en'),
      callbacks: [() {}, () {}, () {}, () {}],
      buildInfo: _testBuildInfo,
    );
    // The override resolves asynchronously; one pump lands the value.
    await tester.pump();

    final versionText = find.byKey(const Key('empty_canvas_version'));
    expect(versionText, findsOneWidget);
    expect(tester.widget<Text>(versionText).data, 'Version 9.9.9');
  });

  testWidgets('omits the version line until build info resolves', (
    tester,
  ) async {
    // No aboutBuildInfoProvider override: the real provider is async, so on
    // the first frame `.value` is null and nothing should render.
    await pumpContent(
      tester,
      locale: const Locale('en'),
      callbacks: [() {}, () {}, () {}, () {}],
    );
    expect(find.byKey(const Key('empty_canvas_version')), findsNothing);
  });

  testWidgets(
    'Import SARIF button is hidden without a callback and fires it when set',
    (tester) async {
      // Default (no onImportSarif) — the button is absent.
      await pumpContent(
        tester,
        locale: const Locale('en'),
        callbacks: [() {}, () {}, () {}, () {}],
      );
      expect(find.text('Import SARIF report…'), findsNothing);

      // With a callback supplied, the button renders and fires.
      var imports = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentProjectsProvider.overrideWithValue(const <String>[]),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              L10N.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: EmptyCanvasContent(
                onOpenProject: () {},
                onOpenSession: () {},
                onOpenWorkspace: () {},
                onNewProject: () {},
                onOpenRecentProject: (_) {},
                onImportSarif: () => imports++,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Import SARIF report…'), findsOneWidget);
      // The glowing-logo header pushes the action row below the fold in the
      // test viewport; bring the button on screen before tapping.
      await tester.ensureVisible(find.text('Import SARIF report…'));
      await tester.pump();
      await tester.tap(find.text('Import SARIF report…'));
      await tester.pump();
      expect(imports, 1);
    },
  );

  testWidgets('Open Project button fires the onOpenProject callback', (
    tester,
  ) async {
    var openTaps = 0;
    await pumpContent(
      tester,
      locale: const Locale('en'),
      callbacks: [() => openTaps++, () {}, () {}, () {}],
    );
    await tester.tap(find.text('Open Project…'));
    await tester.pump();
    expect(openTaps, 1);
  });

  testWidgets('empty recent-projects section shows the placeholder', (
    tester,
  ) async {
    await pumpContent(
      tester,
      locale: const Locale('en'),
      callbacks: [() {}, () {}, () {}, () {}],
    );
    expect(find.text('No recent projects yet.'), findsOneWidget);
  });

  testWidgets('populated recent-projects shows tappable rows', (tester) async {
    var tapped = '';
    await pumpContent(
      tester,
      locale: const Locale('en'),
      callbacks: [() {}, () {}, () {}, () {}],
      recentProjects: const ['/p/a.lintcrux', '/p/b.lintcrux'],
      onOpenRecent: (path) => tapped = path,
    );
    expect(find.text('/p/a.lintcrux'), findsOneWidget);
    expect(find.text('/p/b.lintcrux'), findsOneWidget);
    expect(find.text('No recent projects yet.'), findsNothing);
    await tester.tap(find.text('/p/a.lintcrux'));
    await tester.pump();
    expect(tapped, '/p/a.lintcrux');
  });

  testWidgets('locale sweep: renders the localized chrome for every supported '
      'locale', (tester) async {
    for (final locale in L10N.supportedLocales) {
      await pumpContent(
        tester,
        locale: locale,
        callbacks: [() {}, () {}, () {}, () {}],
      );
      // Assert the locale-resolved strings actually render (a sweep that
      // only checks takeException passes silently on missing wiring).
      final l10n = L10N.of(tester.element(find.byType(EmptyCanvasContent)));
      expect(
        find.text(l10n.emptyCanvasTitle),
        findsOneWidget,
        reason: 'title missing for $locale',
      );
      expect(
        find.text(l10n.emptyCanvasOpenProjectButton),
        findsOneWidget,
        reason: 'open-project button missing for $locale',
      );
      expect(
        find.text(l10n.emptyCanvasOpenWorkspaceButton),
        findsOneWidget,
        reason: 'open-workspace button missing for $locale',
      );
      expect(
        find.text(l10n.emptyCanvasOpenSessionButton),
        findsOneWidget,
        reason: 'open-session button missing for $locale',
      );
      expect(
        find.text(l10n.emptyCanvasNewProjectButton),
        findsOneWidget,
        reason: 'new-project button missing for $locale',
      );
      expect(
        find.text(l10n.emptyCanvasNoRecentProjects),
        findsOneWidget,
        reason: 'recent-projects placeholder missing for $locale',
      );
      expect(tester.takeException(), isNull, reason: 'failed for $locale');
    }
  });
}
