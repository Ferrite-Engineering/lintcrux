// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/inspector/widgets/inspector_pane.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_row.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// A layout check from an imported LibreLane report names no source file. The
/// table, the screen-reader label and the inspector show it with its rule id
/// and tool and say plainly that there is no source location; none of them
/// shows the importer's placeholder as "line 1".
const _fixture =
    'verification/fixtures/sarif/flow/librelane/sky130A_drc.sarif.json';

Future<Violation> _magicDrc() async {
  final store = InMemoryViolationStore();
  final loader = SarifFileLoader();
  try {
    final report = await loader.loadFromString(
      File(_fixture).readAsStringSync(),
      store: store,
    );
    return report.runs.single.violations.singleWhere(
      (v) =>
          (v.raw['properties']! as Map)['metric'] == 'magic__drc_error__count',
    );
  } finally {
    loader.dispose();
    await store.dispose();
  }
}

Widget _host(Violation v, Widget child, {Locale? locale}) {
  final store = InMemoryViolationStore()..replaceFromEngine(v.engineId, [v]);
  addTearDown(store.dispose);
  return ProviderScope(
    overrides: [violationStoreProvider.overrideWithValue(store)],
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
        body: SizedBox(width: 900, child: child),
      ),
    ),
  );
}

void main() {
  // Read outside the widget tests' fake-async zone, where file I/O never
  // completes.
  late Violation magic;
  setUpAll(() async => magic = await _magicDrc());

  testWidgets('the table row shows rule id, tool and no source location', (
    tester,
  ) async {
    final v = magic;
    await tester.pumpWidget(_host(v, ViolationTableRow(violation: v)));
    await tester.pumpAndSettle();
    final l10n = await L10N.delegate.load(const Locale('en'));

    expect(find.text('flow/drc'), findsOneWidget);
    expect(find.text('edacrux flow'), findsOneWidget);
    expect(find.text(l10n.violationNoSourceLocation), findsOneWidget);
    expect(
      find.text('LibreLane reports Magic design rule violations in this run.'),
      findsOneWidget,
    );
    // The placeholder line is not shown as a place in a file.
    expect(find.text('1'), findsNothing);
  });

  testWidgets('the row is read with no file and no line', (tester) async {
    final handle = tester.ensureSemantics();
    final v = magic;
    await tester.pumpWidget(_host(v, ViolationTableRow(violation: v)));
    await tester.pumpAndSettle();
    final l10n = await L10N.delegate.load(const Locale('en'));
    final expected = l10n.accessibilityViolationRowNoLocation(
      'Warning',
      'flow/drc',
      'LibreLane reports Magic design rule violations in this run.',
    );
    expect(expected, isNot(contains('line')));
    expect(find.bySemanticsLabel(expected), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Enter on it opens nothing', (tester) async {
    final v = magic;
    await tester.pumpWidget(_host(v, ViolationTableRow(violation: v)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    // No launch failure snackbar: the editor was never asked.
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in L10N.supportedLocales) {
    testWidgets('row and Details pane render in $locale without exceptions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final l10n = await L10N.delegate.load(locale);
      final v = magic;
      await tester.pumpWidget(
        _host(v, ViolationTableRow(violation: v), locale: locale),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.violationNoSourceLocation), findsOneWidget);
      expect(find.text('flow/drc'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_host(v, const InspectorPane(), locale: locale));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InspectorPane)),
      );
      container.read(selectedViolationProvider.notifier).select(v);
      await tester.pump();
      expect(find.text(l10n.violationNoSourceLocation), findsOneWidget);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  }

  testWidgets('the inspector says there is no source location', (tester) async {
    final v = magic;
    await tester.pumpWidget(_host(v, const InspectorPane()));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(InspectorPane)),
    );
    container.read(selectedViolationProvider.notifier).select(v);
    await tester.pump();
    final l10n = L10N.of(tester.element(find.byType(InspectorPane)));

    expect(find.text(l10n.inspectorLocationHeader), findsOneWidget);
    expect(find.text(l10n.violationNoSourceLocation), findsOneWidget);
    expect(find.text(':1:1'), findsNothing);
    expect(find.text(l10n.inspectorOpenInEditor), findsNothing);
    expect(find.textContaining('flow/drc'), findsWidgets);
    expect(v.severity, Severity.warning);
  });
}
