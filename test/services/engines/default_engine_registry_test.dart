// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';

void main() {
  test('registers every open-core engine, in order', () {
    expect(defaultEngineRegistry().engineIds, <String>[
      'verilator',
      'verible',
      'slang',
      'yosys',
      'ghdl',
      'svlint',
      'cdc',
    ]);
  });

  test('the GUI provider and the headless factory agree', () {
    // The headless CI binary builds its registry from
    // `defaultEngineRegistry()` and the desktop app builds one from
    // `engineRegistryProvider`. If the two sets diverged, a project's
    // `enabledEngineIds` would resolve differently in CI than on the
    // engineer's machine — the CLI would silently skip an engine the
    // desktop app runs, or fail on one it does not have.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(engineRegistryProvider).engineIds,
      defaultEngineRegistry().engineIds,
    );
  });

  test('every registered engine declares at least one language', () {
    for (final engine in defaultEngineRegistry().engines) {
      expect(
        engine.capabilities.supportedLanguages,
        isNotEmpty,
        reason: '${engine.id} would be routed zero source files forever',
      );
    }
  });

  test('the Yosys diagnostics sink is optional', () {
    // The CLI has no diagnostics drawer to forward to, so the factory
    // must build a working registry with no callback.
    expect(defaultEngineRegistry().get('yosys'), isNotNull);
  });
}
