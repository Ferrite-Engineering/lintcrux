// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_row.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/violation_context_menu_provider.dart';

/// A strip above the app's navigator (as the licence-expiry strip is), and a
/// toolbar above the content, inside a nested navigator like the one each file
/// tab has: the nested overlay's origin is not the root overlay's.
const double _strip = 30;
const double _toolbar = 55;

const _violation = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/WIDTH',
  severity: Severity.warning,
  message: 'width mismatch',
  location: SourceLocation(file: '/x/y.sv', line: 3, column: 1),
);

void main() {
  testWidgets('the violation menu opens at the click inside a tab navigator', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          violationContextMenuEntriesProvider.overrideWithValue(
            <ViolationContextMenuEntry>[
              ViolationContextMenuEntry(
                id: 'test.core',
                labelBuilder: (_) => 'Copy rule id',
                onActivate: (_, _, _) {},
              ),
            ],
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
          builder: (context, navigator) => Column(
            children: <Widget>[
              const SizedBox(height: _strip),
              Expanded(child: navigator!),
            ],
          ),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(height: _toolbar),
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 800,
                          child: ViolationTableRow(violation: _violation),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Sanity: the nested overlay really is offset from the root overlay, or
    // this test could not fail.
    final nested = tester.getTopLeft(find.byType(Overlay).last);
    final root = tester.getTopLeft(find.byType(Overlay).first);
    expect(nested.dy - root.dy, _toolbar);

    final row = tester.getTopLeft(find.byType(ViolationTableRow));
    final click = row + const Offset(300, 10);
    await tester.tapAt(click, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    final firstItem = tester.getTopLeft(
      find.byType(PopupMenuItem<String>).first,
    );
    // The menu's own vertical padding sits above its first item.
    const menuPadding = 8.0;
    expect(firstItem.dx, closeTo(click.dx, 2));
    expect(firstItem.dy - menuPadding, closeTo(click.dy, 2));
  });
}
