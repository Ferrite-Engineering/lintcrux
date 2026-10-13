// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: a ColorScheme's `outline` token never colors TEXT.
//
// `outline` is a Material 3 BORDER token — the hairline around an
// `OutlineInputBorder`, a card edge, a divider, a painter's stroke. The
// suite's UI conventions are explicit that de-emphasised text must use
// `onSurfaceVariant` instead: `outline` was never chosen against WCAG
// text-contrast minimums, only against adjacent surface colors, so using it
// to color text reads as a contrast failure. A paid accessibility re-check
// is the reason this sweep happened; this guard is what keeps a new
// violation from shipping quietly afterward.
//
// The scanner is `crux_guards`' `cruxAuditOutlineText`, shared by the four
// products: it parses each file and flags every `.outline` member access
// (never `.outlineVariant`, never an `Icons.*_outline` name) unless pinned
// in the exemption list with its file, line, trimmed text and a reason it is
// NOT a text-color use. An exemption that matches nothing is itself a
// finding, so the list cannot outlive the code it describes.
//
// A 2026-09 sweep of this repository found no use of the token at all; the
// list below is empty on purpose. The next use, text or not, has to be
// reviewed and either fixed or pinned here.
//
// Scope: `lib/` only, this repository. The Pro overlay runs the same scanner
// over its own `lib/`.

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the outline token is never used to color text', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason:
          'lib/ must exist for this guard to mean anything — run from the '
          'repository root',
    );
    final sources = <CruxGuardSource>[
      for (final entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          CruxGuardSource(
            path: p.relative(entity.path).replaceAll(r'\', '/'),
            source: entity.readAsStringSync(),
          ),
    ];

    // No exemptions: the repository is clean of the token. The first one
    // goes here as a `CruxOutlineExemption(file:, line:, expectedTrimmed:,
    // reason:)` passed as `exemptions:`.
    final result = cruxAuditOutlineText(sources: sources);

    // Non-vacuity: a wrong working directory would make this guard pass by
    // scanning nothing at all.
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
          'the outline token is used where onSurfaceVariant belongs (or an '
          'unreviewed new use that needs a CruxOutlineExemption here, with a '
          'reason):\n\n${result.describe()}',
    );
  });
}
