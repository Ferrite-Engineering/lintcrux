// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/engines/engine_binary_ids.dart';

void main() {
  test('CDC runs the Yosys binary', () {
    expect(binaryEngineIdFor('cdc'), 'yosys');
    expect(hasOwnBinary('cdc'), isFalse);
  });

  test('every other engine runs its own binary', () {
    for (final id in <String>['verilator', 'verible', 'slang', 'yosys']) {
      expect(binaryEngineIdFor(id), id);
      expect(hasOwnBinary(id), isTrue);
    }
  });

  test('every shipped engine binary has a --<id>-path flag', () {
    // The headless hint for a missing engine names --<binary id>-path, so
    // the flag list must cover exactly the binaries the registry runs.
    final binaryIds = <String>{
      for (final id in defaultEngineRegistry().engineIds) binaryEngineIdFor(id),
    };
    expect(CliArgsParser.binaryPathEngineIds.toSet(), binaryIds);
  });
}
