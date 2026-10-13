// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: a widget's `ref` is never used after an `await` without a
// `mounted` check in between.
//
// A `ConsumerState`'s `ref`, or the `WidgetRef` a `ConsumerWidget.build`
// hands to a callback, belongs to an element. After an `await` that element
// may have been unmounted (the tab closed, the dialog dismissed, the row
// scrolled out of the virtualized list), and reading a provider through a
// disposed `ref` throws, or worse, reads the wrong container. The fix is one
// of two shapes: read what the continuation needs *before* the await (a
// notifier captured up front outlives the widget), or check `mounted` /
// `context.mounted` / `ref.mounted` right after it.
//
// The scanner is `crux_guards`' `cruxAuditRefAfterAwait`, shared by the four
// products. It parses each file, so a comment never matches, and it does not
// resolve types: a `mounted` check anywhere between the await and the use
// counts, and a `ref` outside a `ConsumerState` or a `WidgetRef` parameter
// is not in scope. An exemption that matches nothing is itself a finding.
//
// The companion `test/static/captured_ref_use_test.dart` covers the other
// half of the same hazard: a `ref` captured into a closure that outlives its
// builder.

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('no widget uses its ref after an await without a mounted check', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue, reason: 'run from the repository root');
    final sources = <CruxGuardSource>[
      for (final entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          CruxGuardSource(
            path: p.relative(entity.path).replaceAll(r'\', '/'),
            source: entity.readAsStringSync(),
          ),
    ];

    // No exemptions: the eleven sites the first run found were fixed (a
    // notifier captured before the await, or a `mounted` check after it).
    // A deliberate case goes here as a `CruxRefAfterAwaitExemption(file:,
    // function:, reason:)` passed as `exemptions:`.
    final result = cruxAuditRefAfterAwait(sources: sources);

    expect(
      result.filesScanned,
      greaterThan(100),
      reason:
          'the source walk collected implausibly few files — check the '
          'working directory (must run from the repository root)',
    );
    expect(
      result.isClean,
      isTrue,
      reason:
          'a widget reads through its ref after an await with no mounted '
          'check between them. Capture what the continuation needs before '
          'the await, or check `mounted` after it; pin a deliberate case '
          'with a CruxRefAfterAwaitExemption and its reason:\n\n'
          '${result.describe()}',
    );
  });
}
