// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';

// The desktop layout uses the Crux Desktop widgets: `showCruxDialog`, the Crux
// snack helpers, `CruxOverflowMenu`, `CruxSwitch` and `CruxFormRow`. The raw
// Material dialogs, snackbars, switches, checkbox tiles and the vertical
// overflow icon do not appear in `lib/`. The scanner is crux_guards'
// `cruxAuditCruxDesktop`; a call site that renders only in a phone layout
// carries a `crux-desktop: phone-only` comment with its reason.
//
// The one allowance is the bookmark-removed toast, whose Undo action the shared
// toast helpers cannot carry yet; it moves onto them once they take an action.
// It never grows, and the list is empty when that site moves.

const _allowances = [
  CruxDesktopAllowance(
    file: 'lib/features/bookmarks/widgets/bookmark_column_icon.dart',
    pattern: CruxDesktopPattern.showSnackBar,
    count: 1,
    reason:
        'The bookmark Undo toast needs the shared toast action; it moves '
        'when the helpers take one.',
  ),
  CruxDesktopAllowance(
    file: 'lib/features/bookmarks/widgets/bookmark_column_icon.dart',
    pattern: CruxDesktopPattern.snackBar,
    count: 1,
    reason:
        'The bookmark Undo toast needs the shared toast action; it moves '
        'when the helpers take one.',
  ),
];

void main() {
  test('no raw Material dialog, snackbar, switch or overflow icon in lib/', () {
    final sources = [
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          CruxGuardSource(
            path: f.path.replaceAll(r'\', '/'),
            source: f.readAsStringSync(),
          ),
    ];

    final result = cruxAuditCruxDesktop(
      sources: sources,
      allowances: _allowances,
    );

    expect(result.filesScanned, greaterThan(100));
    expect(result.isClean, isTrue, reason: result.describe());
  });
}
