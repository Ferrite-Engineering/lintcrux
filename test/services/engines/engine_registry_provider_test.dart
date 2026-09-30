// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_engine.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:lintcrux/services/engines/svlint/svlint_engine.dart';
import 'package:lintcrux/services/engines/verible/verible_engine.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:lintcrux/services/engines/yosys/yosys_check_engine.dart';

void main() {
  group('engineRegistryProvider', () {
    test('default binding registers Verilator, Verible, Slang, '
        'Yosys, GHDL, and Svlint', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final registry = container.read(engineRegistryProvider);
      expect(registry.engineIds, [
        'verilator',
        'verible',
        'slang',
        'yosys',
        'ghdl',
        'svlint',
        'cdc',
      ]);
      expect(registry.get('verilator'), isA<VerilatorEngine>());
      expect(registry.get('verible'), isA<VeribleEngine>());
      expect(registry.get('slang'), isA<SlangEngine>());
      expect(registry.get('yosys'), isA<YosysCheckEngine>());
      expect(registry.get('ghdl'), isA<GhdlEngine>());
      expect(registry.get('svlint'), isA<SvlintEngine>());
    });
  });
}
