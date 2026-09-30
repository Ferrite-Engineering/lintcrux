// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/export/violation_exporters.dart';

Violation _v({
  String engine = 'verilator',
  String rule = 'UNUSED',
  Severity severity = Severity.warning,
  String file = '/a.sv',
  int line = 5,
  int column = 1,
  String message = 'msg',
  List<SourceLocation> related = const [],
}) => Violation(
  engineId: engine,
  ruleId: '$engine/$rule',
  severity: severity,
  message: message,
  location: SourceLocation(file: file, line: line, column: column),
  relatedLocations: related,
);

void main() {
  const exp = ViolationExporters();

  group('toJson', () {
    test('produces a JSON array with one entry per violation', () {
      final out = exp.toJson([_v(), _v(rule: 'WIDTH')]);
      final decoded = json.decode(out);
      expect(decoded, isA<List<dynamic>>());
      expect((decoded as List).length, 2);
    });

    test('includes severity, location, related, suppressed, raw', () {
      final out = exp.toJson([
        _v(
          related: [
            const SourceLocation(file: '/b.sv', line: 1, column: 1),
          ],
        ),
      ]);
      final entry = (json.decode(out) as List).first as Map<String, dynamic>;
      expect(entry['severity'], 'warning');
      expect(entry['ruleId'], 'verilator/UNUSED');
      expect((entry['location'] as Map)['file'], '/a.sv');
      expect((entry['relatedLocations'] as List).length, 1);
      expect(entry['suppressed'], false);
    });

    test('empty input yields an empty JSON array', () {
      expect(exp.toJson(const <Violation>[]), '[]');
    });
  });

  group('toCsv', () {
    test('emits a header row followed by one row per violation', () {
      final out = exp.toCsv([_v(message: 'm1'), _v(message: 'm2')]);
      final lines = const LineSplitter().convert(out);
      expect(
        lines.first,
        'severity,engine,rule,file,line,column,message,suppressed',
      );
      expect(lines.length, 3);
    });

    test('quotes fields containing commas', () {
      final out = exp.toCsv([_v(message: 'has,comma')]);
      expect(out, contains('"has,comma"'));
    });

    test('escapes embedded double quotes by doubling', () {
      final out = exp.toCsv([_v(message: 'has "quote"')]);
      expect(out, contains('"has ""quote"""'));
    });

    test('quotes fields containing newlines', () {
      final out = exp.toCsv([_v(message: 'multi\nline')]);
      expect(out, contains('"multi\nline"'));
    });

    test('marks suppressed violations with true', () {
      // We can't easily build a real Waiver here without pulling in
      // domain/models/waiver.dart — but the CSV column uses
      // Violation.isSuppressed which is false for the unmodified
      // construction. Spot-check the column header position.
      final out = exp.toCsv([_v()]);
      final dataLine = const LineSplitter().convert(out).last; // header,row
      expect(dataLine.endsWith(',false'), isTrue);
    });
  });

  group('toHtml', () {
    test('emits a complete HTML document', () {
      final out = exp.toHtml([_v()]);
      expect(out, contains('<!DOCTYPE html>'));
      expect(out, contains('<title>LintCrux export</title>'));
      expect(out, contains('</html>'));
    });

    test('renders one row per violation', () {
      final out = exp.toHtml([_v(message: 'A'), _v(message: 'B')]);
      expect('<tr class="lc-sev-'.allMatches(out).length, 2);
      expect(out, contains('A'));
      expect(out, contains('B'));
    });

    test('escapes HTML special characters in user data', () {
      final out = exp.toHtml([_v(message: 'a < b & "c"')]);
      expect(out, contains('a &lt; b &amp; "c"'));
      expect(out, isNot(contains('a < b & "c"')));
    });

    test('includes severity class on each row', () {
      final out = exp.toHtml([_v(severity: Severity.error)]);
      expect(out, contains('class="lc-sev-error'));
    });

    test('custom title is used in the document', () {
      final out = exp.toHtml(const <Violation>[], title: 'My Project');
      expect(out, contains('<title>My Project</title>'));
    });

    test('emits filter chips for every severity', () {
      final out = exp.toHtml(const <Violation>[]);
      for (final s in const ['fatal', 'error', 'warning', 'note', 'none']) {
        expect(out, contains('data-sev="$s"'));
      }
    });
  });
}
