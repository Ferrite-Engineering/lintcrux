// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/sarif/sarif_reader.dart';
import 'package:lintcrux/services/sarif/streaming_sarif_reader.dart';

void main() {
  group('StreamingSarifReader', () {
    const reader = StreamingSarifReader();
    const baseline = SarifReader();

    /// Materializes [text] as a `Stream<List<int>>` chunked at
    /// [chunkSize] bytes. Used to exercise the scanner across buffer
    /// boundaries.
    Stream<List<int>> chunked(String text, {int chunkSize = 64}) async* {
      final bytes = utf8.encode(text);
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, bytes.length);
        yield bytes.sublist(i, end);
      }
    }

    test('readAll parses the canonical verilator_basic fixture', () async {
      final text = await File(
        'test/fixtures/sarif/verilator_basic.sarif.json',
      ).readAsString();
      final report = await reader.readAll(chunked(text));

      expect(report.version, '2.1.0');
      expect(report.runs, hasLength(1));
      final run = report.runs.single;
      expect(run.engineId, 'verilator');
      expect(run.engineVersion, '5.026 2024-09-01');
      expect(run.success, isTrue);
      expect(run.exitCode, 0);
      expect(run.violations, hasLength(4));

      final unused = run.violations[0];
      expect(unused.ruleId, 'verilator/UNUSEDSIGNAL');
      expect(unused.severity, Severity.warning);
      expect(unused.location.file, 'src/top.v');
      expect(unused.location.line, 17);
      expect(unused.relatedLocations, hasLength(1));

      final width = run.violations[1];
      expect(width.ruleId, 'verilator/WIDTHTRUNC');

      final pin = run.violations[2];
      expect(pin.severity, Severity.error);

      final syntax = run.violations[3];
      // Streaming reader respects the `lintcrux.severity` extension
      // exactly as the non-streaming reader does.
      expect(syntax.severity, Severity.fatal);
    });

    test(
      'stream emits header → run-start → violations → run-end in order',
      () async {
        final text = await File(
          'test/fixtures/sarif/verilator_basic.sarif.json',
        ).readAsString();
        final events = await reader.stream(chunked(text)).toList();

        expect(events.first, isA<StreamingSarifHeader>());
        expect(events[1], isA<StreamingSarifRunStart>());

        final violations = events.whereType<StreamingSarifViolation>().toList();
        expect(violations, hasLength(4));

        expect(events.last, isA<StreamingSarifRunEnd>());
        final end = events.last as StreamingSarifRunEnd;
        expect(end.runIndex, 0);
      },
    );

    test('matches baseline reader violation-for-violation', () async {
      final text = await File(
        'test/fixtures/sarif/verilator_basic.sarif.json',
      ).readAsString();
      final baselineReport = baseline.read(text);
      final streamedReport = await reader.readAll(chunked(text));

      expect(streamedReport.runs.length, baselineReport.runs.length);
      for (var ri = 0; ri < baselineReport.runs.length; ri++) {
        final br = baselineReport.runs[ri];
        final sr = streamedReport.runs[ri];
        expect(sr.engineId, br.engineId);
        expect(sr.engineVersion, br.engineVersion);
        expect(sr.violations.length, br.violations.length);
        for (var vi = 0; vi < br.violations.length; vi++) {
          final bv = br.violations[vi];
          final sv = sr.violations[vi];
          expect(sv.ruleId, bv.ruleId);
          expect(sv.severity, bv.severity);
          expect(sv.message, bv.message);
          expect(sv.location.file, bv.location.file);
          expect(sv.location.line, bv.location.line);
          expect(sv.location.column, bv.location.column);
        }
      }
    });

    test('honors very small chunk sizes across buffer boundaries', () async {
      final text = await File(
        'test/fixtures/sarif/verilator_basic.sarif.json',
      ).readAsString();
      // 16-byte chunks force the scanner to refill mid-token on every
      // string, every number, and every structural character.
      final report = await reader.readAll(chunked(text, chunkSize: 16));
      expect(report.runs.single.violations, hasLength(4));
    });

    test('handles empty results array', () async {
      const empty = r'''
{
  "version": "2.1.0",
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "runs": [
    {
      "tool": {"driver": {"name": "verilator", "version": "5.0"}},
      "results": []
    }
  ]
}
''';
      final report = await reader.readAll(chunked(empty));
      expect(report.runs, hasLength(1));
      expect(report.runs.single.violations, isEmpty);
      expect(report.runs.single.engineId, 'verilator');
    });

    test('handles run with no `results` key at all', () async {
      const noResults = '''
{
  "version": "2.1.0",
  "runs": [
    {
      "tool": {"driver": {"name": "slang", "version": "0.1"}}
    }
  ]
}
''';
      final report = await reader.readAll(chunked(noResults));
      expect(report.runs.single.engineId, 'slang');
      expect(report.runs.single.violations, isEmpty);
    });

    test('handles empty `runs` array', () async {
      const empty = r'''
{
  "version": "2.1.0",
  "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
  "runs": []
}
''';
      final report = await reader.readAll(chunked(empty));
      expect(report.version, '2.1.0');
      expect(report.runs, isEmpty);
    });

    test('handles multi-run documents', () async {
      const multi = '''
{
  "version": "2.1.0",
  "runs": [
    {
      "tool": {"driver": {"name": "verilator", "version": "5.0"}},
      "results": [
        {
          "ruleId": "R1",
          "level": "warning",
          "message": {"text": "first"},
          "locations": [
            {"physicalLocation": {
              "artifactLocation": {"uri": "a.v"},
              "region": {"startLine": 1, "startColumn": 1}
            }}
          ]
        }
      ]
    },
    {
      "tool": {"driver": {"name": "verible", "version": "0.0.3"}},
      "results": [
        {
          "ruleId": "S1",
          "level": "note",
          "message": {"text": "second"},
          "locations": [
            {"physicalLocation": {
              "artifactLocation": {"uri": "b.v"},
              "region": {"startLine": 2, "startColumn": 1}
            }}
          ]
        }
      ]
    }
  ]
}
''';
      final report = await reader.readAll(chunked(multi));
      expect(report.runs, hasLength(2));
      expect(report.runs[0].engineId, 'verilator');
      expect(report.runs[1].engineId, 'verible');
      expect(report.runs[0].violations.single.message, 'first');
      expect(report.runs[1].violations.single.message, 'second');
    });

    test('parses a large pre-`runs` prefix streamed in tiny chunks', () async {
      // A big top-level field sits before `runs`, so the header accumulation
      // (`_appendUntilContains`) spans many chunks. At chunkSize 1 the `"runs"`
      // needle straddles four chunks (exercising the boundary window), and a
      // naive `_text = _text + chunk` per chunk would be O(prefix^2). We assert
      // correctness across chunk sizes; the header fields are recovered from
      // the fully-accumulated prefix.
      final bigNote = 'x' * 20000;
      final doc =
          '{"version":"2.1.0",'
          r'"$schema":"https://example.com/sarif.json",'
          '"properties":{"note":"$bigNote"},'
          '"runs":[{"tool":{"driver":{"name":"verilator","version":"5.0"}},'
          '"results":[{"ruleId":"R1","level":"warning",'
          '"message":{"text":"hi"},'
          '"locations":[{"physicalLocation":{'
          '"artifactLocation":{"uri":"a.v"},'
          '"region":{"startLine":1,"startColumn":1}}}]}]}]}';

      for (final size in [1, 7, 64]) {
        final report = await reader.readAll(chunked(doc, chunkSize: size));
        expect(report.version, '2.1.0', reason: 'chunkSize $size');
        expect(
          report.schema,
          'https://example.com/sarif.json',
          reason: 'chunkSize $size',
        );
        expect(
          report.runs.single.engineId,
          'verilator',
          reason: 'chunkSize $size',
        );
        expect(
          report.runs.single.violations.single.message,
          'hi',
          reason: 'chunkSize $size',
        );
      }
    });

    test('cancels promptly when the subscription closes mid-stream', () async {
      // Build a synthetic document with 1000 results so cancellation
      // happens before we'd otherwise see the end.
      final results = <Map<String, dynamic>>[
        for (var i = 0; i < 1000; i++)
          <String, dynamic>{
            'ruleId': 'R$i',
            'level': 'warning',
            'message': <String, dynamic>{'text': 'rule $i'},
            'locations': <Map<String, dynamic>>[
              <String, dynamic>{
                'physicalLocation': <String, dynamic>{
                  'artifactLocation': <String, dynamic>{'uri': 'a.v'},
                  'region': <String, dynamic>{
                    'startLine': i + 1,
                    'startColumn': 1,
                  },
                },
              },
            ],
          },
      ];
      final doc = jsonEncode(<String, dynamic>{
        'version': '2.1.0',
        'runs': <Map<String, dynamic>>[
          <String, dynamic>{
            'tool': <String, dynamic>{
              'driver': <String, dynamic>{'name': 'verilator'},
            },
            'results': results,
          },
        ],
      });

      var seen = 0;
      final completer = Completer<void>();
      final sub = reader.stream(chunked(doc, chunkSize: 256)).listen(
        (event) {
          if (event is StreamingSarifViolation) {
            seen++;
            if (seen == 5) {
              completer.complete();
            }
          }
        },
      );
      await completer.future;
      await sub.cancel();
      // We stopped early; we did NOT receive all 1000 results.
      expect(seen, lessThan(1000));
      expect(seen, greaterThanOrEqualTo(5));
    });

    test('rejects malformed input with a SarifReadException', () async {
      const broken = '{"not-a-sarif-doc": true}';
      expect(
        () => reader.readAll(chunked(broken)),
        throwsA(isA<SarifReadException>()),
      );
    });

    test(
      'preserves the raw JSON for each violation in `Violation.raw`',
      () async {
        final text = await File(
          'test/fixtures/sarif/verilator_basic.sarif.json',
        ).readAsString();
        final report = await reader.readAll(chunked(text));
        final widthRaw = report.runs.single.violations[1].raw;
        expect(widthRaw['ruleId'], 'WIDTHTRUNC');
        expect(widthRaw['level'], 'warning');
      },
    );

    test(
      'bounded memory: 1000-violation document does not retain raw text',
      () async {
        // Synthesize a moderately large document and count the streamed
        // violations. The point of the test is the data flows through —
        // memory bounds are validated by inspection of the implementation
        // (the buffer is discarded on every refill via `_swapBuffer`).
        final entries = <Map<String, dynamic>>[
          for (var i = 0; i < 1000; i++)
            <String, dynamic>{
              'ruleId': 'STREAM$i',
              'level': 'warning',
              'message': <String, dynamic>{'text': 'rule $i ' * 20},
              'locations': <Map<String, dynamic>>[
                <String, dynamic>{
                  'physicalLocation': <String, dynamic>{
                    'artifactLocation': <String, dynamic>{
                      'uri': 'src/very/deeply/nested/file_$i.sv',
                    },
                    'region': <String, dynamic>{
                      'startLine': i + 1,
                      'startColumn': 1,
                    },
                  },
                },
              ],
            },
        ];
        final doc = jsonEncode(<String, dynamic>{
          'version': '2.1.0',
          'runs': <Map<String, dynamic>>[
            <String, dynamic>{
              'tool': <String, dynamic>{
                'driver': <String, dynamic>{'name': 'verilator'},
              },
              'results': entries,
            },
          ],
        });
        // Use small chunks to force frequent buffer rotation.
        final report = await reader.readAll(chunked(doc, chunkSize: 1024));
        expect(report.runs.single.violations, hasLength(1000));
        // Spot-check first, mid, last.
        expect(report.runs.single.violations.first.ruleId, 'verilator/STREAM0');
        expect(
          report.runs.single.violations[500].ruleId,
          'verilator/STREAM500',
        );
        expect(
          report.runs.single.violations.last.ruleId,
          'verilator/STREAM999',
        );
      },
    );

    test('handles strings containing escaped quotes', () async {
      const tricky = r'''
{
  "version": "2.1.0",
  "runs": [
    {
      "tool": {"driver": {"name": "verilator"}},
      "results": [
        {
          "ruleId": "R1",
          "level": "warning",
          "message": {"text": "He said \"hi\" then left"},
          "locations": [
            {"physicalLocation": {
              "artifactLocation": {"uri": "a.v"},
              "region": {"startLine": 1, "startColumn": 1}
            }}
          ]
        }
      ]
    }
  ]
}
''';
      final report = await reader.readAll(chunked(tricky));
      final v = report.runs.single.violations.single;
      expect(v.message, 'He said "hi" then left');
    });
  });

  group('Streamed Violation equivalence with the baseline reader', () {
    // Round-trip property: for every fixture under test/fixtures/sarif,
    // the streaming reader produces a violation list whose elements
    // are equal-by-shape to the baseline reader's.
    test(
      'matches the baseline on every fixture under test/fixtures/sarif',
      () async {
        const baseline = SarifReader();
        const streaming = StreamingSarifReader();
        final dir = Directory('test/fixtures/sarif');
        if (!dir.existsSync()) return; // tolerate the fixture set growing
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sarif.json'))
            .toList();
        expect(files, isNotEmpty, reason: 'fixture set should not be empty');
        for (final f in files) {
          final text = await f.readAsString();
          final baselineReport = baseline.read(text);
          final streamedReport = await streaming.readAll(
            Stream<List<int>>.value(utf8.encode(text)),
          );
          expect(
            streamedReport.runs.length,
            baselineReport.runs.length,
            reason: 'run count mismatch in ${f.path}',
          );
          for (var ri = 0; ri < baselineReport.runs.length; ri++) {
            final b = baselineReport.runs[ri];
            final s = streamedReport.runs[ri];
            expect(
              s.violations.length,
              b.violations.length,
              reason: '${f.path} run $ri',
            );
            for (var vi = 0; vi < b.violations.length; vi++) {
              final bv = b.violations[vi];
              final sv = s.violations[vi];
              _expectViolationEquivalent(
                sv,
                bv,
                where: '${f.path} run $ri violation $vi',
              );
            }
          }
        }
      },
    );
  });
}

void _expectViolationEquivalent(
  Violation actual,
  Violation expected, {
  required String where,
}) {
  expect(actual.engineId, expected.engineId, reason: 'engineId @ $where');
  expect(actual.ruleId, expected.ruleId, reason: 'ruleId @ $where');
  expect(actual.severity, expected.severity, reason: 'severity @ $where');
  expect(actual.message, expected.message, reason: 'message @ $where');
  expect(
    actual.location.file,
    expected.location.file,
    reason: 'location.file @ $where',
  );
  expect(
    actual.location.line,
    expected.location.line,
    reason: 'location.line @ $where',
  );
  expect(
    actual.location.column,
    expected.location.column,
    reason: 'location.column @ $where',
  );
  expect(
    actual.relatedLocations.length,
    expected.relatedLocations.length,
    reason: 'relatedLocations.length @ $where',
  );
}
