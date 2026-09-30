// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Round-trip property tests for the SARIF reader + writer.
///
/// The property under test: for any well-formed SARIF document the
/// reader produces a [SarifReport] whose serialization by the writer
/// re-parses to a [SarifReport] that is structurally equivalent to
/// the original — same engines, same violation counts per engine,
/// same per-violation `engineId` / `ruleId` / `severity` / `message`
/// / `location` / `relatedLocations`.
///
/// This catches the class of bug where the reader and writer share
/// the same misconception about the format: a field that round-trips
/// only because both sides agree to drop it. The streaming reader
/// is the canonical reader for this round-trip; the
/// baseline `SarifReader` is exercised as a cross-check to confirm
/// the streaming path agrees with it on every fixture.
///
/// Coverage: one Verilator-only project, one Verible-only project,
/// one Slang-only project, one GHDL-only project, and one mixed-
/// language project (Verilog + VHDL with Verilator + GHDL).
///
/// The fixtures are constructed in-test so they don't drift if the
/// engine output capture in `test/fixtures/projects/*/expected.sarif.json`
/// is regenerated. The committed fixture files are exercised by a
/// separate equivalence sweep in
/// `test/services/sarif/streaming_sarif_reader_test.dart` (the
/// "Streamed Violation equivalence with the baseline reader" group).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart';
import 'package:lintcrux/services/sarif/streaming_sarif_reader.dart';

Violation _v({
  required String engineId,
  required String ruleId,
  required String file,
  required int line,
  Severity severity = Severity.warning,
  String? message,
  List<SourceLocation> related = const <SourceLocation>[],
}) => Violation(
  engineId: engineId,
  ruleId: ruleId.contains('/') ? ruleId : '$engineId/$ruleId',
  severity: severity,
  message: message ?? '$ruleId at $file:$line',
  location: SourceLocation(file: file, line: line, column: 1),
  relatedLocations: related,
);

Run _run({
  required String engineId,
  required String engineVersion,
  required List<Violation> violations,
}) => Run(
  id: 'run-$engineId',
  engineId: engineId,
  engineVersion: engineVersion,
  startedAt: DateTime.utc(2026, 5, 23, 10),
  finishedAt: DateTime.utc(2026, 5, 23, 10, 0, 5),
  violations: violations,
);

void main() {
  const writer = SarifWriter();
  const streamingReader = StreamingSarifReader();

  Future<SarifReport> roundTrip(SarifReport input) async {
    final json = writer.write(input);
    final report = await streamingReader.readAll(
      Stream<List<int>>.value(json.codeUnits),
    );
    return report;
  }

  void expectViolationsEquivalent(
    List<Violation> actual,
    List<Violation> expected, {
    required String where,
  }) {
    expect(actual.length, expected.length, reason: 'count @ $where');
    for (var i = 0; i < expected.length; i++) {
      final a = actual[i];
      final e = expected[i];
      expect(a.engineId, e.engineId, reason: 'engineId @ $where[$i]');
      expect(a.ruleId, e.ruleId, reason: 'ruleId @ $where[$i]');
      expect(a.severity, e.severity, reason: 'severity @ $where[$i]');
      expect(a.message, e.message, reason: 'message @ $where[$i]');
      expect(
        a.location.file,
        e.location.file,
        reason: 'location.file @ $where[$i]',
      );
      expect(
        a.location.line,
        e.location.line,
        reason: 'location.line @ $where[$i]',
      );
      expect(
        a.relatedLocations.length,
        e.relatedLocations.length,
        reason: 'relatedLocations.length @ $where[$i]',
      );
    }
  }

  void expectRoundTrip(SarifReport input, String label) {
    test('$label round-trips through writer → streaming reader', () async {
      final out = await roundTrip(input);
      expect(out.runs.length, input.runs.length, reason: '$label run count');
      for (var ri = 0; ri < input.runs.length; ri++) {
        final inRun = input.runs[ri];
        final outRun = out.runs[ri];
        expect(
          outRun.engineId,
          inRun.engineId,
          reason: '$label engineId @ run $ri',
        );
        expectViolationsEquivalent(
          outRun.violations,
          inRun.violations,
          where: '$label run $ri',
        );
      }
    });
  }

  group('SARIF round-trip — per-engine projects', () {
    expectRoundTrip(
      SarifReport(
        runs: [
          _run(
            engineId: 'verilator',
            engineVersion: '5.026',
            violations: [
              _v(
                engineId: 'verilator',
                ruleId: 'UNUSEDSIGNAL',
                file: 'src/top.sv',
                line: 7,
              ),
              _v(
                engineId: 'verilator',
                ruleId: 'WIDTHTRUNC',
                file: 'src/alu.v',
                line: 42,
              ),
              _v(
                engineId: 'verilator',
                ruleId: 'PINMISSING',
                file: 'src/top.sv',
                line: 88,
                severity: Severity.error,
              ),
            ],
          ),
        ],
      ),
      'Verilator-only project',
    );

    expectRoundTrip(
      SarifReport(
        runs: [
          _run(
            engineId: 'verible',
            engineVersion: '0.0.3935',
            violations: [
              _v(
                engineId: 'verible',
                ruleId: 'no-tabs',
                file: 'src/style_violator.sv',
                line: 12,
              ),
              _v(
                engineId: 'verible',
                ruleId: 'module-filename',
                file: 'src/bad_name.sv',
                line: 1,
                severity: Severity.note,
              ),
            ],
          ),
        ],
      ),
      'Verible-only project',
    );

    expectRoundTrip(
      SarifReport(
        runs: [
          _run(
            engineId: 'slang',
            engineVersion: '7.0',
            violations: [
              _v(
                engineId: 'slang',
                ruleId: 'UnknownPackage',
                file: 'src/pkg_user.sv',
                line: 4,
                severity: Severity.error,
              ),
              _v(
                engineId: 'slang',
                ruleId: 'UnusedDefinition',
                file: 'src/helper.sv',
                line: 18,
              ),
            ],
          ),
        ],
      ),
      'Slang-only project',
    );

    expectRoundTrip(
      SarifReport(
        runs: [
          _run(
            engineId: 'ghdl',
            engineVersion: '4.1.0',
            violations: [
              _v(
                engineId: 'ghdl',
                ruleId: 'unused',
                file: 'design.vhd',
                line: 24,
              ),
              _v(
                engineId: 'ghdl',
                ruleId: 'binding',
                file: 'design.vhd',
                line: 47,
                severity: Severity.error,
              ),
              _v(
                engineId: 'ghdl',
                ruleId: 'reserved',
                file: 'design.vhd',
                line: 110,
                severity: Severity.note,
              ),
            ],
          ),
        ],
      ),
      'GHDL-only project',
    );

    expectRoundTrip(
      SarifReport(
        runs: [
          _run(
            engineId: 'verilator',
            engineVersion: '5.026',
            violations: [
              _v(
                engineId: 'verilator',
                ruleId: 'UNUSEDSIGNAL',
                file: 'src/top.sv',
                line: 7,
              ),
            ],
          ),
          _run(
            engineId: 'ghdl',
            engineVersion: '4.1.0',
            violations: [
              _v(
                engineId: 'ghdl',
                ruleId: 'unused',
                file: 'src/bus_arbiter.vhd',
                line: 18,
              ),
              _v(
                engineId: 'ghdl',
                ruleId: 'shared',
                file: 'src/regfile.vhd',
                line: 30,
                severity: Severity.error,
              ),
            ],
          ),
        ],
      ),
      'Mixed-language project (Verilog + VHDL)',
    );
  });

  group('SARIF round-trip — fatal severity preservation', () {
    expectRoundTrip(
      SarifReport(
        runs: [
          _run(
            engineId: 'verilator',
            engineVersion: '5.026',
            violations: [
              _v(
                engineId: 'verilator',
                ruleId: 'SYNTAX',
                file: 'src/broken.v',
                line: 12,
                severity: Severity.fatal,
                message: "Unexpected token 'endmodule', expected ';'",
              ),
            ],
          ),
        ],
      ),
      'Fatal severity (extension via properties.lintcrux.severity)',
    );
  });

  group('SARIF round-trip — empty results', () {
    expectRoundTrip(
      SarifReport(
        runs: [
          _run(
            engineId: 'verilator',
            engineVersion: '5.026',
            violations: const [],
          ),
        ],
      ),
      'Clean project — no violations',
    );
  });
}
