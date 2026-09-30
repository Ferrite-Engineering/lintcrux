// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/theme/lintcrux_colors.dart';
import 'package:lintcrux/core/theme/lintcrux_theme_tokens.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/features/violations/widgets/severity_chip.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Pumps [child] under a theme carrying [tokens].
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Map<String, Color>> tokens = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      theme: ThemeData(
        extensions: <ThemeExtension<dynamic>>[
          CruxThemeExtension(
            theme: CruxColorTheme(
              id: 'test',
              displayName: 'Test',
              brightness: Brightness.light,
              tokens: tokens,
            ),
          ),
        ],
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('token catalogs', () {
    test('registration is idempotent — a second bootstrap must not throw', () {
      registerLintcruxThemeTokens();
      registerLintcruxThemeTokens();

      final registry = ThemeRegistry.instance;
      expect(registry.hasCategory(kLintcruxSeverityCategoryId), isTrue);
      expect(registry.hasCategory(kLintcruxTrendCategoryId), isTrue);
    });

    test('severity catalog covers every Severity value — a token the enum '
        'has no entry for would be unthemable', () {
      final ids = lintcruxSeverityTokens.tokens.map((t) => t.id).toSet();
      expect(ids, {'fatal', 'error', 'warning', 'note', 'none'});
      expect(ids.length, Severity.values.length);
    });

    test('severity light defaults match the built-in palette so an '
        'unthemed build is unchanged', () {
      Color lightFor(String id) => lintcruxSeverityTokens.tokens
          .firstWhere((t) => t.id == id)
          .lightDefault;

      expect(lightFor('fatal'), LintcruxColors.severityFatal);
      expect(lightFor('error'), LintcruxColors.severityError);
      expect(lightFor('warning'), LintcruxColors.severityWarning);
      expect(lightFor('note'), LintcruxColors.severityNote);
      expect(lightFor('none'), LintcruxColors.severityNone);
    });

    test('every token declares a distinct dark default — reusing the light '
        'value would lose contrast on a dark table', () {
      for (final category in <ThemeTokenCategory>[
        lintcruxSeverityTokens,
        lintcruxTrendTokens,
      ]) {
        for (final token in category.tokens) {
          expect(
            token.darkDefault,
            isNot(token.lightDefault),
            reason: '${category.id}.${token.id}',
          );
        }
      }
    });

    test('trend catalog carries the four series roles', () {
      expect(
        lintcruxTrendTokens.tokens.map((t) => t.id).toSet(),
        {'improving', 'worsening', 'flat', 'baseline'},
      );
    });
  });

  group('severityColor', () {
    testWidgets('falls back to the built-in palette with no tokens', (
      tester,
    ) async {
      late Color resolved;
      await _pump(
        tester,
        Builder(
          builder: (context) {
            resolved = severityColor(context, Severity.error);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(resolved, LintcruxColors.severityError);
    });

    testWidgets('an imported pack retunes the table', (tester) async {
      const packed = Color(0xFF00FF00);
      late Color resolved;
      await _pump(
        tester,
        Builder(
          builder: (context) {
            resolved = severityColor(context, Severity.error);
            return const SizedBox.shrink();
          },
        ),
        tokens: const {
          kLintcruxSeverityCategoryId: {'error': packed},
        },
      );
      expect(resolved, packed);
    });

    testWidgets('a pack that themes only some severities leaves the rest on '
        'the built-in palette', (tester) async {
      const packed = Color(0xFF00FF00);
      late Color error;
      late Color warning;
      await _pump(
        tester,
        Builder(
          builder: (context) {
            error = severityColor(context, Severity.error);
            warning = severityColor(context, Severity.warning);
            return const SizedBox.shrink();
          },
        ),
        tokens: const {
          kLintcruxSeverityCategoryId: {'error': packed},
        },
      );
      expect(error, packed);
      expect(warning, LintcruxColors.severityWarning);
    });

    testWidgets('SeverityIcon paints the themed color', (tester) async {
      const packed = Color(0xFF123456);
      await _pump(
        tester,
        const SeverityIcon(severity: Severity.fatal),
        tokens: const {
          kLintcruxSeverityCategoryId: {'fatal': packed},
        },
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, packed);
    });
  });
}
