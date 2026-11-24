// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `spec/mcp/`: every tool's golden documents, one per outcome it can produce,
// against both doors.
//
// - The `lintcrux mcp` tool's `content[0]` text, with this machine's root
//   written as the goldens write it, is the golden byte for byte. The
//   goldens were written by hand from `spec/fixtures/` and the findings the
//   spec's engines report (`support/spec_engines.dart`): each count, order,
//   baseline state and waiver read off the fixture, and each `signature`
//   and the `design` fingerprint derived outside this code from the
//   documented formats (FNV-1a 64 over `rule|file|message`; SHA-256 over
//   `sha256sum` lines of the sources).
// - The same text is byte for byte what `lintcrux ... --json` writes for the
//   same arguments, and the command exits with the code the contracts'
//   table gives: LintCrux's own for lint, the suite's for rule and waivers.
// - Every golden keeps `spec/mcp/schemas/`: the envelope and its body.

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart' hide HeadlessTelemetry;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/json_schema_check.dart';
import 'support/spec_cases.dart';

Map<String, Object?> _schema(String name) =>
    jsonDecode(File(p.join('spec', 'mcp', 'schemas', name)).readAsStringSync())
        as Map<String, Object?>;

void main() {
  final spec = SpecCases.load();
  tearDownAll(spec.dispose);
  final documentSchema = _schema('document.schema.json');

  group('each golden is what the tool answers', () {
    for (final c in spec.cases) {
      test(c.golden, () async {
        final result = await spec.callTool(spec.cli(c), c);
        final content = result['content']! as List<Object?>;
        expect(content, hasLength(1));
        final item = content.single! as Map<String, Object?>;
        expect(item['type'], 'text');
        final text = item['text']! as String;
        expect(spec.normalize(text), spec.golden(c));
        final outcome = McpOutcome.fromWireName(
          (jsonDecode(text) as Map<String, Object?>)['outcome']! as String,
        );
        expect(result['isError'], outcome!.isError);
      });
    }
  });

  group('the tool and the command line write the same bytes', () {
    for (final c in spec.cases.where((c) => c.door == 'both')) {
      test(c.golden, () async {
        // One program for both doors, the real one, so nothing is normalized.
        const program = McpProgram(name: 'lintcrux', version: '9.9.9');
        final result = await spec.callTool(spec.cli(c, program: program), c);
        final toolText =
            ((result['content']! as List<Object?>).single!
                    as Map<String, Object?>)['text']!
                as String;
        final (stdoutText, code) = await spec.runCommandLine(
          spec.cli(c, program: program),
          spec.argv(c),
        );
        expect(stdoutText, toolText);
        expect(code, c.exit, reason: "the contracts' exit code");
      });
    }
  });

  group('each golden keeps the schemas', () {
    for (final c in spec.cases) {
      test(c.golden, () {
        final doc = jsonDecode(spec.golden(c)) as Map<String, Object?>;
        expect(jsonSchemaProblems(doc, documentSchema), isEmpty);
        final body = doc['body'];
        if (body != null) {
          expect(
            jsonSchemaProblems(body, _schema('${c.tool}.body.schema.json')),
            isEmpty,
          );
        }
        final errors = (doc['diagnostics']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .where((d) => d['severity'] == 'error');
        if (doc['outcome'] == 'completed') {
          expect(body, isNotNull);
          expect(errors, isEmpty);
        } else {
          expect(errors, isNotEmpty);
        }
      });
    }
  });

  test('the schema checker rejects what the schemas forbid', () {
    final good = jsonDecode(spec.golden(spec.cases.first));
    expect(jsonSchemaProblems(good, documentSchema), isEmpty);
    final extra = <String, Object?>{
      ...good as Map<String, Object?>,
      'extra': 1,
    };
    expect(jsonSchemaProblems(extra, documentSchema), isNotEmpty);
    final missing = Map<String, Object?>.of(good)..remove('engines');
    expect(jsonSchemaProblems(missing, documentSchema), isNotEmpty);
    final badOutcome = Map<String, Object?>.of(good)..['outcome'] = 'fine';
    expect(jsonSchemaProblems(badOutcome, documentSchema), isNotEmpty);
    final body = Map<String, Object?>.of(good['body']! as Map<String, Object?>)
      ..remove('engine_runs');
    expect(
      jsonSchemaProblems(body, _schema('lint.body.schema.json')),
      isNotEmpty,
    );
  });

  test('every tool has a golden for each outcome it can produce', () {
    final byTool = <String, Set<String>>{};
    for (final c in spec.cases) {
      final doc = jsonDecode(spec.golden(c)) as Map<String, Object?>;
      byTool
          .putIfAbsent(c.tool, () => <String>{})
          .add(doc['outcome']! as String);
    }
    // The open-core binary reads no licence, so no tool of it can answer
    // licence_error; lint is the only one with a gate or an engine.
    expect(byTool, <String, Set<String>>{
      'lint': <String>{
        'completed',
        'failed_gate',
        'usage_error',
        'input_error',
        'engine_error',
      },
      'rule': <String>{'completed', 'usage_error', 'input_error'},
      'waivers': <String>{'completed', 'usage_error', 'input_error'},
    });
  });

  test('every location in every golden names an absolute file:line', () {
    // The citation an agent gives is `file:line`; paths in documents are
    // absolute (contracts 2.6) and lines count from 1.
    var seen = 0;
    void walk(Object? json) {
      if (json is Map<String, Object?>) {
        if (json.containsKey('file') && json.containsKey('line')) {
          seen++;
          expect(p.posix.isAbsolute(json['file']! as String), isTrue);
          expect(json['line'], greaterThanOrEqualTo(1));
        }
        json.values.forEach(walk);
      } else if (json is List<Object?>) {
        json.forEach(walk);
      }
    }

    for (final c in spec.cases) {
      walk(jsonDecode(spec.golden(c)));
    }
    expect(seen, greaterThanOrEqualTo(10));
  });
}
