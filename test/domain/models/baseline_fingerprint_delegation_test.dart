// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// BaselineFingerprint is the shared crux_io signature with LintCrux's field
// layout; this pins that it stays a delegation, not a second implementation.

import 'package:crux_io/crux_io.dart' show CruxSignature;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';

void main() {
  group('BaselineFingerprint delegates to CruxSignature', () {
    test('compute is the signature over (ruleId, filePath) and message', () {
      const ruleId = 'verilator/UNUSEDSIGNAL';
      const filePath = 'rtl/fifo.sv';
      const message = 'Signal  is not used:\n  wr_ptr \n';
      expect(
        BaselineFingerprint.compute(
          ruleId: ruleId,
          filePath: filePath,
          message: message,
        ),
        CruxSignature.compute(<String>[ruleId, filePath], message),
      );
    });

    test('path and message relativisation are the shared ones', () {
      expect(
        BaselineFingerprint.projectRelativePath('/p/ip/fifo.sv', '/p'),
        CruxSignature.projectRelativePath('/p/ip/fifo.sv', '/p'),
      );
      expect(
        BaselineFingerprint.projectRelativePath(r'C:\p\ip\fifo.sv', r'C:\p'),
        'ip/fifo.sv',
      );
      expect(
        BaselineFingerprint.projectRelativeMessage('see /p/a.sv', '/p'),
        CruxSignature.projectRelativeMessage('see /p/a.sv', '/p'),
      );
    });

    test('computeCount still counts each delegated hash', () {
      final before = BaselineFingerprint.computeCount;
      BaselineFingerprint.compute(ruleId: 'r', filePath: 'f', message: 'm');
      BaselineFingerprint.compute(ruleId: 'r', filePath: 'f', message: 'm');
      expect(BaselineFingerprint.computeCount - before, 2);
    });
  });
}
