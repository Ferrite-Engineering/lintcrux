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
// is the reason this sweep happened now; this guard is what keeps a new
// violation from shipping quietly afterward.
//
// A 2026-09 sweep of this repository found no use of the token at all — the
// `_exemptions` list below is empty on purpose, not by omission. The next
// use, text or not, has to be reviewed and either fixed or pinned here with
// a reason.
//
// ## Heuristic, and why
//
// A precise "does this feed a `TextStyle.color`?" check needs a type-aware
// analysis this guard doesn't have. Instead it scans for the bare,
// word-bounded token `.outline` (so `.outlineVariant` never matches — there
// is no word boundary between "e" and "V" — and neither does an `Icons.*`
// name like `help_outline`, since nothing precedes "outline" there with a
// literal `.`) under any receiver: `colorScheme.outline`, `theme.colorScheme
// .outline`, a local `scheme.outline`, `cs.outline`, and so on — the token
// match is deliberately receiver-agnostic, because the sweep that produced
// this guard found more than one spelling in use across the suite.
//
// Every surviving occurrence must be pinned in `_exemptions` with the exact
// file, line, and trimmed line content, plus a reason it is NOT a text-color
// use. If the file changes around that line, the recorded content stops
// matching and the guard re-flags whatever now sits there instead of
// silently carrying the exemption forward.
//
// ## Scope
//
// `lib/` only, this repository. Each of the suite's open cores keeps its
// own copy of this guard, scoped to its own `lib/`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // No occurrence of the token survives in this repository. Keep this list
  // empty rather than pre-seeding a placeholder — an empty list here is the
  // honest, currently-true state, and the "matches the shapes it must"
  // test below proves the pattern isn't simply broken.
  final exemptions = <_Exemption>[];

  test('the outline token is never used to color text', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason:
          'lib/ must exist for this guard to mean anything — run from the '
          'repository root',
    );

    // Word-bounded, receiver-agnostic: matches `colorScheme.outline`,
    // `theme.colorScheme.outline`, `scheme.outline`, `cs.outline`, ... but
    // never `.outlineVariant` (no boundary between "e" and "V") and never an
    // `Icons.*_outline` name (no literal "." precedes "outline" there).
    final tokenPattern = RegExp(r'\.outline\b(?!Variant)');

    final exemptByFile = <String, List<_Exemption>>{};
    for (final e in exemptions) {
      exemptByFile.putIfAbsent(e.file, () => []).add(e);
    }

    final offenders = <String>[];
    var filesScanned = 0;
    var tokensSeen = 0;

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      filesScanned++;

      final lines = entity.readAsStringSync().split('\n');
      final fileExemptions = exemptByFile[relPath] ?? const [];
      for (var i = 0; i < lines.length; i++) {
        if (!tokenPattern.hasMatch(lines[i])) continue;
        tokensSeen++;

        final lineNo = i + 1;
        final trimmed = lines[i].trim();
        final isExempt = fileExemptions.any(
          (e) => e.line == lineNo && e.expectedTrimmed == trimmed,
        );
        if (isExempt) continue;

        offenders.add('$relPath:$lineNo: $trimmed');
      }
    }

    // Non-vacuity: a broken regex or a wrong working directory would make
    // this guard pass by finding nothing at all — the same shape of
    // "pass" as the genuinely-clean case, so the file-count floor below is
    // this guard's only defense against that failure mode.
    expect(
      filesScanned,
      greaterThan(100),
      reason:
          'the source walk collected implausibly few files — check the '
          'working directory (must run from the repository root)',
    );
    expect(
      tokensSeen,
      equals(0),
      reason:
          'this repository was clean of the outline token as of the last '
          'sweep; $tokensSeen occurrence(s) now exist. Classify each as '
          'text (fix to onSurfaceVariant) or non-text (add to _exemptions '
          'with a reason).',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'the outline token is used where onSurfaceVariant belongs (or an '
          "unreviewed new use that needs an entry in this guard's "
          'exemption list, with a reason):\n\n${offenders.join('\n')}',
    );
  });

  test('the token pattern matches the shapes it must and none it must not', () {
    final tokenPattern = RegExp(r'\.outline\b(?!Variant)');
    for (final positive in <String>[
      'color: theme.colorScheme.outline,',
      'color: colorScheme.outline,',
      'color: cs.outline,',
      'color: scheme.outline,',
    ]) {
      expect(
        tokenPattern.hasMatch(positive),
        isTrue,
        reason: 'should have matched: $positive',
      );
    }
    for (final negative in <String>[
      'theme.colorScheme.outlineVariant',
      'icon: Icons.help_outline,',
      'border: const OutlineInputBorder()',
    ]) {
      expect(
        tokenPattern.hasMatch(negative),
        isFalse,
        reason: 'should not have matched: $negative',
      );
    }
  });
}

class _Exemption {
  const _Exemption({
    required this.file,
    required this.line,
    required this.expectedTrimmed,
    required this.reason,
  });

  final String file;
  final int line;
  final String expectedTrimmed;

  /// Not read by the check itself — kept for a human auditing the list.
  final String reason;
}
