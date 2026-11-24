// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/providers/cross_probe_selection.dart';

const _violation = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'Signal cpu.alu.sum[7:0] is declared but unused',
  location: SourceLocation(file: '/abs/path/cpu.sv', line: 42, column: 5),
);

/// A time (CXP §9.3.3) survives LintCrux forwarding a violation as a
/// cross-probe selection.
void main() {
  test('the selection carries the time unchanged', () {
    final selection = crossProbeSelectionForViolation(
      _violation,
      time: CxpTime.parse('41250ps'),
    );

    expect(selection.time?.toJson(), '41250ps');
  });

  test('a bare tick time stays a tick time', () {
    final selection = crossProbeSelectionForViolation(
      _violation,
      time: CxpTime.ticks(42),
    );

    expect(selection.time?.isTicks, isTrue);
    expect(selection.time?.toJson(), '42');
  });

  test('without a time none is sent', () {
    expect(crossProbeSelectionForViolation(_violation).time, isNull);
  });
}
