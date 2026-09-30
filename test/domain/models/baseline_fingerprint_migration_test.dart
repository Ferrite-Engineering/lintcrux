// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// On-disk format migration guard for BaselineFingerprint.compute.
//
// The fingerprint is persisted in every `.lintcrux-baseline.json` file, so its
// 16-hex output MUST stay byte-identical across implementation changes or
// existing baselines silently stop matching. This test pins the output of a
// deliberately adversarial corpus (whitespace runs, ASCII + Unicode whitespace,
// surrogate-pair emoji, CJK, pipe-separator collisions, all-whitespace, very
// long strings) against a committed golden.
//
// The golden was captured from the original BigInt FNV-1a implementation; the
// int two-32-bit-halves reimplementation must reproduce it exactly. If a change
// is genuinely intended to move fingerprints (it should almost never be), run:
//
//   LC_UPDATE_FIXTURE=1 flutter test test/domain/models/baseline_fingerprint_migration_test.dart
//
// and bump the baseline schema version + add a real migration.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';

const _goldenPath = 'test/domain/models/baseline_fingerprint_golden.json';

/// `[ruleId, filePath, message]` triples. Order is load-bearing — the golden
/// is keyed by index, so append new cases at the end, never insert.
final _corpus = <List<String>>[
  ['verilator/UNUSEDSIGNAL', '/proj/src/cpu.sv', "Signal is unused: 'clk'"],
  ['verible/line-length', '/proj/src/alu.sv', ''],
  // Whitespace-run normalization: tabs, newlines, multiple spaces collapse.
  [
    'verilator/WIDTH',
    '/proj/src/mem.sv',
    'Operator\tADD\n\nexpects   8   bits,\r\ngot 16',
  ],
  // Leading / trailing whitespace is trimmed.
  ['r/x', '/f.sv', '   padded message   '],
  // ASCII + Unicode whitespace in the \s class (NBSP, em-space, line/para sep).
  ['r/ws', '/f.sv', 'a b c d ef'],
  // Surrogate-pair emoji contributes two UTF-16 code units.
  ['r/emoji', '/f.sv', 'boom \u{1F4A5} here'],
  // Non-whitespace Unicode + CJK.
  ['r/cjk', '/src/éè.sv', '信号 未使用'],
  // Pipe collides with the field separator on purpose.
  ['r|x', '/a|b.sv', 'has | pipe | chars'],
  // All-whitespace message normalizes to empty.
  ['r/blank', '/f.sv', ' \t\n\r '],
  // Long message.
  ['r/long', '/f.sv', 'x y ' * 400],
  // Single characters at the boundaries of the ASCII range.
  ['\x00', '\x7f', '\x01￿'],
];

void main() {
  test(
    'BaselineFingerprint.compute is byte-stable vs the committed golden '
    '(on-disk 16-hex format migration guard)',
    () {
      final actual = <String, String>{
        for (var i = 0; i < _corpus.length; i++)
          '$i': BaselineFingerprint.compute(
            ruleId: _corpus[i][0],
            filePath: _corpus[i][1],
            message: _corpus[i][2],
          ),
      };

      // Every output is a well-formed unsigned 16-char lowercase hex string.
      final hex16 = RegExp(r'^[0-9a-f]{16}$');
      for (final entry in actual.entries) {
        expect(
          actual[entry.key],
          matches(hex16),
          reason: 'corpus[${entry.key}] is not 16 lowercase hex chars',
        );
      }

      final file = File(_goldenPath);
      final update = Platform.environment['LC_UPDATE_FIXTURE'] == '1';
      if (update || !file.existsSync()) {
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(actual)}\n',
        );
        return;
      }
      final golden = (json.decode(file.readAsStringSync()) as Map)
          .cast<String, String>();
      expect(
        actual,
        golden,
        reason:
            'BaselineFingerprint output changed — the on-disk 16-hex format '
            'moved and existing baselines would stop matching. Revert, or '
            'bump the baseline schema version with a migration.',
      );
    },
  );

  test(
    'int two-32-bit-halves FNV agrees with the BigInt reference across the '
    'full code-unit space (web-safety breadth guard)',
    () {
      // Deterministic, seeded. Messages are built from arbitrary UTF-16 code
      // units (0..0xFFFF) so surrogates, whitespace, and high code points are
      // all exercised — if the 16-bit-limb multiply ever diverged from true
      // uint64 arithmetic, this fails.
      final rng = Random(0xB4A5E11E);
      String randomString(int maxLen) {
        final len = rng.nextInt(maxLen + 1);
        return String.fromCharCodes(
          <int>[for (var i = 0; i < len; i++) rng.nextInt(0x10000)],
        );
      }

      for (var i = 0; i < 3000; i++) {
        final ruleId = randomString(12);
        final filePath = randomString(24);
        final message = randomString(48);
        expect(
          BaselineFingerprint.compute(
            ruleId: ruleId,
            filePath: filePath,
            message: message,
          ),
          _bigIntReferenceFingerprint(ruleId, filePath, message),
          reason: 'divergence at iteration $i',
        );
      }
    },
  );
}

/// The original BigInt FNV-1a implementation, kept here as an independent
/// oracle for the property test above.
String _bigIntReferenceFingerprint(
  String ruleId,
  String filePath,
  String message,
) {
  final normalizedMessage = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  final normalized = '$ruleId|$filePath|$normalizedMessage';
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  for (final unit in normalized.codeUnits) {
    hash ^= BigInt.from(unit);
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
