// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';

class _FakeEngine implements LintEngine {
  _FakeEngine(this.id);
  @override
  final String id;
  @override
  String get displayName => 'Fake $id';
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '0.0.0';
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

void main() {
  group('EngineRegistry', () {
    test('preserves insertion order in engineIds and engines', () {
      final reg = EngineRegistry([
        _FakeEngine('a'),
        _FakeEngine('b'),
        _FakeEngine('c'),
      ]);
      expect(reg.engineIds, ['a', 'b', 'c']);
      expect(reg.engines.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('get / contains / length report registration', () {
      final reg = EngineRegistry([_FakeEngine('a'), _FakeEngine('b')]);
      expect(reg.length, 2);
      expect(reg.contains('a'), isTrue);
      expect(reg.contains('z'), isFalse);
      expect(reg.get('a'), isNotNull);
      expect(reg.get('z'), isNull);
    });

    test('rejects duplicate engine ids at construction time', () {
      expect(
        () => EngineRegistry([_FakeEngine('a'), _FakeEngine('a')]),
        throwsArgumentError,
      );
    });

    test('empty registry is supported', () {
      final reg = EngineRegistry(const []);
      expect(reg.length, 0);
      expect(reg.engines, isEmpty);
      expect(reg.engineIds, isEmpty);
    });

    test('engineIds is unmodifiable', () {
      final reg = EngineRegistry([_FakeEngine('a')]);
      expect(() => reg.engineIds.add('b'), throwsUnsupportedError);
    });
  });
}
