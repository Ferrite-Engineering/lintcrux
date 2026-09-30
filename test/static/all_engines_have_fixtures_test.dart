// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';

/// Engines exempt from the text-output corpus, each with the reason and
/// where its behaviour is covered instead. Printed on every run so the
/// exemption stays visible.
const Map<String, String> _exempt = <String, String>{
  'cdc':
      'consumes a Yosys-elaborated netlist rather than engine text output, '
      'so there is no output.txt to capture; the analysis is covered by '
      'test/services/engines/cdc/',
};

/// Static guardrail: every engine in the shipped
/// registry must ship at least one `generated/*/output.txt` fixture, unless
/// it is listed in [_exempt] with a reason. This is what stops a new engine
/// wrapper from landing with no golden — add an engine to
/// `defaultEngineRegistry()` without a corpus and this test fails loudly
/// naming the engine.
void main() {
  // The registry the app and the headless binary actually ship, not a
  // hand-built copy of it that can drift.
  final registry = defaultEngineRegistry();

  test('every registered engine has at least one generated fixture', () {
    final missing = <String>[];
    for (final engineId in registry.engineIds) {
      final exemption = _exempt[engineId];
      if (exemption != null) {
        // Printed deliberately: an exemption nobody sees is a gap nobody
        // revisits.
        // ignore: avoid_print
        print('fixture corpus exemption: $engineId — $exemption');
        continue;
      }
      final dir = Directory('test/fixtures/engines/$engineId/generated');
      final hasCase =
          dir.existsSync() &&
          dir.listSync().whereType<Directory>().any(
            (c) => File('${c.path}/output.txt').existsSync(),
          );
      if (!hasCase) missing.add(engineId);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'engines registered without a generated/ corpus '
          '(add one via tool/generate_engine_corpus.dart): $missing',
    );
  });

  test('every exemption names an engine the registry ships', () {
    expect(
      _exempt.keys.toSet().difference(registry.engineIds.toSet()),
      isEmpty,
    );
  });
}
