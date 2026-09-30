// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/cdc/cdc_domain_analysis.dart';

/// How a clock is named in a message the user reads.
///
/// Both cases here were shipped wrong and caught by looking at the product.
void main() {
  group('humanCdcClockName', () {
    test('a source-declared clock passes through untouched', () {
      // The engineer named it; do not improve on that.
      expect(humanCdcClockName('clk_a'), 'clk_a');
      expect(humanCdcClockName('div2'), 'div2');
    });

    test('a Yosys generated clock loses the path and keeps the location', () {
      // The raw form is `$and$/long/abs/path/clocking.v:24$1_Y`, which is what
      // actually appeared in the middle of every crossing message. The file
      // and line are the useful part -- they point at the RTL that made the
      // clock -- so they survive and the rest does not.
      expect(
        humanCdcClockName(
          r'$and$/Users/me/proj/rtl/soc/clocking.v:24$1_Y',
        ),
        'generated clock (clocking.v:24)',
      );
      expect(
        humanCdcClockName(r'$and$rtl/gated_and_divided.v:24$1_Y'),
        'generated clock (gated_and_divided.v:24)',
      );
    });

    test('a synthetic name with no recoverable location still reads', () {
      // Never leak a raw `$...` blob into a sentence, even when there is
      // nothing useful to extract from it.
      expect(humanCdcClockName(r'$auto$xyz$1'), 'generated clock');
      expect(humanCdcClockName(r'$procdff$9'), 'generated clock');
    });

    test('a SystemVerilog source is recognised too', () {
      expect(
        humanCdcClockName(r'$and$/x/top.sv:7$1_Y'),
        'generated clock (top.sv:7)',
      );
    });
  });
}
