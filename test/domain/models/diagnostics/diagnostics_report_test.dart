// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/diagnostics/diagnostics_report.dart';

void main() {
  group('TabDiagnosticsReport.toPlainText', () {
    test('emits a header, project info and every measured engine line', () {
      const r = TabDiagnosticsReport(
        projectPath: '/work/p',
        sourceFileCount: 7,
        lastRunWallMs: 1234,
        engines: [
          EngineDiagnostics(
            engineId: 'verilator',
            binary: 'custom: /opt/verilator/bin/verilator',
            version: 'Verilator 5.022',
            durationMs: 500,
            severityCounts: {Severity.warning: 3, Severity.error: 1},
          ),
        ],
      );
      final out = r.toPlainText();
      expect(out, contains('# LintCrux Tab Diagnostics'));
      expect(out, contains('Project: /work/p'));
      expect(out, contains('Source files: 7'));
      expect(out, contains('Last run wall time: 1234 ms'));
      expect(out, contains('### verilator'));
      expect(out, contains('binary: custom: /opt/verilator/bin/verilator'));
      expect(out, contains('version: Verilator 5.022'));
      expect(out, contains('duration: 500 ms'));
      expect(out, contains('warning: 3'));
      expect(out, contains('error: 1'));
    });

    test('omits zero-count severities', () {
      const r = TabDiagnosticsReport(
        projectPath: '/p',
        sourceFileCount: 1,
        engines: [
          EngineDiagnostics(
            engineId: 'v',
            severityCounts: {Severity.warning: 0, Severity.error: 2},
          ),
        ],
      );
      final out = r.toPlainText();
      expect(out, contains('error: 2'));
      expect(out, isNot(contains('warning: 0')));
    });

    test(
      'an engine with nothing measured gets its heading and no stand-in '
      'lines: no zero duration, no placeholder binary or version',
      () {
        const r = TabDiagnosticsReport(
          projectPath: '/p',
          sourceFileCount: 1,
          engines: [EngineDiagnostics(engineId: 'verible')],
        );
        final out = r.toPlainText();
        expect(out, contains('### verible'));
        expect(out, isNot(contains('Last run')));
        expect(out, isNot(contains('binary:')));
        expect(out, isNot(contains('version:')));
        expect(out, isNot(contains('duration:')));
        expect(out, isNot(contains('counts:')));
        expect(out, isNot(contains('unknown')));
      },
    );

    test('a version probe that got no answer says so', () {
      const r = TabDiagnosticsReport(
        projectPath: '/p',
        sourceFileCount: 1,
        engines: [
          EngineDiagnostics(
            engineId: 'ghdl',
            binary: 'PATH',
            version: kEngineNotDetected,
          ),
        ],
      );
      expect(r.toPlainText(), contains('version: not detected'));
    });
  });

  group('AppDiagnosticsReport.toPlainText', () {
    test('renders resident memory in MiB and the active tab count', () {
      const r = AppDiagnosticsReport(
        residentMemoryBytes: 10 * 1024 * 1024,
        activeTabViolationCount: 42,
      );
      final out = r.toPlainText();
      expect(out, contains('Resident memory: 10.0 MiB'));
      expect(out, contains('Violations in the active tab: 42'));
    });

    test(
      'omits the memory line when the platform cannot report it, and never '
      'prints a frame rate it does not measure',
      () {
        const r = AppDiagnosticsReport(activeTabViolationCount: 0);
        final out = r.toPlainText();
        expect(out, isNot(contains('memory')));
        expect(out, isNot(contains('heap')));
        expect(out, isNot(contains('FPS')));
        expect(out, contains('Violations in the active tab: 0'));
      },
    );
  });
}
