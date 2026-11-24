// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// `lintcrux waivers <project> --json`: the waivers in force for a project.
///
/// Read only. There is no command that writes a waiver or a baseline: an
/// agent that could waive a finding could make any lint run clean, and a
/// waiver is a person's decision.
///
/// What the open-core command line lists:
///
/// - `inline`: each `verilator lint_off` ... `lint_on` range in the
///   project's sources, which LintCrux applies itself (`PragmaWaiverReader`);
/// - `vlt`: each `lint_off` line of the Verilator configuration files the
///   project hands Verilator (`perEngineOptions.verilator.waiverFiles`);
/// - `baseline`: each finding frozen in the project's
///   `.lintcrux-baseline.json`, which `--fail-on-new-violations` does not
///   count as new.
///
/// The project's managed waivers (`.lintcrux-waivers.json`) are LintCrux
/// Pro's; this binary holds no Pro code, so it says they were withheld.
library;

import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/headless/lint_document.dart';
import 'package:lintcrux/services/headless/cli_baseline_reader.dart';
import 'package:lintcrux/services/headless/headless_input_resolver.dart';
import 'package:lintcrux/services/waivers/pragma_waiver_reader.dart';
import 'package:path/path.dart' as p;

/// The command's name, which is also the tool's.
const String kWaiversCommand = 'waivers';

/// The `perEngineOptions.verilator` key naming Verilator configuration
/// files, as `VerilatorEngine` reads it.
const String kVerilatorWaiverFilesOption = 'waiverFiles';

/// The document `lintcrux waivers <projectPath> --json` writes.
///
/// [extra] are warnings the caller adds; the open-core binary passes the
/// managed-waiver withholding from [openCoreManagedWaiversWithheld].
Future<McpDocument> waiversDocument({
  required McpProgram program,
  required String projectPath,
  List<McpDiagnostic> Function(LintProject project)? extra,
  HeadlessInputResolver resolver = const HeadlessInputResolver(),
}) async {
  if (p.extension(projectPath).toLowerCase() !=
      HeadlessInputResolver.projectExtension) {
    return McpDocument.usage(
      tool: program,
      command: kWaiversCommand,
      message:
          '`$projectPath` is not a .lintcrux project; `waivers` reads the '
          'waivers of a project.',
    );
  }
  final resolution = await resolver.resolve(<String>[projectPath]);
  if (!resolution.isSuccess) {
    final loadFailed = resolution.kind == HeadlessInputFailureKind.loadFailed;
    return McpDocument(
      tool: program,
      command: kWaiversCommand,
      outcome: loadFailed ? McpOutcome.inputError : McpOutcome.usageError,
      diagnostics: <McpDiagnostic>[
        for (final problem in resolution.problems)
          McpDiagnostic.error(loadFailed ? 'input.project' : 'usage', problem),
      ],
    );
  }
  final project = resolution.project!;
  final warnings = <McpDiagnostic>[...?extra?.call(project)];
  final waivers = <Map<String, Object?>>[];

  final pragmas = await const PragmaWaiverReader().readFiles(
    project.sourceFiles,
  );
  final inline = List<PragmaWaiver>.of(pragmas.waivers)
    ..sort((a, b) {
      final c = a.file.compareTo(b.file);
      return c != 0 ? c : a.startLine.compareTo(b.startLine);
    });
  for (final w in inline) {
    waivers.add(
      _waiver(
        kind: 'inline',
        rule: w.namespacedRuleId,
        scope: _at(w.file, w.startLine),
        pattern: 'lines ${w.startLine}-${w.endLine}',
      ),
    );
  }

  for (final file in verilatorWaiverFiles(project)) {
    final List<String> lines;
    try {
      lines = File(file).readAsLinesSync();
    } on FileSystemException catch (e) {
      warnings.add(
        McpDiagnostic.warning(
          'waivers.unreadable',
          'The Verilator configuration file $file could not be read: '
              '${e.message}.',
        ),
      );
      continue;
    }
    for (var i = 0; i < lines.length; i++) {
      final directive = parseVltLintOff(lines[i]);
      if (directive == null) continue;
      waivers.add(
        _waiver(
          kind: 'vlt',
          rule: directive.rule,
          scope: _at(file, i + 1),
          pattern: directive.text,
        ),
      );
    }
  }

  final baselinePath = CliBaselineReader.resolvePath(
    projectRoot: project.rootPath,
  );
  final read = await const CliBaselineReader().read(baselinePath);
  if (read.isCorrupt) {
    warnings.add(
      McpDiagnostic.warning(
        'baseline.unreadable',
        'The baseline $baselinePath could not be read: ${read.error}.',
      ),
    );
  }
  final baseline = read.baseline;
  if (baseline != null) {
    for (final entry in baseline.frozenViolations) {
      // Recorded on the machine the baseline was set on; rebased onto this
      // checkout when it was inside that project.
      final file =
          p.isAbsolute(entry.filePath) &&
              p.isWithin(baseline.projectPath, entry.filePath)
          ? p.join(
              project.rootPath,
              p.relative(entry.filePath, from: baseline.projectPath),
            )
          : entry.filePath;
      waivers.add(
        _waiver(
          kind: 'baseline',
          rule: entry.ruleId,
          scope: p.isAbsolute(file) && entry.line >= 1
              ? _at(file, entry.line)
              : null,
          pattern: entry.message,
          author: baseline.createdBy,
        ),
      );
    }
  }

  return McpDocument(
    tool: program,
    command: kWaiversCommand,
    outcome: McpOutcome.completed,
    body: <String, Object?>{'total': waivers.length, 'waivers': waivers},
    diagnostics: warnings,
  );
}

Map<String, Object?> _at(String file, int line) => <String, Object?>{
  'file': file,
  'line': line,
  'column': null,
};

Map<String, Object?> _waiver({
  required String kind,
  required String rule,
  required Map<String, Object?>? scope,
  required String? pattern,
  String? author,
}) => <String, Object?>{
  'kind': kind,
  'rule': rule,
  'scope': scope,
  'pattern': pattern,
  'reason': null,
  'author': author,
  'expires': null,
  'expired': false,
};

/// The Verilator configuration files [project] hands Verilator, absolute:
/// relative entries are taken against the project root, where Verilator
/// runs.
List<String> verilatorWaiverFiles(LintProject project) {
  final raw =
      project.perEngineOptions['verilator']?[kVerilatorWaiverFilesOption];
  if (raw is! List) return const <String>[];
  return <String>[
    for (final entry in raw)
      if (entry is String && entry.isNotEmpty)
        p.normalize(
          p.isAbsolute(entry) ? entry : p.join(project.rootPath, entry),
        ),
  ];
}

/// One `lint_off` line of a Verilator configuration file.
class VltLintOff {
  /// The waiver of [rule] written as [text].
  const VltLintOff(this.rule, this.text);

  /// `verilator/<rule>`, or `verilator/*` for a `lint_off` naming no rule.
  final String rule;

  /// The directive as written, without its comment.
  final String text;
}

final RegExp _lintOff = RegExp(r'^\s*lint_off\b');
final RegExp _ruleArg = RegExp(r'-(?:rule|msg)\s+([A-Za-z0-9_*]+)');

/// [line] as a `lint_off` directive, or `null` when it is not one.
VltLintOff? parseVltLintOff(String line) {
  final comment = line.indexOf('//');
  final code = (comment >= 0 ? line.substring(0, comment) : line).trim();
  if (!_lintOff.hasMatch(code)) return null;
  final rule = _ruleArg.firstMatch(code)?.group(1) ?? '*';
  return VltLintOff('verilator/$rule', code);
}

/// The open-core binary's word on managed waivers: a `licence.withheld`
/// warning when the project has a `.lintcrux-waivers.json`.
List<McpDiagnostic> openCoreManagedWaiversWithheld(LintProject project) =>
    openCoreWithheld(project, cdcRan: false);
