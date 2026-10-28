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
import 'package:lintcrux/services/engines/yosys/yosys_elaboration.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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
/// SystemVerilog sources are read with `read_slang` instead when the Yosys
/// in use has the yosys-slang frontend, and with `read_verilog -sv`
/// otherwise. A run that stops before `check -assert` says so: a read the
/// reader could not finish (a file it could not open, a parse it gave up on,
/// a construct it does not support) is one `yosys/frontend-failed` analysis
/// failure (the design was not checked), and a stop on an error in the
/// design, such as a missing module or port in `hierarchy`, keeps its
/// findings and adds a `yosys/check-not-run` note. See [frontEndError].
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
    supportedLanguages: {HdlLanguage.verilog, HdlLanguage.systemVerilog},
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
      runner: EngineYosysProcessRunner(processRunner),
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
      final sources = yosysSourcesFor(request);
      // SystemVerilog goes through yosys-slang when this Yosys has it, as it
      // does for CDC. The built-in `read_verilog -sv` stops on constructs
      // ordinary SystemVerilog uses (`return` in a function, package
      // scoping), and a read that stops means `check` never runs.
      final hasSystemVerilog = sources.any(
        (s) => s.language == YosysSourceLanguage.systemVerilog,
      );
      final slang = hasSystemVerilog && await _hasSlang(request, executable);
      final runner = YosysRunner(
        processRunner: EngineYosysProcessRunner(
          processRunner,
          workingDirectory: yosysWorkingDirectoryFor(request),
        ),
        executable: executable,
        tempDirectory: tempDirectory,
      );
      final result = await runner.run(
        YosysRunRequest(
          sources: sources,
          topModule: request.topModule,
          defines: yosysDefinesFor(request),
          includePaths: request.includePaths,
          extraCommands: const ['check -assert'],
          parameters: request.parameters,
          frontend: slang ? YosysFrontend.slang : YosysFrontend.verilog,
          slangOptions: slang ? slangOptions : const <String>[],
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
      // yosys-slang names files relative to the directory Yosys ran in.
      final paths = YosysSpanPathResolver(request);

      // A failed run that never reached `check -assert` stopped earlier: in
      // the reader (the sources could not be read) or on an error in the
      // design (most often in `hierarchy`).
      // Either way the check pass did not run, and the run must say so
      // rather than look like a check that found one problem.
      if (result is YosysRunFailure && !checkPassRan(result.stderr)) {
        final readError = frontEndError(diagnostics, slang: slang);
        if (readError != null) {
          // What stopped the read is a fact about the tool, not a finding
          // on the design: one analysis failure replaces the parser's
          // errors. Warnings from the part that was read are kept.
          for (final d in diagnostics) {
            if (d.severity == YosysDiagnosticSeverity.error) continue;
            controller.add(_toViolation(d, paths));
          }
          controller.add(
            _frontEndFailure(
              readError,
              request: request,
              paths: paths,
              slang: slang,
              hasSystemVerilog: hasSystemVerilog,
            ),
          );
          return;
        }
        // A stop on the design itself: its errors are findings. yosys-slang
        // closes its own located errors with a bare `Compilation failed`,
        // which says nothing the errors above it do not.
        final hasOwnErrors = diagnostics.any(
          (d) => d.severity == YosysDiagnosticSeverity.error && !_isSummary(d),
        );
        for (final d in diagnostics) {
          if (hasOwnErrors && _isSummary(d)) continue;
          controller.add(_toViolation(_withoutSlangSeverity(d), paths));
        }
        controller.add(_checkNotRunNote(request));
        return;
      }
      for (final d in diagnostics) {
        controller.add(_toViolation(d, paths));
      }
    } finally {
      await controller.close();
    }
  }

  /// The `read_slang` options the check engine reads SystemVerilog with.
  ///
  /// `check` reads no assertion, so `--ignore-assertions` removes one way an
  /// SVA construct yosys-slang cannot lower could stop the read. Initial
  /// blocks are kept: dropping a declaration initializer would turn a
  /// constant register into an undriven one.
  static const List<String> slangOptions = <String>['--ignore-assertions'];

  /// Whether the stderr of a failed run shows `check -assert` ran: it ends a
  /// run that found problems with `Found N problems in 'check -assert'.`
  @visibleForTesting
  static bool checkPassRan(String stderr) =>
      _checkAssertSummary.hasMatch(stderr);

  static final RegExp _checkAssertSummary = RegExp(
    'problems in .check -assert',
  );

  /// The error that stopped Yosys reading the sources, or `null` when the
  /// run stopped on the design itself.
  ///
  /// Only a stop the reader is responsible for counts: a source or include
  /// file it could not open, a parse it could not finish (the built-in
  /// reader's `syntax error`), or a construct it does not support. Every
  /// other error is a finding about the design, whether the reader or
  /// `hierarchy` raised it: a module that is not part of the design, a port
  /// or parameter the module lacks, a top module that does not exist, a
  /// `-chparam` value Yosys cannot decode, a module defined twice. Reading
  /// those as a failed read would exit `3` on an ordinary design error.
  ///
  /// The split rests on what each pass prints under `yosys -q`. The
  /// readers cite `file:line` for what they reject and `hierarchy` cites
  /// nothing, so an error with no location is never read as a parse
  /// failure unless it is one of the readers' own file messages.
  /// [slang] selects yosys-slang's vocabulary: it is a full SystemVerilog
  /// compiler, so its errors are the design's except where it says it
  /// cannot lower a construct.
  @visibleForTesting
  static YosysDiagnostic? frontEndError(
    List<YosysDiagnostic> diagnostics, {
    bool slang = false,
  }) {
    final errors = diagnostics
        .where((d) => d.severity == YosysDiagnosticSeverity.error)
        .toList(growable: false);
    if (errors.isEmpty) return null;
    for (final d in errors) {
      if (_isReaderStop(d, slang: slang)) return d;
    }
    // yosys-slang's bare `Compilation failed` with nothing located before
    // it: the read failed and there is no design error to report instead.
    if (errors.every(_isSummary)) return errors.first;
    return null;
  }

  static bool _isReaderStop(YosysDiagnostic d, {required bool slang}) {
    final message = d.message;
    if (_readerFileNeedles.any(message.contains)) return true;
    final located = d.filePath != null && d.filePath!.isNotEmpty;
    if (!located) return false;
    final lower = message.toLowerCase();
    if (_unsupportedNeedles.any(lower.contains)) return true;
    return !slang && _parseFailureNeedles.any(lower.contains);
  }

  /// [d] without the `error:` yosys-slang starts its own messages with, so
  /// the message and its rule id read as the design error they are.
  static YosysDiagnostic _withoutSlangSeverity(YosysDiagnostic d) {
    final message = d.message.replaceFirst(_slangSeverityPrefix, '');
    return message == d.message ? d : d.copyWith(message: message);
  }

  /// yosys-slang's closing line after its own located errors.
  static bool _isSummary(YosysDiagnostic d) =>
      d.severity == YosysDiagnosticSeverity.error &&
      d.message.trim() == 'Compilation failed';

  /// The lower-case severity yosys-slang starts its own diagnostics with,
  /// which the Yosys diagnostic parser leaves in the message.
  static final RegExp _slangSeverityPrefix = RegExp(r'^(?:error|fatal):\s*');

  /// The readers' own messages for a file they could not open. Yosys gives
  /// them no location.
  static const List<String> _readerFileNeedles = <String>[
    'not found or is a directory',
    "Can't open include file",
    "Can't open input file",
  ];

  /// A construct the reader does not handle (lower case). yosys-slang says
  /// `unsupported` for what it cannot lower, the built-in reader `not
  /// supported` or `unsupported`.
  static const List<String> _unsupportedNeedles = <String>[
    'unsupported',
    'not supported',
  ];

  /// The built-in reader's parser stopping (lower case).
  static const List<String> _parseFailureNeedles = <String>[
    'syntax error',
    'parser error',
    'unexpected eof',
  ];

  Violation _frontEndFailure(
    YosysDiagnostic error, {
    required LintRunRequest request,
    required YosysSpanPathResolver paths,
    required bool slang,
    required bool hasSystemVerilog,
  }) {
    final file = error.filePath;
    final located = file != null && file.isNotEmpty;
    final location = located
        ? SourceLocation(
            file: paths.resolve(file),
            line: error.line ?? 1,
            column: error.column ?? 1,
          )
        : SourceLocation(
            file: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
            line: 1,
            column: 1,
          );
    final where = located
        ? ' (${p.basename(file)}, line ${error.line ?? 1})'
        : '';
    final String reader;
    if (slang) {
      reader = ' SystemVerilog was read with yosys-slang.';
    } else if (hasSystemVerilog && located) {
      // A located stop is the parser's; a file that could not be opened is
      // no limit of the reader.
      reader =
          " SystemVerilog was read with Yosys's built-in reader "
          '(read_verilog -sv), which does not accept every SystemVerilog '
          'construct, so the error may be a limit of that reader rather than '
          'a fault in the design. A Yosys that includes yosys-slang, such as '
          'the OSS CAD Suite (github.com/YosysHQ/oss-cad-suite-build), reads '
          'the language: select it in Settings > Engines > Yosys check, or '
          'pass --yosys-path.';
    } else {
      reader = '';
    }
    return Violation(
      engineId: id,
      ruleId: 'yosys/frontend-failed',
      severity: Severity.error,
      message:
          'Yosys could not read the sources, so its check pass (logic loops, '
          'multiple drivers, latches) did not run. Yosys stopped at: '
          '${error.message.replaceFirst(_slangSeverityPrefix, '')}'
          '$where.$reader',
      location: location,
      raw: <String, dynamic>{
        Violation.analysisFailedKey: true,
        if (error.rawLine != null) 'yosys.rawLine': error.rawLine,
      },
    );
  }

  /// The note added when Yosys stopped on an error in the design, usually in
  /// `hierarchy`: the findings above it are real, but the check pass they
  /// would normally come with did not run.
  Violation _checkNotRunNote(LintRunRequest request) => Violation(
    engineId: id,
    ruleId: 'yosys/check-not-run',
    severity: Severity.note,
    message:
        'Yosys stopped on the design errors above before its check pass '
        '(logic loops, multiple drivers, latches) ran. Resolve them to get '
        'its results.',
    location: SourceLocation(
      file: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
      line: 1,
      column: 1,
    ),
  );

  /// Whether [executable] has the yosys-slang frontend. Cached per
  /// executable by `crux_yosys`, so this costs one probe per binary per
  /// process.
  Future<bool> _hasSlang(LintRunRequest request, String? executable) =>
      YosysAvailabilityService(
        runner: EngineYosysProcessRunner(processRunner),
        executableNameOverride: executable,
      ).probeSlang();

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

  Violation _toViolation(YosysDiagnostic d, [YosysSpanPathResolver? paths]) {
    final severity = _mapSeverity(d.severity);
    final location = _resolveLocation(d, paths);
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
    // yosys-slang's wording for the same error.
    ('unknown module', 'unknown-module'),
    ('found unknown cell type', 'unknown-cell-type'),
    ('does not have a port named', 'unknown-port'),
    ('does not have a parameter named', 'unknown-parameter'),
    ('decode value', 'bad-parameter-value'),
    ('Re-definition of module', 'module-redefinition'),
    ('not found!', 'module-not-found'),
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

  static SourceLocation _resolveLocation(
    YosysDiagnostic d,
    YosysSpanPathResolver? paths,
  ) {
    if (d.filePath != null && d.filePath!.isNotEmpty) {
      return SourceLocation(
        file: paths?.resolve(d.filePath!) ?? d.filePath!,
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
