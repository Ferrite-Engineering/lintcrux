// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';

// What the two Yosys-backed engines (`yosys`, `cdc`) share: which binary a
// run starts, and how a run that produced nothing becomes the engine
// exception the run pipeline reports.

/// The Yosys executable [config] selects, or `null` for the runner's own
/// `PATH` default (`yosys`, `yosys.exe` on Windows).
///
/// Same resolution as every other engine: a Custom path wins, Bundled asks
/// [resolver] and falls back to `PATH`, Auto-detect is `PATH`. Resolved per
/// run rather than at construction so a changed setting applies to the next
/// run, and so constructing an engine touches no `dart:io` platform state.
String? yosysExecutableFor(
  EngineBinaryConfig config, {
  BundledBinaryResolver resolver = const BundledBinaryResolver(),
}) {
  switch (config.source) {
    case EngineBinarySource.custom:
      final path = config.path;
      return (path == null || path.isEmpty) ? null : path;
    case EngineBinarySource.bundled:
      return resolver.resolve('yosys');
    case EngineBinarySource.system:
      return null;
  }
}

/// How many output lines an [EngineRunFailedException] raised for a Yosys
/// run carries into the diagnostics panel. Matches the other engines.
const int _kOutputExcerptLines = 10;

/// Whether [result] is Yosys's own verdict on the design: it ran over the RTL
/// and exited non-zero, so its stderr describes the design.
///
/// Every other failure is about the tool, not the design, and must fail the
/// engine instead of becoming findings: nothing ran
/// ([YosysFailureKind.launch], [YosysFailureKind.invalidRequest]), or the run
/// ended without the output a completed Yosys run writes
/// ([YosysFailureKind.outputUnreadable], [YosysFailureKind.noOutput]).
///
/// The switch is exhaustive on purpose: a kind added to `crux_yosys` stops
/// this compiling until someone decides which side it falls on.
bool isYosysDesignFailure(YosysRunResult result) => switch (result) {
  YosysRunFailure(:final kind) => switch (kind) {
    YosysFailureKind.nonZeroExit => true,
    YosysFailureKind.launch ||
    YosysFailureKind.invalidRequest ||
    YosysFailureKind.outputUnreadable ||
    YosysFailureKind.noOutput => false,
  },
  YosysRunSuccess() || YosysRunTimeout() || YosysRunCancelled() => false,
};

/// The engine exception for a Yosys run that produced nothing a LintCrux
/// engine can report.
///
/// - a launch failure is [EngineNotAvailableException], so the run reports the
///   engine as unavailable and the headless binary exits `3` unless
///   `--allow-missing-engines` was passed;
/// - a timeout is [EngineTimedOutException];
/// - anything else — a non-zero exit, a rejected request, unreadable or
///   missing `write_json` output, a cancelled run — is
///   [EngineRunFailedException] carrying the first lines of stderr and a
///   reason naming which of those it was.
///
/// [executable] is the binary the runner was asked to start, reported so a
/// misconfigured custom path is visible in the diagnostics panel.
Exception yosysRunException({
  required String engineId,
  required YosysRunResult result,
  String? executable,
}) {
  final excerpt = <String>[
    for (final line in result.stderr.split('\n'))
      if (line.trim().isNotEmpty) line,
  ].take(_kOutputExcerptLines).toList(growable: false);
  switch (result) {
    case YosysRunFailure(kind: YosysFailureKind.launch):
      return EngineNotAvailableException(
        engineId: engineId,
        reason: result.stderr.trim(),
        resolvedPath: executable,
      );
    case YosysRunTimeout(:final budget):
      return EngineTimedOutException(engineId: engineId, timeout: budget);
    case YosysRunCancelled():
      return EngineRunFailedException(
        engineId: engineId,
        exitCode: YosysRunner.launchFailureExitCode,
        reason: 'the yosys run was cancelled before it finished',
        outputExcerpt: excerpt,
        resolvedPath: executable,
      );
    case YosysRunFailure(:final exitCode, :final kind):
      return EngineRunFailedException(
        engineId: engineId,
        exitCode: exitCode,
        reason: switch (kind) {
          YosysFailureKind.invalidRequest =>
            'yosys was not started: the request could not be turned into a '
                'yosys script',
          YosysFailureKind.outputUnreadable =>
            'yosys finished but its JSON output could not be read back',
          YosysFailureKind.noOutput =>
            'yosys exited $exitCode without writing its JSON output',
          // Handled by the launch case above; kept so the switch stays
          // exhaustive over the kinds.
          YosysFailureKind.launch => 'yosys could not be started',
          YosysFailureKind.nonZeroExit =>
            excerpt.isEmpty
                ? 'yosys exited $exitCode with no output'
                : 'yosys exited $exitCode without a parseable diagnostic',
        },
        outputExcerpt: excerpt,
        resolvedPath: executable,
      );
    case YosysRunSuccess():
      throw ArgumentError.value(
        result,
        'result',
        'a successful Yosys run has no failure to report',
      );
  }
}
