// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/headless/headless_export_writer.dart';
import 'package:path/path.dart' as p;

void main() {
  const writer = HeadlessExportWriter();
  final root = p.normalize(p.absolute(p.join('build', 'fake-repo-root')));

  Violation violation({
    String file = 'rtl/top.sv',
    String rule = 'verilator/WIDTHTRUNC',
    Severity severity = Severity.warning,
    List<String> related = const <String>[],
    Map<String, dynamic> raw = const <String, dynamic>{},
  }) {
    return Violation(
      engineId: 'verilator',
      ruleId: rule,
      severity: severity,
      message: 'a finding',
      location: SourceLocation(
        file: p.isAbsolute(file) ? file : p.join(root, file),
        line: 12,
        column: 3,
      ),
      relatedLocations: <SourceLocation>[
        for (final r in related)
          SourceLocation(file: p.join(root, r), line: 1, column: 1),
      ],
      raw: raw,
    );
  }

  Map<String, dynamic> render(List<Violation> violations) {
    final json = writer.renderSarif(
      violations: violations,
      projectRoot: root,
      runId: 'my-project',
      exportTime: DateTime.utc(2026, 7, 21, 12),
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  group('SARIF shaped for GitHub code scanning', () {
    test('declares the 2.1.0 version and schema', () {
      final doc = render(<Violation>[violation()]);
      expect(doc['version'], '2.1.0');
      expect(doc[r'$schema'], contains('sarif-2.1.0'));
    });

    test('paths under the project root become repo-relative', () {
      // Uploading absolute developer-machine paths produces an
      // accepted-but-useless SARIF: the alerts land with no line
      // annotations because nothing in the checked-out repo matches.
      final doc = render(<Violation>[violation()]);
      final loc = ((doc['runs'] as List).first as Map)['results'] as List;
      final artifact =
          ((((loc.first as Map)['locations'] as List).first
                      as Map)['physicalLocation']
                  as Map)['artifactLocation']
              as Map;
      // A URI reference: `/` on every host, Windows included.
      expect(artifact['uri'], 'rtl/top.sv');
      expect(artifact['uriBaseId'], HeadlessExportWriter.srcRootBaseId);
    });

    test('declares originalUriBaseIds so the base is interpretable', () {
      final doc = render(<Violation>[violation()]);
      final run = (doc['runs'] as List).first as Map;
      final bases = run['originalUriBaseIds'] as Map;
      expect(bases.keys, contains(HeadlessExportWriter.srcRootBaseId));
      final uri = (bases[HeadlessExportWriter.srcRootBaseId] as Map)['uri'];
      expect('$uri', startsWith('file:///'));
      expect('$uri', endsWith('/'));
    });

    test('a path outside the project root stays absolute', () {
      // SARIF's `uri` is a URI reference; consumers reject `../..`
      // traversal out of the declared base, so an out-of-tree location
      // must not be relativized into one.
      final outside = p.normalize(p.absolute(p.join('build', 'elsewhere.sv')));
      final doc = render(<Violation>[violation(file: outside)]);
      final artifact =
          (((((doc['runs'] as List).first as Map)['results'] as List).first
                          as Map)['locations']
                      as List)
                  .first
              as Map;
      expect(
        ((artifact['physicalLocation'] as Map)['artifactLocation']
            as Map)['uri'],
        outside,
      );
    });

    test('relatedLocations are relativized too', () {
      final doc = render(<Violation>[
        violation(related: <String>['rtl/decl.sv']),
      ]);
      final result =
          (((doc['runs'] as List).first as Map)['results'] as List).first
              as Map;
      final related = (result['relatedLocations'] as List).first as Map;
      expect(
        ((related['physicalLocation'] as Map)['artifactLocation']
            as Map)['uri'],
        'rtl/decl.sv',
      );
    });

    test('the preserved raw SARIF bag cannot leak absolute paths', () {
      // `SarifWriter` spreads `Violation.raw` into the result before
      // overwriting the structured fields. The raw bag holds the
      // ORIGINAL absolute locations, so anything we do not explicitly
      // overwrite would ship a developer's home directory in the
      // uploaded artifact.
      final doc = render(<Violation>[
        violation(
          raw: <String, dynamic>{
            'partialFingerprints': <String, dynamic>{
              'absolutePath': '/Users/someone/secret/rtl/top.sv',
            },
          },
        ),
      ]);
      expect(jsonEncode(doc), isNot(contains('/Users/someone')));
    });

    test('a suppressed violation is exported with a suppressions marker, '
        'and its waiver id carries no absolute path', () {
      final pragma = violation().copyWith(
        suppression: Waiver(
          id: 'pragma:${p.join(root, 'rtl', 'top.sv')}:10-14:WIDTHTRUNC',
          ruleId: 'verilator/WIDTHTRUNC',
          filePath: p.join(root, 'rtl', 'top.sv'),
          lineStart: 10,
          lineEnd: 14,
          reason: 'Inline pragma `// verilator lint_off WIDTHTRUNC`',
          author: 'source',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      final doc = render(<Violation>[pragma, violation(rule: 'verilator/X')]);
      final results =
          ((doc['runs'] as List).single as Map<String, dynamic>)['results']
              as List;
      final waived = results.first as Map<String, dynamic>;
      final open = results.last as Map<String, dynamic>;
      final suppression =
          (waived['suppressions'] as List).single as Map<String, dynamic>;
      expect(suppression['kind'], 'inSource');
      expect(open.containsKey('suppressions'), isFalse);
      expect(jsonEncode(waived), isNot(contains(root)));
    });

    test('automationDetails.id is stable across runs', () {
      // GitHub groups uploads into a category by this id. A timestamp in
      // it would make every CI upload a brand-new category instead of
      // superseding the previous one.
      final a = render(<Violation>[violation()]);
      final b = render(<Violation>[violation()]);
      final idA = ((a['runs'] as List).first as Map)['automationDetails'];
      final idB = ((b['runs'] as List).first as Map)['automationDetails'];
      expect(idA, idB);
      expect((idA! as Map)['id'], 'my-project/verilator');
    });

    test('one SARIF run per engine', () {
      final doc = render(<Violation>[
        violation(),
        Violation(
          engineId: 'verible',
          ruleId: 'verible/line-length',
          severity: Severity.note,
          message: 'too long',
          location: SourceLocation(
            file: p.join(root, 'rtl', 'top.sv'),
            line: 1,
            column: 1,
          ),
        ),
      ]);
      final runs = doc['runs'] as List;
      expect(runs, hasLength(2));
      expect(
        runs.map((r) => ((r as Map)['tool'] as Map)['driver']),
        containsAll(<Object>[
          <String, dynamic>{'name': 'verilator'},
          <String, dynamic>{'name': 'verible'},
        ]),
      );
    });

    test('severity maps onto SARIF levels', () {
      for (final entry in <Severity, String>{
        Severity.fatal: 'error',
        Severity.error: 'error',
        Severity.warning: 'warning',
        Severity.note: 'note',
        Severity.none: 'none',
      }.entries) {
        final doc = render(<Violation>[violation(severity: entry.key)]);
        final result =
            (((doc['runs'] as List).first as Map)['results'] as List).first
                as Map;
        expect(result['level'], entry.value, reason: '${entry.key}');
      }
    });
  });

  group('write()', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lintcrux_export_');
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('creates missing parent directories', () async {
      final out = p.join(tmp.path, 'a', 'b', 'lint.sarif');
      await writer.write(
        violations: <Violation>[violation()],
        format: 'sarif',
        outputPath: out,
        projectRoot: root,
        runId: 'x',
      );
      expect(File(out).existsSync(), isTrue);
    });

    test('emits each non-SARIF format through ViolationExporters', () async {
      for (final entry in <String, String>{
        'json': '"ruleId"',
        'csv': 'severity,engine,rule',
        'html': '<table',
      }.entries) {
        final out = p.join(tmp.path, 'lint.${entry.key}');
        await writer.write(
          violations: <Violation>[violation()],
          format: entry.key,
          outputPath: out,
          projectRoot: root,
          runId: 'x',
        );
        expect(
          File(out).readAsStringSync(),
          contains(entry.value),
          reason: entry.key,
        );
      }
    });

    test('an unknown format throws rather than writing nothing', () {
      expect(
        () => writer.write(
          violations: <Violation>[violation()],
          format: 'xml',
          outputPath: p.join(tmp.path, 'lint.xml'),
          projectRoot: root,
          runId: 'x',
        ),
        throwsA(isA<HeadlessExportException>()),
      );
    });
  });
}
