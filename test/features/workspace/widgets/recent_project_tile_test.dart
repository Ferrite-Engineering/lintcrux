// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/workspace/widgets/recent_project_tile.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool exists,
  Locale locale = const Locale('en'),
  VoidCallback? onOpen,
  VoidCallback? onRemove,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: RecentProjectTile(
          path: '/p/a.lintcrux',
          exists: exists,
          onOpen: onOpen ?? () {},
          onRemove: onRemove ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping the row opens; the trailing button removes', (
    tester,
  ) async {
    var opens = 0;
    var removes = 0;
    await _pump(
      tester,
      exists: true,
      onOpen: () => opens++,
      onRemove: () => removes++,
    );
    await tester.tap(find.text('/p/a.lintcrux'));
    await tester.tap(find.byTooltip('Remove from Recent Projects'));
    await tester.pump();
    expect(opens, 1);
    expect(removes, 1);
    expect(find.text('Project file not found'), findsNothing);
  });

  testWidgets('a missing project file is greyed and named as missing', (
    tester,
  ) async {
    await _pump(tester, exists: false);
    expect(find.text('Project file not found'), findsOneWidget);
    expect(find.byIcon(Icons.folder_off_outlined), findsOneWidget);
    final context = tester.element(find.byType(RecentProjectTile));
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final title = tester.widget<Text>(find.text('/p/a.lintcrux'));
    expect(title.style?.color, muted);
  });

  testWidgets('the remove button has one accessible name', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, exists: true);
    final node = tester.getSemantics(find.byType(IconButton));
    expect(node.tooltip, 'Remove from Recent Projects');
    expect(node.label, isEmpty);
    handle.dispose();
  });

  testWidgets('locale sweep', (tester) async {
    for (final locale in L10N.supportedLocales) {
      await _pump(tester, exists: false, locale: locale);
      final l10n = L10N.of(tester.element(find.byType(RecentProjectTile)));
      expect(find.text(l10n.emptyCanvasRecentProjectMissing), findsOneWidget);
      expect(find.byTooltip(l10n.emptyCanvasRemoveRecentProject), findsOne);
      expect(tester.takeException(), isNull, reason: '$locale');
    }
  });
}
