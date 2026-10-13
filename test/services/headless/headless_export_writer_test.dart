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

  // The fake root sits inside this repository, so it is named outright:
  // otherwise the writer would find the checkout's own `.git` above it and
  // relativize against that.
  Map<String, dynamic> render(List<Violation> violations) {
    final json = writer.renderSarif(
      violations: violations,
      projectRoot: root,
      sarifRoot: root,
      runId: 'my-project',
      exportTime: DateTime.utc(2026, 7, 21, 12),
    );
    return jsonDecode(json) as Map<String, dynamic>;
  }

  Map<String, dynamic> firstResult(Map<String, dynamic> doc) =>
      (((doc['runs'] as List).first as Map)['results'] as List).first
          as Map<String, dynamic>;

  String uriOf(Map<String, dynamic> result) =>
      ((((result['locations'] as List).first as Map)['physicalLocation']
                  as Map)['artifactLocation']
              as Map)['uri']
          as String;

  group('the SARIF root', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('lintcrux_sarif_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Map<String, dynamic> renderIn({
      required String projectRoot,
      required String file,
      String? sarifRoot,
    }) {
      final json = writer.renderSarif(
        violations: <Violation>[
          Violation(
            engineId: 'verilator',
            ruleId: 'verilator/UNUSEDSIGNAL',
            severity: Severity.warning,
            message: 'a finding',
            location: SourceLocation(file: file, line: 1, column: 1),
          ),
        ],
        projectRoot: projectRoot,
        sarifRoot: sarifRoot,
        runId: 'demo',
      );
      return jsonDecode(json) as Map<String, dynamic>;
    }

    String srcRoot(Map<String, dynamic> doc) =>
        ((((doc['runs'] as List).first as Map)['originalUriBaseIds']
                    as Map)[HeadlessExportWriter.srcRootBaseId]
                as Map)['uri']
            as String;

    test('is the enclosing git repository, not the project folder', () {
      // GitHub resolves a relative URI against the repository root and
      // ignores originalUriBaseIds. A project kept in `rtl/` recorded every
      // alert at `alu.sv` instead of `rtl/alu.sv`, so the PR check found
      // no alerts in the changed lines.
      final repo = Directory(p.join(tmp.path, 'repo'))..createSync();
      Directory(p.join(repo.path, '.git')).createSync();
      final rtl = Directory(p.join(repo.path, 'rtl'))..createSync();
      final doc = renderIn(
        projectRoot: rtl.path,
        file: p.join(rtl.path, 'alu.sv'),
      );
      expect(uriOf(firstResult(doc)), 'rtl/alu.sv');
      expect(srcRoot(doc), Uri.directory(repo.path).toString());
    });

    test('a .git file (submodule, linked work tree) marks the root too', () {
      final repo = Directory(p.join(tmp.path, 'repo'))..createSync();
      File(p.join(repo.path, '.git')).writeAsStringSync('gitdir: ../x\n');
      final rtl = Directory(p.join(repo.path, 'rtl'))..createSync();
      final doc = renderIn(
        projectRoot: rtl.path,
        file: p.join(rtl.path, 'alu.sv'),
      );
      expect(uriOf(firstResult(doc)), 'rtl/alu.sv');
    });

    test('--sarif-root names it outright', () {
      final repo = Directory(p.join(tmp.path, 'repo'))..createSync();
      Directory(p.join(repo.path, '.git')).createSync();
      final rtl = Directory(p.join(repo.path, 'rtl'))..createSync();
      final doc = renderIn(
        projectRoot: rtl.path,
        file: p.join(rtl.path, 'alu.sv'),
        sarifRoot: rtl.path,
      );
      expect(uriOf(firstResult(doc)), 'alu.sv');
      expect(srcRoot(doc), Uri.directory(rtl.path).toString());
    });

    test('with no repository anywhere above, the project root stands', () {
      final rtl = Directory(p.join(tmp.path, 'rtl'))..createSync();
      final doc = renderIn(
        projectRoot: rtl.path,
        file: p.join(rtl.path, 'alu.sv'),
      );
      expect(uriOf(firstResult(doc)), 'alu.sv');
      expect(srcRoot(doc), Uri.directory(rtl.path).toString());
    });

    test('findRepositoryRoot answers null off any repository', () {
      expect(HeadlessExportWriter.findRepositoryRoot(tmp.path), isNull);
    });
  });

  group('SARIF shaped for GitHub code scanning', () {
    test('every rule has a descriptor and each result points at it', () {
      final doc = render(<Violation>[
        violation(),
        violation(rule: 'verilator/UNUSEDSIGNAL'),
      ]);
      final run = (doc['runs'] as List).first as Map<String, dynamic>;
      final rules =
          ((run['tool'] as Map)['driver'] as Map)['rules'] as List<dynamic>;
      expect(rules.map((r) => (r as Map)['id']), [
        'WIDTHTRUNC',
        'UNUSEDSIGNAL',
      ]);
      final results = run['results'] as List;
      expect(results.map((r) => (r as Map)['ruleIndex']), [0, 1]);
      final first = rules.first as Map<String, dynamic>;
      expect(first['name'], 'WIDTHTRUNC');
      expect((first['shortDescription'] as Map)['text'], 'WIDTHTRUNC');
      expect(first['helpUri'], 'https://verilator.org/warn/WIDTHTRUNC');
      expect((first['defaultConfiguration'] as Map)['level'], 'warning');
    });

    test("an engine's structured data survives in properties", () {
      // A CDC finding carries the registers, domains, width and synchronizer
      // kind the crossing connects; dropping the whole bag left a consumer
      // able to see that a crossing was reported and nothing else.
      final doc = render(<Violation>[
        violation(
          raw: <String, dynamic>{
            'src_domain': 'clk_a',
            'dst_domain': 'clk_b',
            'width': 8,
            'sync_kind': 'none',
            'src_register': 'top.u_a.q',
          },
        ),
      ]);
      final props = firstResult(doc)['properties'] as Map<String, dynamic>;
      expect(props['src_domain'], 'clk_a');
      expect(props['width'], 8);
      expect(props['src_register'], 'top.u_a.q');
    });

    test('a path inside the structured data is made relative too', () {
      final doc = render(<Violation>[
        violation(
          raw: <String, dynamic>{
            'lintcrux.pragmaWaiverSourceFile': p.join(root, 'rtl', 'top.sv'),
            'nested': <String, dynamic>{
              'files': <String>[p.join(root, 'rtl', 'a.sv')],
            },
          },
        ),
      ]);
      final props = firstResult(doc)['properties'] as Map<String, dynamic>;
      expect(props['lintcrux.pragmaWaiverSourceFile'], 'rtl/top.sv');
      expect(((props['nested'] as Map)['files'] as List).single, 'rtl/a.sv');
      // The root appears once, as the declared %SRCROOT% base; no result
      // carries it.
      expect(jsonEncode(firstResult(doc)), isNot(contains(root)));
    });

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
        runs.map((r) => (((r as Map)['tool'] as Map)['driver'] as Map)['name']),
        containsAll(<Object>['verilator', 'verible']),
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
