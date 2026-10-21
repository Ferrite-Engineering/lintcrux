// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io' show Directory, File, FileSystemEntity, FileSystemEntityType;

import 'package:crux_yosys/crux_yosys.dart';
import 'package:lintcrux/domain/enums/constraint_format.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/constraints/constraint_checks.dart';
import 'package:lintcrux/services/engines/constraints/constraint_parsers.dart';
import 'package:lintcrux/services/engines/yosys/yosys_elaboration.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';
import 'package:path/path.dart' as p;

/// The largest constraint file the engine reads, in bytes. A pin list for a
/// large FPGA package is a few tens of kilobytes; a bound keeps a file that
/// is not one from being read at all.
const int kMaxConstraintFileBytes = 4 * 1024 * 1024;

/// Checks FPGA pin-constraint files against the top module's ports.
///
/// The ports come from the Yosys elaboration the CDC engine uses
/// ([elaborateDesign]); the checks are Dart over the parsed files
/// (`checkConstraints`). Findings are ordinary [Violation]s on the constraint
/// file's own line and column, so waivers, trends, SARIF export and
/// cross-probe need nothing specific to this engine.
///
/// A project with no constraint files gets no findings and no Yosys run. A
/// project that has some and cannot be checked (no top module, a source the
/// engine does not read, a constraint file that cannot be read, a design Yosys
/// cannot elaborate) gets one finding carrying [Violation.analysisFailedKey]:
/// the run did not happen, which is never the same as a pass.
class ConstraintsEngine implements LintEngine {
  /// Creates the engine.
  ///
  /// Like CDC it starts no binary of its own: it runs Yosys, resolved from
  /// [LintRunRequest.binary] per run. [processRunner] and [tempDirectory] are
  /// the seams handed to the `YosysRunner` built for each run.
  ConstraintsEngine({
    this.processRunner = const DefaultProcessRunner(),
    this.tempDirectory,
    this.bundledBinaryResolver = const BundledBinaryResolver(),
  });

  /// Spawns Yosys and its version probe.
  final ProcessRunner processRunner;

  /// Where Yosys writes its `write_json` output; `null` is the system temp
  /// directory.
  final Directory? tempDirectory;

  /// Bundled-binary resolver, consulted when [EngineBinaryConfig.source]
  /// is [EngineBinarySource.bundled].
  final BundledBinaryResolver bundledBinaryResolver;

  @override
  String get id => 'constraints';

  @override
  String get displayName => 'Constraints';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.verilog, HdlLanguage.systemVerilog},
    emitsStructuredOutput: true,
    // NOT CACHEABLE. The lint cache keys on the source files, the request
    // config and the engine version, and the constraint files are none of
    // those: a user edits a pin, re-runs, and a cached answer from before the
    // edit comes back. The cost of opting out is one Yosys run per check.
    cacheable: false,
  );

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async {
    final probe = await YosysAvailabilityService(
      runner: EngineYosysProcessRunner(processRunner),
      executableNameOverride: yosysExecutableFor(
        config,
        resolver: bundledBinaryResolver,
      ),
    ).probe();
    return probe.isAvailable ? probe.versionString : null;
  }

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    if (request.constraintFiles.isEmpty) return;
    final firstConstraint = request.constraintFiles.first;

    Violation didNotRun(
      String ruleId,
      String message,
      SourceLocation location,
    ) => Violation(
      engineId: id,
      ruleId: 'constraints/$ruleId',
      severity: Severity.error,
      message: message,
      location: location,
      // A finding about the run, not the design: the headless binary fails
      // the run on it rather than counting it as one error.
      raw: const <String, dynamic>{Violation.analysisFailedKey: true},
    );

    // Refuse rather than check against a design we only have part of: the
    // ports are those of a design Yosys elaborated, and a design with its VHDL
    // removed does not elaborate to the same ports.
    if (request.droppedSources.isNotEmpty) {
      final dropped = request.droppedSources;
      final shown = dropped.take(3).join(', ');
      final more = dropped.length > 3 ? ' and ${dropped.length - 3} more' : '';
      yield didNotRun(
        'unsupported-sources',
        'Constraint check did not run: ${dropped.length} source file(s) were '
            'excluded because this engine supports Verilog and SystemVerilog '
            "only ($shown$more). The top module's ports come from the whole "
            'design, so a check against the remaining files could report '
            'ports the design does not have.',
        SourceLocation(file: dropped.first, line: 1, column: 1),
      );
      return;
    }

    final topModule = request.topModule;
    if (topModule == null || topModule.isEmpty) {
      yield didNotRun(
        'no-top-module',
        'Constraint check did not run: no top module is set, so there are no '
            'ports to check the constraint files against. Set the top module '
            'in the project, or pass --top.',
        SourceLocation(file: firstConstraint, line: 1, column: 1),
      );
      return;
    }

    // Read every constraint file before starting Yosys, so a file that cannot
    // be read costs no elaboration.
    final parsed = <ParsedConstraintFile>[];
    var unreadable = false;
    for (final path in request.constraintFiles) {
      final format = ConstraintFormat.fromPath(path);
      final problem = format == null
          ? 'its extension is not one of ${ConstraintFormat.extensionList}'
          : await _readProblem(path);
      if (format == null || problem != null) {
        unreadable = true;
        yield didNotRun(
          'constraint-file-unreadable',
          'Constraint check did not run: ${p.basename(path)} cannot be read, '
              '$problem.',
          SourceLocation(file: path, line: 1, column: 1),
        );
        continue;
      }
      parsed.add(
        ParsedConstraintFile(
          path: path,
          format: format,
          result: await parseConstraintLines(format, _linesOf(path)),
        ),
      );
    }
    if (unreadable) return;

    final fallback = SourceLocation(
      file: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
      line: 1,
      column: 1,
    );
    final elaborated = await elaborateDesign(
      request,
      engineId: id,
      processRunner: processRunner,
      tempDirectory: tempDirectory,
      bundledBinaryResolver: bundledBinaryResolver,
    );
    final String rawJson;
    switch (elaborated) {
      case DesignElaborated(rawJson: final json):
        rawJson = json;
      case DesignElaborationFailed(:final stderr):
        yield didNotRun(
          'elaboration-failed',
          'Constraint check could not elaborate the design: ${stderr.trim()}',
          fallback,
        );
        return;
    }

    final ports = readTopModulePorts(rawJson, topModule);
    if (ports == null) {
      yield didNotRun(
        'elaboration-failed',
        'Constraint check could not find module `$topModule` in the '
            'elaborated design.',
        fallback,
      );
      return;
    }

    final findings = checkConstraints(
      ports: ports,
      files: parsed,
      topModule: topModule,
    );
    for (final finding in findings) {
      yield _violationFor(finding, firstConstraint);
    }
  }

  Violation _violationFor(ConstraintFinding finding, String firstConstraint) {
    final declaration = finding.declaration;
    final location = declaration != null
        ? SourceLocation(
            file: declaration.file,
            line: declaration.line,
            column: declaration.column,
          )
        : SourceLocation(
            file: finding.file ?? firstConstraint,
            line: finding.line,
            column: finding.column,
          );
    return Violation(
      engineId: id,
      ruleId: 'constraints/${finding.ruleId}',
      severity: finding.severity,
      message: finding.message,
      location: location,
      raw: <String, dynamic>{
        if (finding.port != null) 'port': finding.port,
        if (finding.pin != null) 'pin': finding.pin,
        if (finding.file != null) 'constraint_file': finding.file,
      },
    );
  }

  /// Why [path] cannot be read as a constraint file, or `null` when it can.
  ///
  /// Constraint files are read like source files: a regular file that exists,
  /// within a size bound, and read as a stream of lines (never one string
  /// holding the whole file).
  Future<String?> _readProblem(String path) async {
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.notFound) return 'the file does not exist';
    if (type != FileSystemEntityType.file) return 'it is not a regular file';
    final length = await File(path).length();
    if (length > kMaxConstraintFileBytes) {
      return 'it is larger than ${kMaxConstraintFileBytes ~/ (1024 * 1024)} MiB';
    }
    return null;
  }

  Stream<String> _linesOf(String path) => File(path)
      .openRead()
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  @override
  void cancel() {
    // One short Yosys subprocess and a bounded file read; there is no
    // streaming parse of engine output to interrupt.
  }
}
