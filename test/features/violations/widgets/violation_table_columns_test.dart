// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/violation_column_layout.dart';
import 'package:lintcrux/features/violations/providers/violation_column_layout_provider.dart';
import 'package:lintcrux/features/violations/widgets/violation_table.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_row.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/persistence/violation_column_layout_codec.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/telemetry_test_store.dart';

const _file = '/work/soc/rtl/alu.sv';

Violation _v(String rule) => Violation(
  engineId: 'verilator',
  ruleId: 'verilator/$rule',
  severity: Severity.warning,
  message: 'msg $rule',
  location: const SourceLocation(file: _file, line: 24, column: 1),
);

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> pumpTable(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = InMemoryViolationStore()
      ..replaceFromEngine('verilator', [_v('UNUSEDSIGNAL')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...telemetryDeclinedOverrides(),
          violationStoreProvider.overrideWithValue(store),
          violationColumnLayoutSettingsServiceProvider.overrideWithValue(
            SettingsService<ViolationColumnLayout>(
              const ViolationColumnLayoutCodec(),
              prefsOverride: prefs,
            ),
          ),
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
          home: const Scaffold(body: ViolationTable()),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ViolationTable)),
    );
    container
        .read(currentProjectProvider.notifier)
        .load(const LintProject(name: 'soc', rootPath: '/work/soc'));
    await tester.pumpAndSettle();
    return container;
  }

  /// Left edge of the File header and of the File cell's text in the row.
  (double, double) fileColumnLeft(WidgetTester tester) => (
    tester
        .getTopLeft(find.byKey(const ValueKey('violationTableHeader-file')))
        .dx,
    tester.getTopLeft(find.text('rtl/alu.sv')).dx,
  );

  testWidgets('the File column shows the path inside the project, the '
      'tooltip the full path', (tester) async {
    await pumpTable(tester);
    expect(find.text('rtl/alu.sv'), findsOneWidget);
    expect(find.text(_file), findsNothing);
    expect(find.byTooltip(_file), findsOneWidget);
  });

  testWidgets('a truncatable rule ID carries its full value as a tooltip', (
    tester,
  ) async {
    await pumpTable(tester);
    expect(find.byTooltip('verilator/UNUSEDSIGNAL'), findsOneWidget);
    expect(find.byTooltip('verilator'), findsOneWidget);
  });

  testWidgets('dragging a divider moves the column in the header and the '
      'rows together, and saves when the drag ends', (tester) async {
    await pumpTable(tester);
    final (headerBefore, rowBefore) = fileColumnLeft(tester);

    await tester.drag(
      find.byKey(const ValueKey('violationTableResize-rule')),
      const Offset(80, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    final (headerAfter, rowAfter) = fileColumnLeft(tester);
    expect(headerAfter - headerBefore, closeTo(80, 2));
    expect(rowAfter - rowBefore, closeTo(80, 2));

    expect(
      await const ViolationColumnLayoutCodec().load(prefs),
      isNot(ViolationColumnLayout.defaults),
    );
  });

  testWidgets('double-clicking a divider restores the default widths', (
    tester,
  ) async {
    final container = await pumpTable(tester);
    await tester.drag(
      find.byKey(const ValueKey('violationTableResize-rule')),
      const Offset(80, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(
      container.read(violationColumnLayoutProvider),
      isNot(ViolationColumnLayout.defaults),
    );

    final handle = find.byKey(const ValueKey('violationTableResize-file'));
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(
      container.read(violationColumnLayoutProvider),
      ViolationColumnLayout.defaults,
    );
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('locale ${locale.toLanguageTag()}: the dividers and the '
        'relative path render', (tester) async {
      await pumpTable(tester, locale: locale);
      expect(
        find.byKey(const ValueKey('violationTableResize-rule')),
        findsOneWidget,
      );
      expect(find.text('rtl/alu.sv'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('displayPath leaves a file outside the project absolute', () {
    expect(displayPath('/elsewhere/x.sv', '/work/soc'), '/elsewhere/x.sv');
    expect(displayPath('/work/soc/a.sv', null), '/work/soc/a.sv');
    expect(displayPath('/work/soc/a.sv', '/work/soc'), 'a.sv');
  });
}
