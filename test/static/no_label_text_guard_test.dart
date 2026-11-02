// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: a source scan; it renders nothing.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The Crux Desktop theme sets `floatingLabelBehavior: never`, so an
// `InputDecoration.labelText` is visible only while its field is empty: a
// field that holds a value would read as a bare value with no label. A field
// whose value the user must identify is a `CruxFormRow` (label always
// visible, the label also the accessible name). A pure search or filter box
// uses `hintText` and names itself with `Semantics(label: ...)`.
//
// So `labelText:` does not appear under `lib/`. Each allowance below is one
// file and line with the reason that field's label can disappear safely; the
// list is empty and does not grow.

const _allowances = <String>[];

void main() {
  test('the allow-list is empty', () {
    expect(_allowances, isEmpty);
  });

  test('no InputDecoration labelText in lib/', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the package root');

    final offenders = <String>[];
    var scanned = 0;
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart')) continue;
      scanned++;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (line.contains('labelText:')) {
          final where = '$path:${i + 1}';
          if (!_allowances.contains(where)) offenders.add('$where  $line');
        }
      }
    }

    expect(scanned, greaterThan(100));
    expect(
      offenders,
      isEmpty,
      reason:
          'A labelText shows only while the field is empty under the Crux '
          'Desktop theme. Move the field into a CruxFormRow (a search box: '
          'hintText plus Semantics(label:)):\n${offenders.join('\n')}',
    );
  });
}
