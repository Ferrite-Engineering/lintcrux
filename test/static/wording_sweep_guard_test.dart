// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Wording canon for the labels the 2026-11 suite audit found worded
// differently across the four products (D05, D44, D48, D51, D52, D54). A
// label that opens a dialog ends in the ellipsis character in every locale;
// the Reset Workspace confirmation says what it replaces and does not
// contradict itself; an open-core action whose opener is missing says "is not
// available in this build" and never promises a future.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];

/// Labels that open a dialog or a picker.
const _dialogOpeners = <String>[
  'actionSaveSession',
  'actionCrossProbeSelection',
  'aboutButtonSubmitIssue',
];

Map<String, dynamic> _load(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  if (!file.existsSync()) {
    throw StateError('missing ${file.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final arbs = {for (final l in _locales) l: _load(l)};
  final en = arbs['en']!;

  for (final locale in _locales) {
    test('$locale: dialog-opening labels end in an ellipsis', () {
      for (final key in _dialogOpeners) {
        expect(
          (arbs[locale]![key] as String).endsWith('…'),
          isTrue,
          reason: '$key in app_$locale.arb is "${arbs[locale]![key]}"',
        );
      }
    });

    test('$locale: the not-available notice is the "in this build" key', () {
      expect(arbs[locale]!.containsKey('snackFeatureNotAvailableYet'), isFalse);
      expect(
        arbs[locale]!['snackActionUnavailableInThisBuild'],
        contains('{action}'),
      );
    });
  }

  test('en: session save is worded as the Save As dialog it opens', () {
    expect(en['actionSaveSession'], 'Save Session As…');
  });

  test('en: Cross-Probe Selection… is hyphenated and capitalised', () {
    expect(en['actionCrossProbeSelection'], 'Cross-Probe Selection…');
  });

  test('en: the About issue button reads as the Help menu item does', () {
    expect(en['aboutButtonSubmitIssue'], 'Submit Issue…');
    expect(en['aboutButtonSubmitIssue'], en['actionSubmitIssue']);
  });

  test('en: the not-available notice names the build, not a future', () {
    expect(
      en['snackActionUnavailableInThisBuild'],
      '{action} is not available in this build.',
    );
  });

  test('en: the Reset Workspace confirmation does not contradict itself', () {
    expect(en['workspaceResetConfirmTitle'], 'Reset workspace?');
    final body = en['workspaceResetConfirmBody'] as String;
    expect(body, startsWith('All open tabs will be closed.'));
    expect(body, contains('This cannot be undone.'));
    expect(body, isNot(contains('but')));
  });

  test('en: no user-visible string spells "licence"', () {
    final offenders = <String>[
      for (final e in en.entries)
        if (!e.key.startsWith('@') &&
            e.value is String &&
            (e.value as String).toLowerCase().contains('licence'))
          e.key,
    ];
    expect(offenders, isEmpty);
  });
}
