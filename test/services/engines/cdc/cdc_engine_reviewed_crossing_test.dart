// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/cdc/cdc_domain_analysis.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:path/path.dart' as p;

/// What the engine reports for a crossing the analysis marks reviewed.
///
/// A reviewed crossing is a hazard the user accepted with a reason. The
/// engine turns it into a `cdc/reviewed-crossing` note instead of the error,
/// so it stays in the table, in SARIF and in the summary count rather than
/// vanishing, which is what would make an accepted crossing indistinguishable
/// from one the analysis never saw.
///
/// Against the real EDU capstone, elaborated by a real yosys; skipped where
/// yosys is not installed, and CI installs it.
const _sources = <String>[
  'test/fixtures/verilog/cdc/soc_top.v',
  'test/fixtures/verilog/cdc/producer.v',
  'test/fixtures/verilog/cdc/consumer.v',
  'test/fixtures/verilog/cdc/sync2.v',
];

const _reason = 'written once at boot, before clk_b leaves reset';

void main() {
  late bool yosysAvailable;

  setUpAll(() async {
    final probe = await YosysAvailabilityService(
      runner: const DefaultProcessRunner(),
    ).probe();
    yosysAvailable = probe.isAvailable;
  });

  Future<List<Violation>> run(CdcDomainAnalysis analysis) =>
      CdcEngine(
            analysis: analysis,
          )
          .run(
            LintRunRequest(
              sourceFiles: <String>[for (final s in _sources) p.absolute(s)],
              binary: const EngineBinaryConfig.system(),
              language: HdlLanguage.verilog,
              topModule: 'soc_top',
              projectRoot: Directory.current.path,
            ),
          )
          .toList();

  test('an unreviewed capstone reports the bus as an error', () async {
    if (!yosysAvailable) {
      markTestSkipped('yosys not on PATH');
      return;
    }
    final violations = await run(const CdcDomainAnalysis());
    expect(
      violations.where((v) => v.ruleId == 'cdc/unsync-multi-bit'),
      hasLength(1),
    );
    expect(
      violations.where((v) => v.ruleId == 'cdc/reviewed-crossing'),
      isEmpty,
    );
    final summary = violations.singleWhere((v) => v.ruleId == 'cdc/summary');
    expect(summary.message, contains('1 unsafe.'));
    expect(summary.message, isNot(contains('reviewed')));
    expect(summary.raw['reviewed'], 0);
  });

  test('a reviewed crossing is a note carrying the reason', () async {
    if (!yosysAvailable) {
      markTestSkipped('yosys not on PATH');
      return;
    }
    final violations = await run(
      CdcDomainAnalysis(
        reviewedCrossing:
            ({required sourceClock, required destClock, netName}) =>
                netName == 'data' ? _reason : null,
      ),
    );

    expect(
      violations.where((v) => v.ruleId == 'cdc/unsync-multi-bit'),
      isEmpty,
      reason: 'the accepted crossing must not also be reported as an error',
    );
    final note = violations.singleWhere(
      (v) => v.ruleId == 'cdc/reviewed-crossing',
    );
    expect(note.severity, Severity.note);
    expect(note.message, contains('8-bit bus `data`'));
    expect(note.message, contains('clk_a → clk_b'));
    expect(note.message, contains(_reason));
    expect(note.raw['review_reason'], _reason);
    expect(note.raw['sync_kind'], 'reviewed');
    // The same anchor and cross-probe field as the error it replaces, so a
    // waiver or a NetCrux highlight written against one works against the
    // other.
    expect(note.raw['path'], 'data');
    expect(note.relatedLocations, hasLength(1));
    expect(note.isAnalysisFailure, isFalse);

    final summary = violations.singleWhere((v) => v.ruleId == 'cdc/summary');
    expect(summary.message, contains('0 unsafe, 1 reviewed.'));
    expect(summary.raw['unsafe'], 0);
    expect(summary.raw['reviewed'], 1);
  });
}
