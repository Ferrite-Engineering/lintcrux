// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:meta/meta.dart';

/// The central plugin contract for a wrapped lint engine.
///
/// One concrete implementation per engine (Verilator, Verible, Slang,
/// GHDL, Yosys check, Svlint, CDC, custom regex).
///
/// Plugins do *not* evaluate rules — they wrap an existing engine
/// subprocess, parse its output, and emit normalized [Violation]
/// objects.
abstract class LintEngine {
  /// Stable identifier — appears as the `<engineId>` prefix in every
  /// [Violation.ruleId] this engine produces and in the engine-toggle
  /// UI. Lowercase, ASCII, no spaces (e.g. `"verilator"`).
  String get id;

  /// Human-readable display name (e.g. `"Verilator"`).
  String get displayName;

  /// Detect the installed engine version. Returns `null` if the engine
  /// cannot be found or refuses to run with `--version` (or its
  /// equivalent). Used by the diagnostics panel and the trend store.
  Future<String?> detectVersion(EngineBinaryConfig config);

  /// Run a lint pass over the given project files. Implementations
  /// stream [Violation]s as they parse the engine's output so the UI
  /// can render partial results during long runs (Verilator on a
  /// large SoC project can take 30+ seconds).
  ///
  /// Implementations must propagate cancellation: when the caller
  /// invokes [cancel], the returned stream closes promptly and the
  /// subprocess is killed.
  Stream<Violation> run(LintRunRequest request);

  /// Re-lint only the source files in [changedFiles] (each
  /// a path that appears in `request.sourceFiles`). Engines that
  /// declare [EngineCapabilities.supportsIncrementalPerFile] override
  /// this with a faster subprocess invocation that scopes the work to
  /// the changed files (e.g. Verilator's `--lint-only <files>` over
  /// just the edited file rather than the whole project).
  ///
  /// The default implementation falls back to a full [run] using the
  /// same request — safe for engines that don't support incremental
  /// re-runs (Yosys, GHDL). The orchestration layer reads
  /// [EngineCapabilities.supportsIncrementalPerFile] to decide
  /// whether the call is worth making in the first place; engines
  /// that say they support it should produce a meaningfully smaller
  /// workload here.
  ///
  /// Cancellation semantics match [run].
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) {
    return run(request);
  }

  /// Cancel an in-progress run. Idempotent — safe to call when nothing
  /// is running.
  void cancel();

  /// Static declaration of what this engine can do. Consulted by the
  /// engine-routing layer when deciding which engines to invoke for a
  /// given project's [LintRunRequest].
  EngineCapabilities get capabilities;
}

/// One invocation request for a [LintEngine].
@immutable
class LintRunRequest {
  /// Creates a [LintRunRequest].
  const LintRunRequest({
    required this.sourceFiles,
    required this.binary,
    required this.language,
    this.droppedSources = const <String>[],
    this.includePaths = const <String>[],
    this.defines = const <String, String>{},
    this.topModule,
    this.options = const <String, Object?>{},
    this.projectRoot = '',
  });

  /// Source files passed to the engine.
  final List<String> sourceFiles;

  /// Source files the language router excluded for THIS engine, because
  /// the engine does not support their language.
  ///
  /// Carried so an engine can refuse rather than analyse a design it has
  /// only part of. An engine whose analysis is per-file (a linter) can
  /// ignore this; an engine that elaborates a whole design cannot — the
  /// survivors reference modules that were dropped, and the tool reports
  /// a confusing elaboration error instead of the real cause.
  final List<String> droppedSources;

  /// `+incdir+`-style include paths.
  final List<String> includePaths;

  /// `+define+`-style preprocessor defines.
  final Map<String, String> defines;

  /// Optional top module / entity for engines that benefit from
  /// elaboration ordering.
  final String? topModule;

  /// Primary source language. Engines that don't support [language]
  /// should not be invoked at all — the engine-routing layer is
  /// responsible.
  final HdlLanguage language;

  /// Where the engine binary comes from (bundled / system / custom).
  final EngineBinaryConfig binary;

  /// Engine-specific options bag. Keys are engine-defined and
  /// documented per engine; the bag is untyped so the request shape
  /// stays stable as new options land.
  final Map<String, Object?> options;

  /// Absolute root of the project being linted (`LintProject.rootPath`),
  /// or empty when the caller has no project. Engines with a project-level
  /// configuration file (Verible's `.rules.verible_lint`, Svlint's
  /// `.svlint.toml`) look for it here.
  final String projectRoot;

  /// Returns a copy with overridden fields. Used by the incremental
  /// re-run path to swap [sourceFiles] for the changed subset without
  /// rebuilding the request from scratch.
  LintRunRequest copyWith({
    List<String>? sourceFiles,
    List<String>? droppedSources,
    List<String>? includePaths,
    Map<String, String>? defines,
    String? topModule,
    HdlLanguage? language,
    EngineBinaryConfig? binary,
    Map<String, Object?>? options,
    String? projectRoot,
  }) {
    return LintRunRequest(
      sourceFiles: sourceFiles ?? this.sourceFiles,
      // Must be carried: the incremental re-run path calls
      // `copyWith(sourceFiles: changed)`, and losing the dropped set here
      // would let a whole-design engine analyse a partial design on every
      // re-run while the first run correctly refused.
      droppedSources: droppedSources ?? this.droppedSources,
      includePaths: includePaths ?? this.includePaths,
      defines: defines ?? this.defines,
      topModule: topModule ?? this.topModule,
      language: language ?? this.language,
      binary: binary ?? this.binary,
      options: options ?? this.options,
      projectRoot: projectRoot ?? this.projectRoot,
    );
  }
}

/// Thrown by a [LintEngine] when its required binary cannot be found or
/// cannot be invoked.
///
/// Engines surface this as a stream error from [LintEngine.run] (or as a
/// `null` from [LintEngine.detectVersion]) so the orchestration layer can
/// keep the rest of the run going. The exception is not a crash — it is a
/// graceful "this engine is unavailable on this machine" signal whose UI
/// translation is a discoverable diagnostics-panel entry, not a dialog.
///
/// Missing-binary cases come from (a) the configured executable not being
/// on `PATH`, (b) the resolved path being non-executable, or (c) the
/// engine refusing to run `--version` (or its equivalent) with a non-zero
/// exit. Once per-platform bundled binaries ship, a binary missing from
/// the LintCrux distribution becomes a fourth case.
class EngineNotAvailableException implements Exception {
  /// Creates an [EngineNotAvailableException].
  const EngineNotAvailableException({
    required this.engineId,
    required this.reason,
    this.resolvedPath,
    this.cause,
  });

  /// The [LintEngine.id] of the engine that could not be invoked.
  final String engineId;

  /// Human-readable explanation, suitable for the diagnostics panel.
  /// English-only; localization wraps this at the display layer.
  final String reason;

  /// The path the engine resolver tried (if known). Useful for
  /// diagnostics when a custom path is misconfigured.
  final String? resolvedPath;

  /// The underlying error (typically a `ProcessException` from
  /// `Process.run` / `Process.start`), preserved for diagnostics.
  final Object? cause;

  @override
  String toString() {
    final pathStr = resolvedPath != null ? ' (path: $resolvedPath)' : '';
    final causeStr = cause != null ? ': $cause' : '';
    return 'EngineNotAvailableException[$engineId]: $reason$pathStr$causeStr';
  }
}

/// Thrown when a [LintEngine] run exceeds its wall-clock budget and is
/// killed by the [EngineWatchdog].
///
/// A hung or pathologically slow engine (an infinite-loop in the engine
/// on adversarial input, a binary waiting on stdin, a runaway elaboration)
/// must never hang the whole app. The watchdog arms a timer per spawned
/// process; on expiry it cancels the engine — which kills the subprocess —
/// and surfaces this exception as a stream error so the orchestration
/// layer marks the engine failed while the *other* engines keep running.
///
/// This is distinct from [EngineNotAvailableException]: the binary was
/// found and started, it just didn't finish in time. The UI affordance is
/// "this engine timed out; raise the timeout or check the input", not
/// "install this engine".
class EngineTimedOutException implements Exception {
  /// Creates an [EngineTimedOutException].
  const EngineTimedOutException({
    required this.engineId,
    required this.timeout,
  });

  /// The [LintEngine.id] of the engine that exceeded its budget.
  final String engineId;

  /// The wall-clock budget that was exceeded.
  final Duration timeout;

  @override
  String toString() =>
      'EngineTimedOutException[$engineId]: exceeded '
      '${timeout.inMilliseconds}ms wall-clock budget';
}

/// Thrown when a [LintEngine]'s binary ran to completion but the
/// invocation itself failed — the process exited non-zero without
/// producing a single parseable violation.
///
/// This exists to close the **silent false-clean** class: most lint
/// binaries exit non-zero precisely *because* they found violations, so a
/// non-zero exit alone means nothing. But a non-zero exit that yields zero
/// violations means the run never linted anything (a rejected command-line
/// flag, an unreadable source file, a malformed rules spec) — and
/// reporting that as "Completed, 0 violations" can green-light a dirty
/// design. Engines raise this instead; `ParallelEngineRunner` turns it
/// into an `EngineRunPhase.failed` with the [outputExcerpt] visible in the
/// diagnostics panel.
///
/// Distinct from [EngineNotAvailableException] (the binary could not be
/// started at all) and [EngineTimedOutException] (it never finished).
class EngineRunFailedException implements Exception {
  /// Creates an [EngineRunFailedException].
  const EngineRunFailedException({
    required this.engineId,
    required this.exitCode,
    required this.reason,
    this.outputExcerpt = const <String>[],
    this.resolvedPath,
  });

  /// The [LintEngine.id] of the engine whose invocation failed.
  final String engineId;

  /// The process exit code.
  final int exitCode;

  /// Human-readable explanation, suitable for the diagnostics panel.
  /// English-only; localization wraps this at the display layer.
  final String reason;

  /// First lines of the combined stdout/stderr transcript, so the user
  /// sees *why* (e.g. `ERROR: unknown command line flag 'lint_output'`).
  final List<String> outputExcerpt;

  /// The executable that was invoked, when known.
  final String? resolvedPath;

  @override
  String toString() {
    final pathStr = resolvedPath != null ? ' (path: $resolvedPath)' : '';
    final outStr = outputExcerpt.isEmpty ? '' : '\n${outputExcerpt.join('\n')}';
    return 'EngineRunFailedException[$engineId]: $reason$pathStr$outStr';
  }
}

/// Static declaration of what a [LintEngine] supports.
@immutable
class EngineCapabilities {
  /// Creates an [EngineCapabilities].
  const EngineCapabilities({
    required this.supportedLanguages,
    this.supportsIncrementalPerFile = false,
    this.emitsStructuredOutput = false,
    this.supportsAutoFix = false,
    this.supportsConfigFile = false,
    this.cacheable = true,
  });

  /// Set of [HdlLanguage]s the engine accepts. The engine-routing
  /// layer rejects requests whose `language` is absent here.
  final Set<HdlLanguage> supportedLanguages;

  /// Whether this engine's results may be served from the lint cache.
  ///
  /// The cache key is `(source fingerprints, request config, engine version)`,
  /// which is complete for an engine whose behaviour is fully determined by a
  /// versioned external binary and the files it is handed. It is **not**
  /// complete for an engine with any other input.
  ///
  /// Set this false when either holds:
  ///
  /// * the engine reads a file that is not in `sourceFiles` — a cache key
  ///   blind to that file replays a stale result forever, so the user edits
  ///   the file and nothing happens;
  /// * the analysis lives in Dart rather than in the binary whose version the
  ///   key records, so shipping an improved analysis cannot invalidate
  ///   anything and the improvement is invisible on any warm cache.
  ///
  /// Both are silent failures — the run reports Completed and the numbers are
  /// simply wrong — which is why this is opt-out rather than something a
  /// caller is trusted to reason about per engine.
  final bool cacheable;

  /// Whether the engine supports per-file incremental re-runs (Phase
  /// 2). When `false`, the orchestration layer falls back to
  /// whole-project re-runs.
  final bool supportsIncrementalPerFile;

  /// Whether the engine emits structured output (SARIF or JSON-line)
  /// natively. When `true`, the plugin's parser is the structured-
  /// output parser; when `false`, the plugin parses human-readable
  /// text.
  final bool emitsStructuredOutput;

  /// Whether the engine knows how to produce auto-fixes for the
  /// violations it reports. Today only Verible. Pro tier is
  /// the consumer.
  final bool supportsAutoFix;

  /// Whether the engine has its own configuration file format (e.g.
  /// Verible's `.rules.verible_lint`, Svlint's `.svlint.toml`). When
  /// `true`, the plugin scans the project root for the config file
  /// and surfaces its presence in the engine-config UI.
  final bool supportsConfigFile;
}
