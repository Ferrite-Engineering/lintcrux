// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Minimal in-test implementation used to prove the interface compiles
/// and admits a usable mock surface.
class _FakeEngine implements LintEngine {
  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '0.0.1';

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    // No-op; real engines stream parsed violations.
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {}
}

void main() {
  group('LintEngine interface', () {
    test('a minimal implementation satisfies the contract', () async {
      final engine = _FakeEngine();
      expect(engine.id, 'fake');
      expect(engine.displayName, 'Fake');
      expect(
        await engine.detectVersion(const EngineBinaryConfig.bundled()),
        '0.0.1',
      );
      expect(
        engine.capabilities.supportedLanguages,
        contains(HdlLanguage.systemVerilog),
      );
      expect(engine.capabilities.supportsAutoFix, isFalse);
      // No-op run produces an empty stream.
      final out = await engine
          .run(
            const LintRunRequest(
              sourceFiles: [],
              binary: EngineBinaryConfig.bundled(),
              language: HdlLanguage.systemVerilog,
            ),
          )
          .toList();
      expect(out, isEmpty);
      // cancel is safe when nothing is running.
      engine.cancel();
    });
  });

  group('LintRunRequest', () {
    test('defaults are conservative empty collections', () {
      const req = LintRunRequest(
        sourceFiles: ['/x.v'],
        binary: EngineBinaryConfig.bundled(),
        language: HdlLanguage.systemVerilog,
      );
      expect(req.includePaths, isEmpty);
      expect(req.defines, isEmpty);
      expect(req.topModule, isNull);
      expect(req.options, isEmpty);
    });
  });

  group('EngineNotAvailableException', () {
    test('toString includes engine id and reason', () {
      const e = EngineNotAvailableException(
        engineId: 'verilator',
        reason: 'binary not found on PATH',
      );
      final s = e.toString();
      expect(s, contains('verilator'));
      expect(s, contains('binary not found on PATH'));
    });

    test('toString includes resolvedPath when provided', () {
      const e = EngineNotAvailableException(
        engineId: 'verible',
        reason: 'not executable',
        resolvedPath: '/opt/verible/bin/verible-verilog-lint',
      );
      final s = e.toString();
      expect(s, contains('/opt/verible/bin/verible-verilog-lint'));
    });

    test('toString includes cause when provided', () {
      const cause = FormatException('garbage output');
      const e = EngineNotAvailableException(
        engineId: 'verilator',
        reason: 'version probe failed',
        cause: cause,
      );
      final s = e.toString();
      expect(s, contains('garbage output'));
    });

    test('is an Exception subtype (can flow through Stream.error)', () {
      const e = EngineNotAvailableException(
        engineId: 'x',
        reason: 'y',
      );
      expect(e, isA<Exception>());
    });
  });
}
