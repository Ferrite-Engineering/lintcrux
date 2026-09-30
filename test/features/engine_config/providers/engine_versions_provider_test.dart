// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/engine_config/providers/engine_versions_provider.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';

class _FakeEngine implements LintEngine {
  _FakeEngine(this.id, this._version, {this.throws = false});

  @override
  final String id;
  final String? _version;
  final bool throws;

  int probes = 0;

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async {
    probes++;
    if (throws) throw StateError('binary not on PATH');
    return _version;
  }

  @override
  String get displayName => id;

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );

  @override
  Stream<Violation> run(LintRunRequest request) async* {}

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {}
}

ProviderContainer _container(List<_FakeEngine> engines) {
  final container = ProviderContainer(
    overrides: [
      engineRegistryProvider.overrideWithValue(EngineRegistry(engines)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('engineVersionsProvider', () {
    test(
      'reports the detected version for every engine that answers',
      () async {
        final container = _container([
          _FakeEngine('verilator', 'Verilator 5.022'),
          _FakeEngine('verible', 'v0.0-3752'),
        ]);
        expect(await container.read(engineVersionsProvider.future), {
          'verilator': 'Verilator 5.022',
          'verible': 'v0.0-3752',
        });
      },
    );

    test('omits an engine whose binary is absent', () async {
      // The normal state on a machine that installed only some of the six —
      // not an error, and it must not take the other engines down with it.
      final container = _container([
        _FakeEngine('verilator', 'Verilator 5.022'),
        _FakeEngine('ghdl', null),
      ]);
      final versions = await container.read(engineVersionsProvider.future);
      expect(versions.keys, ['verilator']);
    });

    test('omits an engine whose probe throws', () async {
      final container = _container([
        _FakeEngine('verilator', 'Verilator 5.022'),
        _FakeEngine('slang', null, throws: true),
      ]);
      final versions = await container.read(engineVersionsProvider.future);
      expect(versions.keys, ['verilator']);
    });

    test('omits an engine that prints nothing usable', () async {
      final container = _container([_FakeEngine('svlint', '   ')]);
      expect(await container.read(engineVersionsProvider.future), isEmpty);
    });

    test('trims the reported version', () async {
      final container = _container([
        _FakeEngine('verilator', '  Verilator 5.022\n'),
      ]);
      final versions = await container.read(engineVersionsProvider.future);
      expect(versions['verilator'], 'Verilator 5.022');
    });

    test('probes each engine once per container', () async {
      // One subprocess per engine is the cost; a re-read must not pay it
      // again, or opening the reporter twice would spawn twelve processes.
      final engine = _FakeEngine('verilator', 'Verilator 5.022');
      final container = _container([engine]);
      await container.read(engineVersionsProvider.future);
      await container.read(engineVersionsProvider.future);
      expect(engine.probes, 1);
    });

    test('an empty registry resolves to an empty map', () async {
      final container = _container([]);
      expect(await container.read(engineVersionsProvider.future), isEmpty);
    });
    test('in the browser no engine is probed', () async {
      // The web viewer can reach the issue reporter from the command
      // palette, and a probe there would touch dart:io platform state the
      // browser does not have. The guard must stop it before any engine.
      final engine = _FakeEngine('yosys', 'Yosys 0.40');
      final container = ProviderContainer(
        overrides: [
          engineRegistryProvider.overrideWithValue(EngineRegistry([engine])),
          engineVersionProbingSupportedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(engineVersionsProvider.future), isEmpty);
      expect(engine.probes, 0);
    });

    test('probing is supported on the VM host', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(engineVersionProbingSupportedProvider), isTrue);
    });
  });
}
