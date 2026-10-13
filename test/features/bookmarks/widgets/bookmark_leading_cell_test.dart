// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/bookmarks/widgets/bookmark_leading_cell.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/violation_row_leading_cells_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

import '../../../support/telemetry_test_store.dart';

/// A leading cell an overlay contributes after the bookmark column.
final ViolationRowLeadingCell _overlayCell = ViolationRowLeadingCell(
  id: 'overlay.extra',
  width: 24,
  bodyBuilder: (_, _, _) => const SizedBox.shrink(),
  headerBuilder: (_, _) => const SizedBox.shrink(),
);

/// Mounts a header row of [watchViolationLeadingCells] under [container]
/// and returns the ids it rendered, in order.
Future<List<String>> _pumpCells(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) async {
  var ids = <String>[];
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
          body: Consumer(
            builder: (context, ref, _) {
              final cells = watchViolationLeadingCells(ref);
              ids = [for (final c in cells) c.id];
              return Row(
                children: [
                  for (final c in cells)
                    SizedBox(
                      width: c.width,
                      child: c.headerBuilder(context, ref),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return ids;
}

ProviderContainer _container({bool withOverlayCell = false}) {
  final container = ProviderContainer(
    overrides: [
      ...telemetryDeclinedOverrides(),
      if (withOverlayCell)
        violationRowLeadingCellsProvider.overrideWithValue([_overlayCell]),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('kBookmarkLeadingCell', () {
    test('is the 32 dp bookmark column', () {
      expect(kBookmarkLeadingCell.id, 'bookmark');
      expect(kBookmarkLeadingCell.width, 32);
    });

    testWidgets('its header is a tooltip-anchored bookmark icon', (
      tester,
    ) async {
      final container = _container();
      container
          .read(currentProjectProvider.notifier)
          .load(const LintProject(name: 'p', rootPath: '/r'));
      await _pumpCells(tester, container);
      expect(find.byIcon(Icons.bookmark_outline), findsOneWidget);
      expect(
        find.byTooltip(
          L10N.of(tester.element(find.byType(Row))).bookmarkColumnHeaderTooltip,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('watchViolationLeadingCells', () {
    testWidgets('no project: no bookmark column', (tester) async {
      final ids = await _pumpCells(tester, _container());
      expect(ids, isEmpty);
    });

    testWidgets('a project with an empty root: no bookmark column', (
      tester,
    ) async {
      final container = _container();
      container
          .read(currentProjectProvider.notifier)
          .load(const LintProject(name: 'p', rootPath: ''));
      final ids = await _pumpCells(tester, container);
      expect(ids, isEmpty);
    });

    testWidgets('a project with a root: the bookmark column', (tester) async {
      final container = _container();
      container
          .read(currentProjectProvider.notifier)
          .load(const LintProject(name: 'p', rootPath: '/r'));
      final ids = await _pumpCells(tester, container);
      expect(ids, ['bookmark']);
    });

    testWidgets('overlay contributions follow the bookmark column', (
      tester,
    ) async {
      final container = _container(withOverlayCell: true);
      container
          .read(currentProjectProvider.notifier)
          .load(const LintProject(name: 'p', rootPath: '/r'));
      final ids = await _pumpCells(tester, container);
      expect(ids, ['bookmark', 'overlay.extra']);
    });

    testWidgets('overlay contributions stay when there is no project', (
      tester,
    ) async {
      final ids = await _pumpCells(
        tester,
        _container(withOverlayCell: true),
      );
      expect(ids, ['overlay.extra']);
    });

    testWidgets('the column follows the project opening and closing', (
      tester,
    ) async {
      final container = _container();
      expect(await _pumpCells(tester, container), isEmpty);
      container
          .read(currentProjectProvider.notifier)
          .load(const LintProject(name: 'p', rootPath: '/r'));
      expect(await _pumpCells(tester, container), ['bookmark']);
      container.read(currentProjectProvider.notifier).clear();
      expect(await _pumpCells(tester, container), isEmpty);
    });

    group('locale sweep', () {
      for (final loc in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('header renders without exception in ${loc.languageCode}', (
          tester,
        ) async {
          final container = _container();
          container
              .read(currentProjectProvider.notifier)
              .load(const LintProject(name: 'p', rootPath: '/r'));
          await _pumpCells(tester, container, locale: loc);
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
