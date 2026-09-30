// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';

void main() {
  group('HdlLanguage', () {
    test('declares the four expected values', () {
      expect(HdlLanguage.values, [
        HdlLanguage.verilog,
        HdlLanguage.systemVerilog,
        HdlLanguage.vhdl,
        HdlLanguage.mixed,
      ]);
    });
  });
}
