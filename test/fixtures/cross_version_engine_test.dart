// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:lintcrux/services/engines/verible/verible_engine.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/rules/map_rule_alias_table.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The committed rule-alias table, loaded once. The
/// cross-version comparison resolves rule ids through it so a rule rename
/// across engine versions reconciles instead of failing the drift check;
/// an *un*-aliased difference still fails loudly.
final _aliasTable = MapRuleAliasTable.fromJsonString(
  File('lib/data/rule_aliases.json').readAsStringSync(),
);

/// Cross-version engine validation harness.
///
/// For each primary engine (Verilator, Verible, Slang), this test
/// runs the canonical fixture corpus against TWO versions of the
/// engine binary:
///
/// 1. The current version on `PATH` (or `LINTCRUX_BUNDLED_BIN_DIR`).
/// 2. The N-1 version supplied by the env vars
///    `VERILATOR_NMINUS1_BIN`, `VERIBLE_NMINUS1_BIN`,
///    `SLANG_NMINUS1_BIN` (absolute paths to the older binary).
///
/// The assertion is **tolerant**: violations are compared on rule
/// ID + severity + file (basename) + line. The message text is
/// allowed to differ between versions because engines routinely
/// reword diagnostics. A divergence in rule ID or severity is a
/// hard error and surfaces in CI; new rules in the current version
/// that the N-1 version does not produce are also tolerated (they
/// land in the current-only set without failing the test) so that
/// engine version bumps are not blocked by genuinely new
/// diagnostics.
///
/// Each test skips with a clear reason if either binary is missing.
/// The CI matrix populates the N-1 binary path via the
/// `nminus1Version` field in `tool/bundled_engines.yaml`.

bool _onPath(String binary) {
  final pathVar = Platform.environment['PATH'] ?? '';
  for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
    final candidate = File(p.join(dir, binary));
    if (candidate.existsSync()) return true;
  }
  return false;
}

String? _resolveCurrentPath(String binary) {
  final bundledRoot = Platform.environment['LINTCRUX_BUNDLED_BIN_DIR'];
  if (bundledRoot != null && bundledRoot.isNotEmpty) {
    final platformDir = Platform.isLinux
        ? 'linux-x86_64'
        : Platform.isMacOS
        ? 'macos-universal'
        : 'windows-x86_64';
    final exe = Platform.isWindows ? '$binary.exe' : binary;
    final candidate = p.join(bundledRoot, platformDir, exe);
    if (File(candidate).existsSync()) return candidate;
  }
  if (_onPath(binary)) return binary;
  return null;
}

/// Returns `null` if the N-1 env var is unset, the empty string, or
/// points at a non-existent file. The test skips when this returns
/// `null`.
String? _resolveNminus1(String envVar) {
  final raw = Platform.environment[envVar];
  if (raw == null || raw.isEmpty) return null;
  if (!File(raw).existsSync()) return null;
  return raw;
}

@immutable
class _ComparableViolation {
  _ComparableViolation(Violation v)
    : ruleId = v.ruleId,
      severity = v.severity.name,
      file = p.basename(v.location.file),
      line = v.location.line;

  final String ruleId;
  final String severity;
  final String file;
  final int line;

  String get key => '$ruleId@$file:$line';

  @override
  bool operator ==(Object other) =>
      other is _ComparableViolation && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => '[$severity] $key';
}

Future<List<_ComparableViolation>> _runEngine({
  required LintEngine engine,
  required EngineBinaryConfig config,
  required LintRunRequest request,
}) async {
  final out = <_ComparableViolation>[];
  await for (final v in engine.run(request.copyWith(binary: config))) {
    out.add(_ComparableViolation(v));
  }
  return out;
}

LintRunRequest _basicWarningsRequest() {
  final root = p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'projects',
    'basic_warnings',
  );
  const codec = ProjectFileCodec();
  final project = codec.decode(
    File(p.join(root, 'project.lintcrux')).readAsStringSync(),
  );
  final resolvedSources = [
    for (final s in project.sourceFiles)
      if (p.isAbsolute(s)) s else p.normalize(p.join(root, s)),
  ];
  return LintRunRequest(
    sourceFiles: resolvedSources,
    includePaths: project.includePaths,
    defines: project.defines,
    topModule: project.topModule,
    language: project.language,
    binary: const EngineBinaryConfig.system(),
  );
}

void _runCrossVersion({
  required String engineId,
  required LintEngine Function() makeEngine,
  required String currentBinary,
  required String nminus1Env,
}) {
  final currentPath = _resolveCurrentPath(currentBinary);
  final nminus1Path = _resolveNminus1(nminus1Env);

  String? skipReason;
  if (currentPath == null) {
    skipReason = '$currentBinary not on PATH or in LINTCRUX_BUNDLED_BIN_DIR';
  } else if (nminus1Path == null) {
    skipReason = 'set $nminus1Env to enable the N-1 cross-check';
  }

  test(
    '$engineId current vs N-1 — rule + severity + location agree on basic_warnings',
    () async {
      final request = _basicWarningsRequest();

      final currentConfig = currentPath == currentBinary
          ? const EngineBinaryConfig.system()
          : EngineBinaryConfig(
              source: EngineBinarySource.custom,
              path: currentPath ?? currentBinary,
            );
      final nminus1Config = EngineBinaryConfig(
        source: EngineBinarySource.custom,
        path: nminus1Path ?? '',
      );

      final currentResults = await _runEngine(
        engine: makeEngine(),
        config: currentConfig,
        request: request,
      );
      final nminus1Results = await _runEngine(
        engine: makeEngine(),
        config: nminus1Config,
        request: request,
      );

      // Match by (resolved-ruleId, file, line). Rule ids are resolved
      // through the alias table so a rule the engine renamed across
      // versions reconciles to one key; the parsed rule-id set may differ
      // between N and N-1 *only* by entries the alias table reconciles —
      // any un-aliased difference fails loudly with the rule ids printed.
      String resolvedKey(_ComparableViolation v) =>
          '${_aliasTable.resolve(v.ruleId)}@${v.file}:${v.line}';
      final currentByKey = {
        for (final v in currentResults) resolvedKey(v): v,
      };
      for (final old in nminus1Results) {
        final matching = currentByKey[resolvedKey(old)];
        expect(
          matching,
          isNotNull,
          reason:
              'N-1 reported "$old" (resolved rule '
              '${_aliasTable.resolve(old.ruleId)}) but current did not. '
              'Either the rule was renamed without a rule_aliases.json '
              'entry, removed in the current version (intentional?), or '
              'this is a regression in the cross-engine harness.',
        );
        expect(
          matching!.severity,
          old.severity,
          reason:
              'severity drift for ${old.key}: '
              'N-1=${old.severity} current=${matching.severity}',
        );
      }
    },
    skip: skipReason ?? false,
  );
}

void main() {
  group('Cross-version engine validation', () {
    _runCrossVersion(
      engineId: 'verilator',
      makeEngine: VerilatorEngine.new,
      currentBinary: 'verilator',
      nminus1Env: 'VERILATOR_NMINUS1_BIN',
    );
    _runCrossVersion(
      engineId: 'verible',
      makeEngine: VeribleEngine.new,
      currentBinary: 'verible-verilog-lint',
      nminus1Env: 'VERIBLE_NMINUS1_BIN',
    );
    _runCrossVersion(
      engineId: 'slang',
      makeEngine: SlangEngine.new,
      currentBinary: 'slang',
      nminus1Env: 'SLANG_NMINUS1_BIN',
    );
  });
}
