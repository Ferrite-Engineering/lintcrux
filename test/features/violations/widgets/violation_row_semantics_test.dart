// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/violations/widgets/violation_table_row.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// What a screen reader actually hears from the violation table.
///
/// A suite accessibility audit named this shape directly:
/// "a label that is technically present and useless". A table row here is five
/// separate `Text` cells, and a screen reader announces five disconnected
/// fragments with no column context — `verible`, `line-length`, `top.sv`,
/// `42`, `Line too long`. Every fragment is labelled. The row is unusable.
///
/// So the assertion is not "the row has semantics" — it had those all along.
/// It is that the row produces **one** announcement, that the announcement
/// contains the facts a user needs to act, and that the fragments are gone.
void main() {
  Violation violation() => const Violation(
    engineId: 'verible',
    ruleId: 'line-length',
    severity: Severity.warning,
    message: 'Line too long (95 > 80)',
    location: SourceLocation(file: 'rtl/top.sv', line: 42, column: 1),
  );

  Widget host(Widget child, {Locale? locale}) => ProviderScope(
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: child),
    ),
  );

  testWidgets(
    'a row is one announcement carrying rule, file, line and message',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(ViolationTableRow(violation: violation())));
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      final expected = l10n.accessibilityViolationRow(
        'Warning',
        'line-length',
        'rtl/top.sv',
        42,
        'Line too long (95 > 80)',
      );

      expect(
        find.bySemanticsLabel(expected),
        findsOneWidget,
        reason:
            'The row should announce itself as a single sentence. If this fails '
            "with the label absent, check that the row's check box still "
            'carries it as its semanticLabel (the check box is the Tab stop, '
            'so that is where a screen reader hears it); if it fails with the '
            'label present but duplicated, the sentence has been put back on '
            'a second node as well.',
      );

      handle.dispose();
    },
  );

  testWidgets('the individual cells no longer announce themselves', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(ViolationTableRow(violation: violation())));
    await tester.pumpAndSettle();

    // These are the fragments a reader used to hear one at a time. They are
    // still drawn — this asserts what is announced, not what is visible, and
    // the finder below is a semantics finder for exactly that reason.
    for (final fragment in const ['verible', 'line-length', '42']) {
      expect(
        find.bySemanticsLabel(fragment),
        findsNothing,
        reason:
            '"$fragment" is announced on its own again. The cells are inside '
            'an ExcludeSemantics so the row reads as one sentence; putting a '
            'label back on a cell undoes that and gives the reader six '
            'announcements instead of five.',
      );
    }

    // The visual cell is still there. A change that fixed the announcement by
    // deleting the column would pass every assertion above.
    expect(find.text('verible'), findsOneWidget);
    expect(find.text('line-length'), findsOneWidget);

    handle.dispose();
  });

  // Every shipped locale, not just one: the point of resolving severity
  // through the localizations is that it holds in all of them, and a single
  // spot-check in `ja` would pass while `ko` announced an English enum name.
  for (final locale in L10N.supportedLocales) {
    testWidgets(
      'the announcement is localized in ${locale.toLanguageTag()}',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(ViolationTableRow(violation: violation()), locale: locale),
        );
        await tester.pumpAndSettle();

        final l10n = await L10N.delegate.load(locale);
        expect(
          find.bySemanticsLabel(
            l10n.accessibilityViolationRow(
              severityLabelForTest(l10n),
              'line-length',
              'rtl/top.sv',
              42,
              'Line too long (95 > 80)',
            ),
          ),
          findsOneWidget,
          reason:
              'A screen reader in ${locale.toLanguageTag()} should hear a '
              'sentence in that language. The severity in particular must come '
              'from the localizations rather than `Severity.warning.name`, '
              'which would be read out as the English identifier in every '
              'locale.',
        );

        handle.dispose();
      },
    );
  }
}

/// The localized severity the fixture violation carries.
///
/// Deliberately resolved through the same helper the widget uses rather than
/// hardcoded per locale: a test that hardcodes the translation passes when the
/// widget stops localizing and the ARB happens to still match.
String severityLabelForTest(L10N l10n) => l10n.severityWarning;
