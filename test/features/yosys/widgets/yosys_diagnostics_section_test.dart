// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/yosys/widgets/yosys_diagnostics_section.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/yosys/yosys_diagnostics_provider.dart';

/// Seeds [YosysDiagnosticsNotifier] with a fixed snapshot for a widget
/// test — mirrors the `_SeedProjectNotifier extends CurrentProjectNotifier`
/// pattern used throughout this repo's provider-backed widget tests.
class _SeededYosysDiagnosticsNotifier extends YosysDiagnosticsNotifier {
  _SeededYosysDiagnosticsNotifier(this._seed);

  final YosysDiagnosticsState _seed;

  @override
  YosysDiagnosticsState build() => _seed;
}

const _errorDiagnostic = YosysDiagnostic(
  severity: YosysDiagnosticSeverity.error,
  message: 'multiply-driven net',
  filePath: '/proj/a.v',
  line: 10,
  column: 3,
);

const _warningDiagnostic = YosysDiagnostic(
  severity: YosysDiagnosticSeverity.warning,
  message: 'unused wire',
  filePath: '/proj/b.v',
  line: 5,
);

const _infoDiagnostic = YosysDiagnostic(
  severity: YosysDiagnosticSeverity.info,
  message: 'informational note',
);

const _mixedState = YosysDiagnosticsState(
  diagnostics: [_errorDiagnostic, _warningDiagnostic, _infoDiagnostic],
);

void main() {
  Widget harness({
    YosysDiagnosticsState state = const YosysDiagnosticsState(),
    void Function(String filePath, int line)? onJump,
    Locale locale = const Locale('en'),
  }) {
    return ProviderScope(
      overrides: [
        yosysDiagnosticsProvider.overrideWith(
          () => _SeededYosysDiagnosticsNotifier(state),
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
        home: Scaffold(
          body: YosysDiagnosticsSection(onJump: onJump),
        ),
      ),
    );
  }

  L10N l10nOf(WidgetTester tester) =>
      L10N.of(tester.element(find.byType(YosysDiagnosticsSection)));

  group('YosysDiagnosticsSection — empty state', () {
    testWidgets(
      'shows the empty-state message and renders no filter chips or rows '
      'when there are no diagnostics',
      (tester) async {
        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        expect(find.text(l10n.yosysDiagnosticsSectionTitle), findsOneWidget);
        expect(find.text(l10n.yosysDiagnosticsEmpty), findsOneWidget);
        expect(find.byType(FilterChip), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('YosysDiagnosticsSection — populated state', () {
    testWidgets(
      'renders one filter chip per severity and one row per diagnostic, '
      'with the file:line:col citation format for each',
      (tester) async {
        await tester.pumpWidget(harness(state: _mixedState));
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        expect(find.byType(FilterChip), findsNWidgets(3));
        expect(find.text(l10n.yosysDiagnosticsSeverityError), findsOneWidget);
        expect(
          find.text(l10n.yosysDiagnosticsSeverityWarning),
          findsOneWidget,
        );
        expect(find.text(l10n.yosysDiagnosticsSeverityInfo), findsOneWidget);

        expect(find.text('multiply-driven net'), findsOneWidget);
        expect(find.text('/proj/a.v:10:3'), findsOneWidget);
        expect(find.text('unused wire'), findsOneWidget);
        expect(find.text('/proj/b.v:5'), findsOneWidget);
        expect(find.text('informational note'), findsOneWidget);
        expect(find.text('<yosys>'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'selecting the Errors chip narrows the rendered rows to only '
      'error-severity diagnostics, and deselecting restores the full list',
      (tester) async {
        await tester.pumpWidget(harness(state: _mixedState));
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tester.tap(find.text(l10n.yosysDiagnosticsSeverityError));
        await tester.pumpAndSettle();

        expect(find.text('multiply-driven net'), findsOneWidget);
        expect(find.text('unused wire'), findsNothing);
        expect(find.text('informational note'), findsNothing);

        final chip = tester.widget<FilterChip>(
          find.ancestor(
            of: find.text(l10n.yosysDiagnosticsSeverityError),
            matching: find.byType(FilterChip),
          ),
        );
        expect(chip.selected, isTrue);

        // Deselect: "no chips selected" means "show all" again.
        await tester.tap(find.text(l10n.yosysDiagnosticsSeverityError));
        await tester.pumpAndSettle();

        expect(find.text('multiply-driven net'), findsOneWidget);
        expect(find.text('unused wire'), findsOneWidget);
        expect(find.text('informational note'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'selecting both Warnings and Info narrows the list to the union of '
      'the two severities',
      (tester) async {
        await tester.pumpWidget(harness(state: _mixedState));
        await tester.pumpAndSettle();

        final l10n = l10nOf(tester);
        await tester.tap(find.text(l10n.yosysDiagnosticsSeverityWarning));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.yosysDiagnosticsSeverityInfo));
        await tester.pumpAndSettle();

        expect(find.text('multiply-driven net'), findsNothing);
        expect(find.text('unused wire'), findsOneWidget);
        expect(find.text('informational note'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('YosysDiagnosticsSection — onJump wiring', () {
    testWidgets(
      'tapping a row with a file path invokes onJump with the file path '
      'and 1-indexed line',
      (tester) async {
        final calls = <(String, int)>[];
        await tester.pumpWidget(
          harness(
            state: _mixedState,
            onJump: (filePath, line) => calls.add((filePath, line)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('multiply-driven net'));
        await tester.pumpAndSettle();

        expect(calls, [('/proj/a.v', 10)]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping a row with no file path does not invoke onJump — the row '
      'has no tap handler when it cannot jump anywhere',
      (tester) async {
        final calls = <(String, int)>[];
        await tester.pumpWidget(
          harness(
            state: _mixedState,
            onJump: (filePath, line) => calls.add((filePath, line)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('informational note'));
        await tester.pumpAndSettle();

        expect(calls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'when onJump is null, rows render as static text without throwing '
      'on tap',
      (tester) async {
        await tester.pumpWidget(harness(state: _mixedState));
        await tester.pumpAndSettle();

        await tester.tap(find.text('multiply-driven net'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('YosysDiagnosticsSection — locale sweep', () {
    testWidgets(
      'renders the populated state without exceptions in every supported '
      'locale',
      (tester) async {
        for (final locale in L10N.supportedLocales) {
          await tester.pumpWidget(harness(state: _mixedState, locale: locale));
          await tester.pumpAndSettle();
          final l10n = l10nOf(tester);
          expect(
            find.text(l10n.yosysDiagnosticsSectionTitle),
            findsOneWidget,
            reason: 'section title missing for $locale',
          );
          expect(
            find.text('multiply-driven net'),
            findsOneWidget,
            reason: 'diagnostic message missing for $locale',
          );
          expect(tester.takeException(), isNull, reason: 'failed for $locale');
        }
      },
    );
  });
}
