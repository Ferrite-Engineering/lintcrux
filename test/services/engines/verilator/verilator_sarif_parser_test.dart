// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The SARIF reader against real Verilator output. Every expectation here is
// the text transcript Verilator printed in the same run as the SARIF (the
// fixtures' own captured stderr), parsed by the text parser that has always
// read it. Nothing is taken from the SARIF reader's output. See
// test/fixtures/engines/verilator/sarif/PROVENANCE.md.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/verilator/verilator_parser.dart';
import 'package:lintcrux/services/engines/verilator/verilator_sarif_parser.dart';

const _dir = 'test/fixtures/sarif/verilator_capture';
const _root = '/work/sarif_design';
const _tags = <String>[
  'oss-cad-2026-08-21',
  'oss-cad-2026-09-21',
  'oss-cad-2026-10-21',
];

/// The fixture, with `@ROOT@` (the capture directory, kept out of the
/// committed files) put back as [_root].
String _read(String name) =>
    File('$_dir/$name').readAsStringSync().replaceAll('@ROOT@', _root);

List<Violation> _fromText(String tag) => VerilatorParser(
  rootPath: _root,
).parse(_read('$tag.stderr.txt').split('\n'));

List<Violation>? _fromSarif(String source) =>
    VerilatorSarifParser(rootPath: _root).parse(source);

void main() {
  group('VerilatorSarifParser on captured Verilator output', () {
    for (final tag in _tags) {
      group(tag, () {
        test('reports the findings the text transcript reports', () {
          final text = _fromText(tag);
          final sarif = _fromSarif(_read('$tag.sarif'));
          expect(sarif, isNotNull);
          // The transcript names six diagnostics: the summary line is not
          // one of them.
          expect(text, hasLength(6));
          expect(sarif, equals(text));
          expect(
            sarif!.map((v) => v.ruleId),
            <String>[
              'verilator/WIDTHTRUNC',
              'verilator/MULTIDRIVEN',
              'verilator/UNUSEDSIGNAL',
              'verilator/UNUSEDSIGNAL',
              'verilator/UNDRIVEN',
              'verilator/MULTIDRIVEN',
            ],
          );
        });

        test('keeps the continuation block the inspector renders', () {
          final text = _fromText(tag);
          final sarif = _fromSarif(_read('$tag.sarif'))!;
          for (var i = 0; i < text.length; i++) {
            expect(
              sarif[i].raw['verilator.continuation'],
              text[i].raw['verilator.continuation'],
              reason: 'result $i',
            );
          }
        });

        test('carries no fixes, because this Verilator writes none', () {
          final sarif = _fromSarif(_read('$tag.sarif'))!;
          expect(sarif.where((v) => v.raw.containsKey('fixes')), isEmpty);
        });
      });
    }
  });

  group('VerilatorSarifParser edge cases', () {
    final real = _read('oss-cad-2026-10-21.sarif');

    test('a missing comma (the 5.052 document) is not usable', () {
      final broken = real.replaceFirst(
        '},\n            "invocations"',
        '}\n            "invocations"',
      );
      expect(broken, isNot(real), reason: 'the fixture changed shape');
      expect(_fromSarif(broken), isNull);
    });

    test('a truncated document is not usable', () {
      expect(_fromSarif(real.substring(0, real.length ~/ 2)), isNull);
    });

    test('JSON that is not a SARIF log is not usable', () {
      expect(_fromSarif('[]'), isNull);
      expect(_fromSarif('{"runs": []}'), isNull);
      expect(_fromSarif('{"runs": [{}]}'), isNull);
      expect(_fromSarif(''), isNull);
    });

    test('a clean run is a usable document with no findings', () {
      final doc = jsonDecode(real) as Map<String, dynamic>;
      ((doc['runs'] as List).first as Map<String, dynamic>)['results'] =
          <Object>[];
      expect(_fromSarif(jsonEncode(doc)), isEmpty);
    });

    test('a result without a ruleId is UNCLASSIFIED', () {
      final doc = jsonDecode(real) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List;
      (results.first as Map<String, dynamic>).remove('ruleId');
      final out = _fromSarif(jsonEncode(doc))!;
      expect(out.first.ruleId, 'verilator/UNCLASSIFIED');
    });

    test('level maps to severity', () {
      final doc = jsonDecode(real) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List;
      (results[0] as Map<String, dynamic>)['level'] = 'error';
      (results[1] as Map<String, dynamic>)['level'] = 'none';
      final out = _fromSarif(jsonEncode(doc))!;
      expect(out[0].severity, Severity.error);
      expect(out[1].severity, Severity.note);
      expect(out[2].severity, Severity.warning);
    });

    test('fixes are kept verbatim in raw, for the export round trip', () {
      // Hand-built to the SARIF 2.1.0 `fix` shape: no Verilator release
      // writes `fixes` yet, so there is no captured output to use.
      final fix = <String, dynamic>{
        'description': <String, dynamic>{'text': 'Disable WIDTHTRUNC'},
        'artifactChanges': <Object>[
          <String, dynamic>{
            'artifactLocation': <String, dynamic>{
              'uri': 'file://$_root/sarif_design.sv',
            },
            'replacements': <Object>[
              <String, dynamic>{
                'deletedRegion': <String, dynamic>{
                  'startLine': 21,
                  'startColumn': 1,
                  'endColumn': 1,
                },
                'insertedContent': <String, dynamic>{
                  'text': '  /* verilator lint_off WIDTHTRUNC */\n',
                },
              },
            ],
          },
        ],
      };
      final doc = jsonDecode(real) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List;
      (results.first as Map<String, dynamic>)['fixes'] = <Object>[fix];
      final out = _fromSarif(jsonEncode(doc))!;
      expect(out.first.raw['fixes'], <Object>[fix]);
      expect(out[1].raw.containsKey('fixes'), isFalse);
      // Findings are unchanged by the presence of fixes.
      expect(out, equals(_fromText('oss-cad-2026-10-21')));
    });

    test('a project under a symlinked directory keeps its own path form', () {
      final out = VerilatorSarifParser(
        rootPath: '/link/proj',
        rootRealPath: _root,
      ).parse(real)!;
      expect(out.first.location.file, '/link/proj/sarif_design.sv');
      expect(
        out.first.location,
        const SourceLocation(
          file: '/link/proj/sarif_design.sv',
          line: 21,
          column: 12,
        ),
      );
    });

    test(
      'an absolute path outside the root is kept, as in the text path',
      () {
        final out = VerilatorSarifParser(rootPath: '/elsewhere').parse(real)!;
        // Absolute paths are kept, out-of-tree or not.
        expect(out.first.location.file, '$_root/sarif_design.sv');
      },
    );
  });
}
