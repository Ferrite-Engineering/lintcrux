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
// There are no allowances, and the list never grows: the bookmark-removed
// toast carries its Undo through the shared toast helpers' action.

const _allowances = <CruxDesktopAllowance>[];

void main() {
  test('the allow-list is empty', () {
    expect(_allowances, isEmpty);
  });

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
      // The empty list is the default; passing it keeps the claim above
      // checked by the test above.
      // ignore: avoid_redundant_argument_values
      allowances: _allowances,
    );

    expect(result.filesScanned, greaterThan(100));
    expect(result.isClean, isTrue, reason: result.describe());
  });
}
