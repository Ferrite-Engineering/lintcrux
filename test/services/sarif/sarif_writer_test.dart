// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/sarif/sarif_reader.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart';

void main() {
  group('SarifWriter', () {
    const writer = SarifWriter();

    test('emits the canonical top-level shape', () {
      final r = SarifReport(
        runs: [
          Run(
            id: 'r1',
            engineId: 'verilator',
            engineVersion: '5.026',
            startedAt: DateTime.utc(2026, 5, 22, 10, 30),
            finishedAt: DateTime.utc(2026, 5, 22, 10, 30, 5),
            violations: const [],
          ),
        ],
      );
      final map = writer.toMap(r);

      expect(map[r'$schema'], r.schema);
      expect(map['version'], '2.1.0');
      expect(map['runs'], isA<List<dynamic>>());
      final runMap = (map['runs'] as List).single as Map<String, dynamic>;
      expect(runMap['tool'], isA<Map<String, dynamic>>());
      expect(runMap['invocations'], isA<List<dynamic>>());
      expect(runMap['automationDetails'], <String, dynamic>{'id': 'r1'});
      expect(runMap['results'], isEmpty);
    });

    test('writes violations with structured fields and the level mapping', () {
      const v = Violation(
        engineId: 'verible',
        ruleId: 'verible/STYLE_X',
        severity: Severity.note,
        message: 'too many spaces',
        location: SourceLocation(
          file: '/p/a.sv',
          line: 7,
          column: 4,
          endLine: 7,
          endColumn: 10,
        ),
      );
      final r = SarifReport(
        runs: [
          Run(
            id: 'r',
            engineId: 'verible',
            engineVersion: '0.0',
            startedAt: DateTime.utc(2026),
            finishedAt: DateTime.utc(2026),
            violations: const [v],
          ),
        ],
      );
      final m = writer.toMap(r);
      final result =
          ((m['runs'] as List).single as Map<String, dynamic>)['results']
              as List;
      final entry = result.single as Map<String, dynamic>;
      expect(entry['ruleId'], 'STYLE_X'); // engine prefix stripped
      expect(entry['level'], 'note');
      expect(entry['message'], <String, dynamic>{'text': 'too many spaces'});
      final loc = (entry['locations'] as List).single as Map<String, dynamic>;
      final phys = loc['physicalLocation'] as Map<String, dynamic>;
      final region = phys['region'] as Map<String, dynamic>;
      expect(region['startLine'], 7);
      expect(region['endColumn'], 10);
    });

    test('emits the lintcrux fatal extension', () {
      const v = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/SYNTAX',
        severity: Severity.fatal,
        message: 'aborted',
        location: SourceLocation(file: 'a.v', line: 1, column: 1),
      );
      final m = writer.toMap(
        SarifReport(
          runs: [
            Run(
              id: 'r',
              engineId: 'verilator',
              engineVersion: '5.026',
              startedAt: DateTime.utc(2026),
              finishedAt: DateTime.utc(2026),
              violations: const [v],
            ),
          ],
        ),
      );
      final entry =
          (((m['runs'] as List).single as Map<String, dynamic>)['results']
                      as List)
                  .single
              as Map<String, dynamic>;
      expect(entry['level'], 'error'); // SARIF has no fatal
      final props = entry['properties'] as Map<String, dynamic>;
      final lcrux = props['lintcrux'] as Map<String, dynamic>;
      expect(lcrux['severity'], 'fatal');
    });

    test('omits relatedLocations when empty', () {
      const v = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/X',
        severity: Severity.warning,
        message: 'm',
        location: SourceLocation(file: 'a.v', line: 1, column: 1),
      );
      final m = writer.toMap(
        SarifReport(
          runs: [
            Run(
              id: 'r',
              engineId: 'verilator',
              engineVersion: '5.026',
              startedAt: DateTime.utc(2026),
              finishedAt: DateTime.utc(2026),
              violations: const [v],
            ),
          ],
        ),
      );
      final entry =
          (((m['runs'] as List).single as Map<String, dynamic>)['results']
                      as List)
                  .single
              as Map<String, dynamic>;
      expect(entry.containsKey('relatedLocations'), isFalse);
    });

    test('pretty-print produces multi-line, valid JSON', () {
      final body = writer.write(
        SarifReport(
          runs: [
            Run(
              id: 'r',
              engineId: 'verilator',
              engineVersion: '5.026',
              startedAt: DateTime.utc(2026),
              finishedAt: DateTime.utc(2026),
              violations: const [],
            ),
          ],
        ),
      );
      expect(body, contains('\n  '));
      final decoded = jsonDecode(body);
      expect(decoded, isA<Map<String, dynamic>>());
    });

    test('compact output (pretty: false) produces single-line JSON', () {
      const compactWriter = SarifWriter(pretty: false);
      final body = compactWriter.write(
        SarifReport(
          runs: [
            Run(
              id: 'r',
              engineId: 'verilator',
              engineVersion: '5.026',
              startedAt: DateTime.utc(2026),
              finishedAt: DateTime.utc(2026),
              violations: const [],
            ),
          ],
        ),
      );
      expect(body.contains('\n'), isFalse);
    });
  });

  group('SARIF round-trip (property test)', () {
    test('read → write → read produces structurally equal violations', () {
      const reader = SarifReader();
      const writer = SarifWriter();
      final src = File(
        'test/fixtures/sarif/verilator_basic.sarif.json',
      ).readAsStringSync();
      final originalMap = jsonDecode(src) as Map<String, dynamic>;
      final report = reader.read(src);
      final roundTripped = writer.write(report);
      final newMap = jsonDecode(roundTripped) as Map<String, dynamic>;

      // Structural-equivalence check: counts and key fields.
      expect(newMap['version'], originalMap['version']);
      expect(
        (newMap['runs'] as List).length,
        (originalMap['runs'] as List).length,
      );

      final origResults =
          (((originalMap['runs'] as List).single
                      as Map<String, dynamic>)['results']
                  as List)
              .cast<Map<String, dynamic>>();
      final newResults =
          (((newMap['runs'] as List).single as Map<String, dynamic>)['results']
                  as List)
              .cast<Map<String, dynamic>>();
      expect(newResults.length, origResults.length);

      for (var i = 0; i < origResults.length; i++) {
        final o = origResults[i];
        final n = newResults[i];
        expect(n['ruleId'], o['ruleId']);
        expect(n['level'], o['level']);
        expect(
          (n['message'] as Map)['text'],
          (o['message'] as Map)['text'],
        );
        final op =
            ((o['locations'] as List).first as Map)['physicalLocation'] as Map;
        final np =
            ((n['locations'] as List).first as Map)['physicalLocation'] as Map;
        expect(
          (np['artifactLocation'] as Map)['uri'],
          (op['artifactLocation'] as Map)['uri'],
        );
        expect(
          (np['region'] as Map)['startLine'],
          (op['region'] as Map)['startLine'],
        );
        expect(
          (np['region'] as Map)['startColumn'],
          (op['region'] as Map)['startColumn'],
        );

        // Vendor properties survive the round-trip via Violation.raw.
        if (o['properties'] is Map) {
          expect(n['properties'], isA<Map<String, dynamic>>());
          final op2 = (o['properties'] as Map).cast<String, dynamic>();
          final np2 = (n['properties'] as Map).cast<String, dynamic>();
          for (final key in op2.keys) {
            expect(np2.containsKey(key), isTrue, reason: 'vendor key $key');
          }
        }
      }

      // Read the round-tripped JSON again and assert typed equality.
      // Violation `==` ignores `raw` by design, so this compares the
      // structural fields we care about.
      final report2 = reader.read(roundTripped);
      expect(report2.runs.length, report.runs.length);
      for (var i = 0; i < report.runs.length; i++) {
        final a = report.runs[i];
        final b = report2.runs[i];
        expect(b.engineId, a.engineId);
        expect(b.engineVersion, a.engineVersion);
        expect(b.violations.length, a.violations.length);
        for (var j = 0; j < a.violations.length; j++) {
          expect(b.violations[j], a.violations[j]);
        }
      }
    });
  });
  group('SarifWriter schema shape', () {
    const writer = SarifWriter();

    Map<String, dynamic> resultFor(Violation v) {
      final m = writer.toMap(
        SarifReport(
          runs: [
            Run(
              id: 'r',
              engineId: v.engineId,
              engineVersion: '',
              startedAt: DateTime.utc(2026),
              finishedAt: DateTime.utc(2026),
              violations: [v],
            ),
          ],
        ),
      );
      return (((m['runs'] as List).single as Map<String, dynamic>)['results']
                  as List)
              .single
          as Map<String, dynamic>;
    }

    // No SARIF 2.1.0 schema is available offline, so the constraints this
    // writer can break are asserted directly: the `result` object is
    // `additionalProperties: false`, `suppression.kind` is required and an
    // enum, `status` is an enum, and `guid` must be a GUID.
    void expectSchemaShape(Map<String, dynamic> result) {
      expect(
        result.keys.toSet().difference(SarifWriter.sarifResultKeys),
        isEmpty,
        reason: 'result.additionalProperties is false in SARIF 2.1.0',
      );
      final suppressions = result['suppressions'];
      if (suppressions == null) return;
      for (final s in suppressions as List) {
        final entry = s as Map<String, dynamic>;
        expect(entry['kind'], isIn(<String>['inSource', 'external']));
        expect(
          entry['status'],
          anyOf(isNull, isIn(<String>['accepted', 'underReview', 'rejected'])),
        );
        expect(entry.containsKey('guid'), isFalse);
        expect(
          entry.keys.toSet().difference(<String>{
            'guid',
            'kind',
            'status',
            'justification',
            'location',
            'properties',
          }),
          isEmpty,
        );
      }
    }

    test('engine raw keys go into properties, never onto the result', () {
      final result = resultFor(
        const Violation(
          engineId: 'yosys',
          ruleId: 'yosys/undriven-wire',
          severity: Severity.warning,
          message: 'Wire x is used but has no driver.',
          location: SourceLocation(file: 'top.v', line: 1, column: 1),
          raw: <String, dynamic>{
            'yosys.severityRaw': 'warning',
            'yosys.rawLine': 'Warning: Wire x is used but has no driver.',
          },
        ),
      );
      expectSchemaShape(result);
      expect(result['properties'], <String, dynamic>{
        'yosys.severityRaw': 'warning',
        'yosys.rawLine': 'Warning: Wire x is used but has no driver.',
      });
    });

    test('a pragma-suppressed violation carries an inSource suppression', () {
      final result = resultFor(
        Violation(
          engineId: 'verilator',
          ruleId: 'verilator/UNUSEDSIGNAL',
          severity: Severity.warning,
          message: 'Signal is not used: foo',
          location: const SourceLocation(file: 'top.sv', line: 4, column: 1),
          suppression: Waiver(
            id: 'pragma:top.sv:3-5:UNUSEDSIGNAL',
            ruleId: 'verilator/UNUSEDSIGNAL',
            filePath: 'top.sv',
            lineStart: 3,
            lineEnd: 5,
            reason: 'Inline pragma `// verilator lint_off UNUSEDSIGNAL`',
            author: 'source',
            createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
          raw: const <String, dynamic>{
            'lintcrux.pragmaWaiverSourceFile': 'top.sv',
            'lintcrux.pragmaWaiverSourceLine': 3,
          },
        ),
      );
      expectSchemaShape(result);
      final suppression =
          (result['suppressions'] as List).single as Map<String, dynamic>;
      expect(suppression['kind'], 'inSource');
      expect(suppression['status'], 'accepted');
      expect(suppression['justification'], contains('lint_off'));
      expect(
        (suppression['properties'] as Map)['lintcrux'],
        containsPair('waiverId', 'pragma:top.sv:3-5:UNUSEDSIGNAL'),
      );
    });

    test('a managed waiver is an external suppression', () {
      final result = resultFor(
        Violation(
          engineId: 'verilator',
          ruleId: 'verilator/WIDTH',
          severity: Severity.warning,
          message: 'width mismatch',
          location: const SourceLocation(file: 'top.sv', line: 9, column: 1),
          suppression: Waiver(
            id: 'w-1',
            ruleId: 'verilator/WIDTH',
            filePath: 'top.sv',
            reason: 'intentional truncation',
            author: 'alice',
            createdAt: DateTime.utc(2026, 3),
          ),
        ),
      );
      expectSchemaShape(result);
      expect(
        ((result['suppressions'] as List).single as Map)['kind'],
        'external',
      );
    });

    test('an unsuppressed violation drops a suppression read from raw', () {
      final result = resultFor(
        const Violation(
          engineId: 'verilator',
          ruleId: 'verilator/WIDTH',
          severity: Severity.warning,
          message: 'width mismatch',
          location: SourceLocation(file: 'top.sv', line: 9, column: 1),
          raw: <String, dynamic>{
            'suppressions': <Object?>[
              <String, dynamic>{'kind': 'external'},
            ],
          },
        ),
      );
      expect(result.containsKey('suppressions'), isFalse);
    });

    test('suppressions survive a write and a read', () {
      final waived = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'Signal is not used: foo',
        location: const SourceLocation(file: 'top.sv', line: 4, column: 1),
        suppression: Waiver(
          id: 'w-7',
          ruleId: 'verilator/UNUSEDSIGNAL',
          filePath: 'top.sv',
          lineStart: 3,
          lineEnd: 5,
          reason: 'legacy block',
          author: 'alice',
          createdAt: DateTime.utc(2026, 2, 3),
          expiresAt: DateTime.utc(2027),
        ),
      );
      final json = writer.write(
        SarifReport(
          runs: [
            Run(
              id: 'r',
              engineId: 'verilator',
              engineVersion: '',
              startedAt: DateTime.utc(2026),
              finishedAt: DateTime.utc(2026),
              violations: [waived],
            ),
          ],
        ),
      );
      final read = const SarifReader().read(json).runs.single.violations.single;
      expect(read.isSuppressed, isTrue);
      expect(read.suppression, waived.suppression);
    });
  });
}
