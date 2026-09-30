// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show Directory;

import 'package:crux_yosys/crux_yosys.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';

/// LintCrux lint adapter around Yosys's `check -assert` synthesis-time
/// diagnostics.
///
/// Yosys is not a primary lint engine — it's a synthesis tool — but it
/// catches a class of issues that pure-RTL linters cannot (driver
/// conflicts, multiply-driven nets, undriven outputs, unresolved
/// hierarchies). This adapter runs a tightly-scoped Yosys script:
///
/// ```text
/// read_verilog … (sources, +incdir+, +define+ translation)
/// hierarchy -check -top <top>
/// check -assert
/// ```
///
/// `check -assert` exits non-zero when Yosys identifies a structural
/// problem; the captured stderr is fed to [YosysDiagnosticParser]
/// (from `crux_yosys`) and each [YosysDiagnostic] is mapped into a
/// LintCrux [Violation]:
///
/// - [YosysDiagnosticSeverity.error] → [Severity.error]
/// - [YosysDiagnosticSeverity.warning] → [Severity.warning]
/// - [YosysDiagnosticSeverity.info] → [Severity.note]
///
/// Module-name fallback: when [YosysDiagnostic.filePath] is null, the
/// adapter populates the violation's location from a best-effort module
/// name capture in the diagnostic message (e.g. `Module \mod_a` → file
/// `<top:mod_a>:0`). This keeps the violation table grouped per-module
/// for the common case where Yosys reports a problem without a source
/// citation.
///
/// The binary comes from [LintRunRequest.binary] like every other engine's
/// (see [yosysExecutableFor]): a Custom path from Settings > Engines or
/// `--yosys-path`, a bundled binary, or `yosys` on `PATH`. A binary that
/// cannot be started is reported as an unavailable engine, never as a clean
/// run.
class YosysCheckEngine implements LintEngine {
  /// Creates a [YosysCheckEngine].
  ///
  /// [processRunner] and [tempDirectory] are the subprocess and scratch-file
  /// seams handed to the `YosysRunner` built for each run; tests inject a
  /// fake runner. [bundledBinaryResolver] answers the Bundled binary source.
  YosysCheckEngine({
    this.processRunner = const DefaultProcessRunner(),
    this.tempDirectory,
    YosysDiagnosticParser? parser,
    this.onDiagnostics,
    this.bundledBinaryResolver = const BundledBinaryResolver(),
  }) : _parser = parser ?? const YosysDiagnosticParser();

  /// Spawns Yosys and its version probe.
  final ProcessRunner processRunner;

  /// Where Yosys writes its `write_json` output; `null` is the system temp
  /// directory.
  final Directory? tempDirectory;

  final YosysDiagnosticParser _parser;

  /// Bundled-binary resolver, consulted when [EngineBinaryConfig.source]
  /// is [EngineBinarySource.bundled].
  final BundledBinaryResolver bundledBinaryResolver;

  /// Optional sink that receives the full [YosysDiagnostic] list each
  /// time a run completes. The Tab Diagnostics drawer wires a
  /// callback that forwards the list into `yosysDiagnosticsProvider`
  /// so the drawer can render the raw diagnostics alongside the
  /// per-tab violation summary.
  final void Function(List<YosysDiagnostic> diagnostics)? onDiagnostics;

  @override
  String get id => 'yosys';

  @override
  String get displayName => 'Yosys check';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {
      HdlLanguage.verilog,
      HdlLanguage.systemVerilog,
    },
    // Yosys's `check`/`hierarchy -check` runs after a full
    // elaboration pass. Incremental per-file re-linting would
    // miss the cross-file driver-conflict and multiply-driven-net
    // diagnostics that are the whole point of the Yosys check
    // engine. Stay at the default (false).
  );

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async {
    final service = YosysAvailabilityService(
      runner: processRunner,
      executableNameOverride: yosysExecutableFor(
        config,
        resolver: bundledBinaryResolver,
      ),
    );
    final availability = await service.probe();
    if (availability.isAvailable) return availability.versionString;
    return null;
  }

  @override
  Stream<Violation> run(LintRunRequest request) {
    final controller = StreamController<Violation>();
    unawaited(_runAndStream(request, controller));
    return controller.stream;
  }

  Future<void> _runAndStream(
    LintRunRequest request,
    StreamController<Violation> controller,
  ) async {
    try {
      final executable = yosysExecutableFor(
        request.binary,
        resolver: bundledBinaryResolver,
      );
      final runner = YosysRunner(
        processRunner: processRunner,
        executable: executable,
        tempDirectory: tempDirectory,
      );
      final result = await runner.run(
        YosysRunRequest.fromPaths(
          sourceFiles: request.sourceFiles,
          topModule: request.topModule,
          defines: [
            for (final entry in request.defines.entries)
              if (entry.value.isEmpty)
                entry.key
              else
                '${entry.key}=${entry.value}',
          ],
          includePaths: request.includePaths,
          extraCommands: const ['check -assert'],
        ),
      );

      // The runner never throws, so "yosys is not installed" arrives here as
      // a failure result rather than an exception. Only a failure that is
      // Yosys's verdict on the design may be parsed: every other kind carries
      // a synthetic message that matches no diagnostic pattern, or none at
      // all, which would report a clean run over a design nothing linted.
      switch (result) {
        case YosysRunSuccess():
          break;
        case YosysRunFailure() when isYosysDesignFailure(result):
          // `check -assert` exits non-zero precisely because it found
          // problems; the diagnostics are parsed below.
          break;
        case YosysRunFailure() || YosysRunTimeout() || YosysRunCancelled():
          controller.addError(
            yosysRunException(
              engineId: id,
              result: result,
              executable: executable,
            ),
          );
          return;
      }

      final diagnostics = _parser.parse(result.stderr);
      // A non-zero exit that yields no diagnostic means the run linted
      // nothing (an unreadable source, a rejected script) — the same
      // false-clean contract the other engines enforce.
      if (result is YosysRunFailure && diagnostics.isEmpty) {
        controller.addError(
          yosysRunException(
            engineId: id,
            result: result,
            executable: executable,
          ),
        );
        return;
      }
      onDiagnostics?.call(diagnostics);
      for (final d in diagnostics) {
        controller.add(_toViolation(d));
      }
    } finally {
      await controller.close();
    }
  }

  /// Parses a captured Yosys `check -assert` stderr transcript into
  /// violations using the same mapping the live [run] uses (the engine
  /// corpus relies on this). Exposed so a canned stderr can be turned into
  /// the golden SARIF without spawning Yosys.
  List<Violation> violationsFromStderr(String stderr) =>
      _parser.parse(stderr).map(_toViolation).toList(growable: false);

  @override
  void cancel() {
    // crux_yosys' YosysRunner does not currently expose mid-run
    // cancellation — `check -assert` runs are short (seconds), so the
    // missing seam is acceptable. When the package
    // grows a cancel API, plug it in here.
  }

  Violation _toViolation(YosysDiagnostic d) {
    final severity = _mapSeverity(d.severity);
    final location = _resolveLocation(d);
    final ruleId = 'yosys/${_inferRuleId(d)}';
    return Violation(
      engineId: id,
      ruleId: ruleId,
      severity: severity,
      message: d.message,
      location: location,
      raw: <String, dynamic>{
        'yosys.severityRaw': d.severity.name,
        if (d.rawLine != null) 'yosys.rawLine': d.rawLine,
      },
    );
  }

  /// Yosys check diagnostics, mapped to stable rule ids.
  ///
  /// Yosys does not name its checks, so LintCrux derives an id from the
  /// message. The original derivation kebab-cased the first four words, which
  /// worked for messages opening with four English words and failed badly for
  /// the ones that do not — the signal name is the second word here:
  ///
  ///     Wire fifo.rd_ptr is used but has no driver. -> wire-fifordptr-is-used
  ///     Wire undriven.z  is used but has no driver. -> wire-undrivenz-is-used
  ///
  /// The same check produced a different id per signal, which is not a
  /// cosmetic problem. A waiver keys on the rule id, so one written against
  /// either of those matched exactly one signal in one design and died the
  /// moment it was renamed; by-rule grouping degenerated into N groups of one;
  /// and SARIF export carries the rule id, so a design's internal signal names
  /// were being published into GitHub Code Scanning.
  ///
  /// Patterns match the message in order, first match wins. Every id here has
  /// an entry in `lib/data/rules/yosys.json` — possible only because the set
  /// is now closed.
  static const List<(String, String)> _rulePatterns = <(String, String)>[
    ('is used but has no driver', 'undriven-wire'),
    ('multiple conflicting drivers', 'multiple-drivers'),
    ('found logic loop', 'logic-loop'),
    ('Latch inferred', 'latch-inferred'),
    ('is not part of the design', 'unknown-module'),
    ('found unknown cell type', 'unknown-cell-type'),
    ('is implicitly declared', 'implicit-declaration'),
    ('Replacing memory', 'memory-replaced'),
    ('Found and reported', 'check-summary'),
    ('Successfully finished', 'run-summary'),
  ];

  /// Punctuation stripped from a token's edges before it is judged.
  static final RegExp _edgePunctuation = RegExp(
    r'''^[`'"(\[]+|[`'".,:;)\]]+$''',
  );

  /// Design-reference punctuation. A token carrying any of it names something
  /// in the user's RTL rather than describing the check.
  static final RegExp _designReference = RegExp(r'''[\\`'".]''');

  /// Derives the rule id for [d].
  ///
  /// Falls back to the word heuristic for a message no pattern covers — but
  /// strips design references first, so even an unrecognised message yields an
  /// id identical across designs.
  static String _inferRuleId(YosysDiagnostic d) {
    for (final (needle, ruleId) in _rulePatterns) {
      if (d.message.contains(needle)) return ruleId;
    }
    final words = <String>[];
    for (final raw in d.message.split(RegExp(r'\s+'))) {
      final token = raw.replaceAll(_edgePunctuation, '');
      if (token.isEmpty) continue;
      if (_designReference.hasMatch(token)) continue;
      if (RegExp(r'^\d+$').hasMatch(token)) continue;
      words.add(token);
      if (words.length == 4) break;
    }
    if (words.isEmpty) return 'unknown';
    return words.join('-').toLowerCase().replaceAll(RegExp('[^a-z0-9-]'), '');
  }

  static Severity _mapSeverity(YosysDiagnosticSeverity s) {
    switch (s) {
      case YosysDiagnosticSeverity.error:
        return Severity.error;
      case YosysDiagnosticSeverity.warning:
        return Severity.warning;
      case YosysDiagnosticSeverity.info:
        return Severity.note;
    }
  }

  static SourceLocation _resolveLocation(YosysDiagnostic d) {
    if (d.filePath != null && d.filePath!.isNotEmpty) {
      return SourceLocation(
        file: d.filePath!,
        line: d.line ?? 1,
        column: d.column ?? 1,
      );
    }
    // Module-name fallback: when Yosys cites a module name in the
    // message (`\modname` is the common syntax for cell/module
    // references), use it as the synthetic file path so the violation
    // groups under the right module in the table.
    final match = RegExp(r'\\([A-Za-z_]\w*)').firstMatch(d.message);
    final fallbackPath = match != null
        ? '<module:${match.group(1)}>'
        : '<yosys>';
    return SourceLocation(file: fallbackPath, line: 1, column: 1);
  }
}
