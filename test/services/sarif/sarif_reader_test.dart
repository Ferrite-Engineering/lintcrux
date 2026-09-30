// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/sarif/sarif_reader.dart';

void main() {
  group('SarifReader', () {
    const reader = SarifReader();

    test('parses the verilator_basic fixture into typed values', () {
      final body = File(
        'test/fixtures/sarif/verilator_basic.sarif.json',
      ).readAsStringSync();
      final report = reader.read(body);

      expect(report.version, '2.1.0');
      expect(report.runs, hasLength(1));

      final run = report.runs.single;
      expect(run.engineId, 'verilator');
      expect(run.engineVersion, '5.026 2024-09-01');
      expect(run.success, isTrue);
      expect(run.exitCode, 0);
      expect(run.startedAt.isUtc, isTrue);
      expect(run.finishedAt.isAfter(run.startedAt), isTrue);

      expect(run.violations, hasLength(4));

      final unused = run.violations[0];
      expect(unused.engineId, 'verilator');
      expect(unused.ruleId, 'verilator/UNUSEDSIGNAL');
      expect(unused.severity, Severity.warning);
      expect(unused.message, contains('unused_wire'));
      expect(unused.location.file, 'src/top.v');
      expect(unused.location.line, 17);
      expect(unused.location.column, 8);
      expect(unused.location.endLine, 17);
      expect(unused.location.endColumn, 19);
      expect(unused.relatedLocations, hasLength(1));
      expect(unused.relatedLocations.first.line, 23);
      expect(unused.raw['properties'], isA<Map<String, dynamic>>());

      final width = run.violations[1];
      expect(width.ruleId, 'verilator/WIDTHTRUNC');
      expect(width.relatedLocations, isEmpty);

      final pin = run.violations[2];
      expect(pin.severity, Severity.error);

      // Fatal extension: SARIF level is `error`, but
      // properties.lintcrux.severity = "fatal" overrides.
      final syntax = run.violations[3];
      expect(syntax.severity, Severity.fatal);
    });

    test('throws for non-JSON input', () {
      expect(
        () => reader.read('not json'),
        throwsA(isA<SarifReadException>()),
      );
    });

    test('throws when top-level is not a JSON object', () {
      expect(
        () => reader.read('[]'),
        throwsA(isA<SarifReadException>()),
      );
    });

    test('throws when `runs` is missing or wrong type', () {
      expect(
        () => reader.read('{"version":"2.1.0"}'),
        throwsA(isA<SarifReadException>()),
      );
      expect(
        () => reader.read('{"runs":"oops"}'),
        throwsA(isA<SarifReadException>()),
      );
    });

    test('defaults missing optional fields gracefully', () {
      const minimal = '''
{
  "version": "2.1.0",
  "runs": [
    {
      "tool": {"driver": {"name": "verible"}},
      "results": [
        {
          "ruleId": "STYLE_X",
          "message": {"text": "msg"},
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {"uri": "/tmp/a.sv"},
                "region": {"startLine": 5, "startColumn": 1}
              }
            }
          ]
        }
      ]
    }
  ]
}
''';
      final report = reader.read(minimal);
      final v = report.runs.single.violations.single;
      expect(v.engineId, 'verible');
      expect(v.severity, Severity.warning); // default
      expect(v.location.endLine, isNull);
      expect(v.location.endColumn, isNull);
    });

    test('namespaces unprefixed ruleId with the engine name', () {
      const body = '''
{
  "version": "2.1.0",
  "runs": [
    {
      "tool": {"driver": {"name": "slang"}},
      "results": [
        {
          "ruleId": "UnusedVariable",
          "level": "note",
          "message": {"text": "x"},
          "locations": [
            {
              "physicalLocation": {
                "artifactLocation": {"uri": "/a.sv"},
                "region": {"startLine": 1, "startColumn": 1}
              }
            }
          ]
        }
      ]
    }
  ]
}
''';
      final v = reader.read(body).runs.single.violations.single;
      expect(v.ruleId, 'slang/UnusedVariable');
      expect(v.severity, Severity.note);
    });
  });
}
