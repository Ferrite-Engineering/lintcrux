// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_project/crux_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/project/services/open_project_feedback.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

const _project = LintProject(name: 'uart', rootPath: '/work/uart');

final _ambiguous = OpenProjectManifestAmbiguous(
  const CruxProjectAmbiguousException(
    directory: '/work/uart',
    candidates: <String>[
      '/work/uart/.crux-project',
      '/work/uart/uart.crux-project',
    ],
  ),
);

void main() {
  /// Pumps a scaffold, shows [result]'s outcome, and returns the L10N the
  /// outcome was rendered with.
  Future<L10N> show(
    WidgetTester tester,
    OpenProjectResult result, {
    Locale locale = const Locale('en'),
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    showOpenProjectOutcome(captured, result);
    await tester.pump();
    return L10N.of(captured);
  }

  for (final locale in L10N.supportedLocales) {
    testWidgets('a legacy manifest name asks for the rename ($locale)', (
      tester,
    ) async {
      final l10n = await show(
        tester,
        const OpenProjectSuccess(
          _project,
          legacyManifestRenameTo: 'uart.crux-project',
        ),
        locale: locale,
      );
      final expected = l10n.openProjectLegacyManifestName('uart.crux-project');
      expect(expected, contains('uart.crux-project'));
      expect(expected, contains('.crux-project'));
      expect(find.text(expected), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a folder holding two manifests is explained ($locale)', (
      tester,
    ) async {
      final l10n = await show(tester, _ambiguous, locale: locale);
      final expected = l10n.openProjectAmbiguousManifests(
        '/work/uart',
        '.crux-project, uart.crux-project',
      );
      expect(find.text(expected), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('any other failure shows its own message', (tester) async {
    await show(tester, const OpenProjectFailure('could not read project'));
    expect(find.text('could not read project'), findsOneWidget);
  });

  testWidgets('a plain success shows nothing', (tester) async {
    await show(tester, const OpenProjectSuccess(_project));
    expect(find.byType(SnackBar), findsNothing);
  });

  test('the ambiguity text names every manifest by file name', () {
    final l10n = lookupL10N(const Locale('en'));
    final text = openProjectFailureText(l10n, _ambiguous);
    expect(text, contains('/work/uart'));
    expect(text, contains('.crux-project, uart.crux-project'));
    expect(text, isNot(contains('/work/uart/uart.crux-project')));
  });
}
