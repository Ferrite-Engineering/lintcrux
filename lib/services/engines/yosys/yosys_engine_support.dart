// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/clean_engine_environment.dart';
import 'package:path/path.dart' as p;

// What the two Yosys-backed engines (`yosys`, `cdc`) share: which binary a
// run starts, how the run request becomes a Yosys request, how Yosys is
// spawned, and how a run that produced nothing becomes the engine exception
// the run pipeline reports.

/// The Yosys source list for [request]: every file under the language the
/// project resolved for it, so a SystemVerilog file is read with
/// `read_verilog -sv` and a Verilog file without.
///
/// Reading every file as Verilog-2005 stopped a SystemVerilog source at its
/// first SystemVerilog-only token although the project declared the file's
/// language and the engine declares SystemVerilog support.
List<YosysSourceFile> yosysSourcesFor(LintRunRequest request) =>
    <YosysSourceFile>[
      for (final path in request.sourceFiles)
        YosysSourceFile(
          path,
          language: _yosysLanguageFor(request.languageOf(path), path),
        ),
    ];

YosysSourceLanguage _yosysLanguageFor(HdlLanguage language, String path) =>
    switch (language) {
      HdlLanguage.verilog => YosysSourceLanguage.verilog,
      HdlLanguage.systemVerilog => YosysSourceLanguage.systemVerilog,
      HdlLanguage.vhdl => YosysSourceLanguage.vhdl,
      // A hand-built request over a mixed project carries no per-file
      // language; the extension is the only evidence left.
      HdlLanguage.mixed => switch (p.extension(path).toLowerCase()) {
        '.sv' || '.svh' => YosysSourceLanguage.systemVerilog,
        '.vhd' || '.vhdl' => YosysSourceLanguage.vhdl,
        _ => YosysSourceLanguage.verilog,
      },
    };

/// `NAME` or `NAME=VALUE` for every entry of [LintRunRequest.defines], the
/// form `YosysRunRequest.defines` takes.
List<String> yosysDefinesFor(LintRunRequest request) => <String>[
  for (final entry in request.defines.entries)
    if (entry.value.isEmpty) entry.key else '${entry.key}=${entry.value}',
];

/// The per-engine option naming the directory Yosys runs from, relative to
/// the project root or absolute. Read under `perEngineOptions.yosys` and
/// `perEngineOptions.cdc`.
const String kYosysWorkingDirectoryOption = 'workingDirectory';

/// The directory Yosys runs from for [request].
///
/// Yosys resolves a relative `$readmemh` / `$readmemb` path against its own
/// working directory, which used to be wherever LintCrux happened to be
/// started: a design that loads a memory image elaborated from one shell and
/// failed from another, and never from the Dock. The run now starts from the
/// project root, so one project gives one answer everywhere, and a design
/// whose images live elsewhere names that directory in
/// [kYosysWorkingDirectoryOption]. With no project root the directory holding
/// the first source stands in; `null` when there is nothing to anchor on,
/// which leaves the process's own directory in place.
String? yosysWorkingDirectoryFor(LintRunRequest request) {
  final String? root;
  if (request.projectRoot.isNotEmpty) {
    root = request.projectRoot;
  } else if (request.sourceFiles.isNotEmpty) {
    root = p.dirname(request.sourceFiles.first);
  } else {
    root = null;
  }
  final option = request.options[kYosysWorkingDirectoryOption];
  if (option is String && option.isNotEmpty) {
    if (p.isAbsolute(option) || root == null) return p.normalize(option);
    return p.normalize(p.join(root, option));
  }
  return root;
}

/// Spawns Yosys the way LintCrux spawns every other engine.
///
/// `crux_yosys`'s runner hands its process runner neither an environment nor
/// a working directory, so a Yosys started through it inherited the bare
/// environment of the launching process. From Finder or the Dock that
/// `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`, and a Homebrew Yosys was
/// "not available" while Verilator and Verible beside it ran, because their
/// spawns go through [cleanEngineEnvironment]. This wrapper routes every
/// Yosys spawn, the version probe included, through the same environment,
/// and starts the run from [workingDirectory] (see
/// [yosysWorkingDirectoryFor]).
class EngineYosysProcessRunner implements ProcessRunner {
  /// Wraps [inner], the runner that spawns the process.
  const EngineYosysProcessRunner(this.inner, {this.workingDirectory});

  /// The runner the spawn is delegated to.
  final ProcessRunner inner;

  /// The directory every spawn runs from unless the caller names one.
  final String? workingDirectory;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    Future<void>? cancelSignal,
    String? stdoutFilePath,
    void Function(String line)? onStderrLine,
  }) => inner.run(
    executable,
    arguments,
    workingDirectory: workingDirectory ?? this.workingDirectory,
    environment: cleanEngineEnvironment(environment),
    timeout: timeout,
    cancelSignal: cancelSignal,
    stdoutFilePath: stdoutFilePath,
    onStderrLine: onStderrLine,
  );
}

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
