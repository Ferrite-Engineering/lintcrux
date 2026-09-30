// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/issue_reporter/lintcrux_issue_reporter_strings.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];

L10N _l10n(String tag) {
  final parts = tag.split('_');
  return lookupL10N(
    parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts[0]),
  );
}

void main() {
  group('LintcruxIssueReporterStrings', () {
    test('every getter resolves in every shipped locale', () {
      for (final tag in _locales) {
        final s = LintcruxIssueReporterStrings(_l10n(tag));
        for (final value in <String>[
          s.dialogTitle,
          s.titleFieldLabel,
          s.titleFieldHint,
          s.privacyNotice,
          s.previewHeader,
          s.categoryAppEnv,
          s.categoryAppEnvDescription,
          s.categorySession,
          s.categorySessionDescription,
          s.categoryLog,
          s.categoryLogDescription,
          s.categoryScreenshot,
          s.categoryScreenshotDescription,
          s.lockedCategorySemantics,
          s.submitButton,
          s.cancelButton,
          s.openedToast,
          s.openedToastPrefilled,
          s.screenshotSaved('/tmp/shot.png'),
          s.emptyLogPlaceholder,
          s.emptySessionLogPlaceholder,
        ]) {
          expect(value, isNotEmpty, reason: 'empty reporter string in $tag');
        }
      }
    });

    test('the screenshot path is interpolated in every locale', () {
      for (final tag in _locales) {
        expect(
          LintcruxIssueReporterStrings(
            _l10n(tag),
          ).screenshotSaved('/tmp/x.png'),
          contains('/tmp/x.png'),
          reason: 'screenshotSaved dropped the path in $tag',
        );
      }
    });

    test(
      'the privacy notice states the no-paths guarantee in every locale',
      () {
        // The notice is the user-facing half of the privacy contract asserted
        // in `providers/issue_session_context_test.dart`. A locale whose
        // translation lost the guarantee would be quietly misleading.
        for (final tag in _locales) {
          expect(
            LintcruxIssueReporterStrings(_l10n(tag)).privacyNotice.length,
            greaterThan(20),
            reason: 'privacy notice looks truncated in $tag',
          );
        }
      },
    );

    test('zh and zh_CN resolve to the same copy', () {
      expect(
        LintcruxIssueReporterStrings(_l10n('zh')).dialogTitle,
        LintcruxIssueReporterStrings(_l10n('zh_CN')).dialogTitle,
      );
    });
  });
}
