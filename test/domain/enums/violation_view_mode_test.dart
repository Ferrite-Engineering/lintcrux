// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/violation_view_mode.dart';

void main() {
  group('ViolationViewMode', () {
    test('declares three values in stable order', () {
      expect(ViolationViewMode.values, hasLength(3));
      expect(ViolationViewMode.values, <ViolationViewMode>[
        ViolationViewMode.allViolations,
        ViolationViewMode.onlyNew,
        ViolationViewMode.onlyResolved,
      ]);
    });
  });
}
