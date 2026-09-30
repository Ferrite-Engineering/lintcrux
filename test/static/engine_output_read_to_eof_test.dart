// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Engine output is read in one place, and read to end-of-file.
///
/// A subprocess's exit code and its output reach Dart on separate channels
/// with no ordering between them. Every engine adapter used to listen to
/// stdout and stderr, await the exit code, and stop listening — which drops
/// whatever had not yet arrived. On CI that lost Verible's one-line rejection
/// of `--lint_output` two runs in three; for Slang, GHDL, svlint and Verilator
/// the same loss reported a clean run with no error at all.
///
/// `collectProcessOutput` in `process_runner.dart` reads both streams to their
/// end, and `engine_output_drain_test.dart` proves each adapter survives output
/// that lands after the exit. This guard keeps the next adapter from reading a
/// `LintProcess` itself: the behavioural test covers only the adapters that
/// exist today, and an adapter written from memory reintroduces the race.
///
/// MUTATION: adding `await proc.exitCode;` or `proc.stderr.listen(lines.add);`
/// to any engine adapter makes this guard red.
void main() {
  test('no engine adapter reads a subprocess outside collectProcessOutput', () {
    final dir = Directory('lib/services/engines');
    expect(dir.existsSync(), isTrue, reason: 'run from the package root');

    final offenders = <String>[];
    for (final file
        in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final rel = p.relative(file.path);
      if (p.basename(rel) == _seam) continue;
      final source = file.readAsStringSync();
      for (final shape in _directReads) {
        for (final match in shape.allMatches(source)) {
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('$rel:$line  ${match.group(0)}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'An engine adapter reads its subprocess directly. Read it with '
          'collectProcessOutput (process_runner.dart), which waits for both '
          'streams to end rather than for the exit code — stopping at the '
          'exit drops output, and a lint engine that drops its output reports '
          'a clean run.\n${offenders.join('\n')}',
    );
  });

  /// The exemption is asserted, not just declared: if the seam stops reading
  /// the process itself, it no longer needs one.
  test('the seam is still the one place that reads a subprocess', () {
    final seam = File(p.join('lib', 'services', 'engines', _seam));
    expect(seam.existsSync(), isTrue, reason: '$_seam must exist');
    final source = seam.readAsStringSync();
    expect(
      source,
      contains('Future<CapturedProcessOutput> collectProcessOutput('),
    );
    expect(_directReads.first.hasMatch(source), isTrue);
  });
}

/// The one file that may read a `LintProcess` directly.
const _seam = 'process_runner.dart';

/// Shapes of reading a process's exit code or output streams by hand.
final _directReads = <RegExp>[
  RegExp(r'\bawait\s+[\w.]+\s*\.\s*exitCode\b'),
  RegExp(r'\.\s*exitCode\s*\.\s*(then|timeout|whenComplete)\s*\('),
  RegExp(
    r'\.\s*(stdout|stderr)\s*\.\s*'
    r'(listen|toList|drain|join|forEach|first|last|fold|transform)\b',
  ),
  RegExp(r'\bawait\s+for\s*\([^)]*\bin\s+[\w.]+\s*\.\s*(stdout|stderr)\s*\)'),
];
