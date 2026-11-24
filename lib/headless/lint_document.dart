// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The `lintcrux ... --json` document: a headless run in `crux_mcp`'s
/// eight-member envelope.
///
/// One builder for both doors: the command line writes [buildLintDocument]'s
/// text to stdout, and `lintcrux mcp`'s `lint` tool returns the same text as
/// its `content[0]`. The exit code stays LintCrux's own
/// ([HeadlessRunResult.exitCode]); the document says the outcome, and the
/// document is the authority.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crux_mcp/crux_mcp.dart';
import 'package:crypto/crypto.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart'
    show baselineFingerprintFor;
import 'package:lintcrux/domain/models/engine_run_outcome.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/export/violation_exporters.dart';
import 'package:lintcrux/services/headless/headless_run_result.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart' show SarifWriter;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The program every LintCrux document names.
const String kLintcruxProgramName = 'lintcrux';

/// The `command` of a lint run's document. Linting is the bare `lintcrux`
/// command line; the document still names it.
const String kLintCommand = 'lint';

/// The environment variable a LintCrux licence file is named by.
const String kLintcruxLicenseEnv = 'LINTCRUX_LICENSE_FILE';

/// The `design.fingerprint.scheme` of a lint document: SHA-256 over one line
/// per source file, in project order: the SHA-256 of its bytes in hex, two
/// spaces, its path relative to the project root with `/` separators, and a
/// newline (`sha256sum`'s format).
const String kLintSourcesFingerprintScheme = 'lintcrux-sources-sha256/1';

/// The managed-waiver file LintCrux Pro reads from a project's root.
const String kManagedWaiverFileName = '.lintcrux-waivers.json';

/// What a run's outcome is, and the error diagnostics that say why.
@immutable
class LintClassification {
  /// [outcome], with [errors] saying why when it is not `completed`.
  const LintClassification(this.outcome, this.errors);

  /// How the run ended.
  final McpOutcome outcome;

  /// One error diagnostic per reason; empty for `completed`.
  final List<McpDiagnostic> errors;
}

/// Maps a headless run to its outcome. [classifyLintRun] is the one the
/// binary uses; the type exists so a test can prove a broken mapping is
/// caught.
typedef LintRunClassifier =
    LintClassification Function(HeadlessRunResult result);

/// The outcome of [result], decided by what went wrong first and by the
/// exit code only when nothing did.
///
/// - Any problem the run recorded makes it a non-answer: an engine that
///   failed, timed out, was missing or cancelled, or could not analyse the
///   design is `engine_error`; otherwise an unusable input is `input_error`
///   and an unusable command line `usage_error`. Each problem is one error
///   diagnostic. The findings an engine did return stay in the body, marked
///   partial by that outcome.
/// - With no problem, exit 1, 2 and 4 are LintCrux's three gates, so
///   `failed_gate`, with the gate that fired as the error; exit 0 is
///   `completed`.
LintClassification classifyLintRun(HeadlessRunResult result) {
  final failures = _failuresOf(result);
  if (failures.isNotEmpty) {
    final kinds = failures.map((f) => f.kind).toSet();
    final outcome = kinds.contains(HeadlessFailureKind.engine)
        ? McpOutcome.engineError
        : kinds.contains(HeadlessFailureKind.input) ||
              kinds.contains(HeadlessFailureKind.output)
        ? McpOutcome.inputError
        : McpOutcome.usageError;
    return LintClassification(outcome, <McpDiagnostic>[
      for (final f in failures) McpDiagnostic.error(f.code, f.message),
    ]);
  }
  final reportable = result.reportableViolations.length;
  switch (result.exitCode) {
    case CliExitCode.clean:
      return const LintClassification(McpOutcome.completed, <McpDiagnostic>[]);
    case CliExitCode.violations:
      return LintClassification(McpOutcome.failedGate, <McpDiagnostic>[
        McpDiagnostic.error(
          'gate.findings',
          '$reportable ${_findings(reportable)} remain, and --exit-code fails '
              'the run on any.',
        ),
      ]);
    case CliExitCode.newViolations:
      final fresh = result.newViolations.length;
      return LintClassification(McpOutcome.failedGate, <McpDiagnostic>[
        McpDiagnostic.error(
          'gate.new_findings',
          '$fresh ${_findings(fresh)} not in the baseline, and '
              '--fail-on-new-violations fails the run on them.',
        ),
      ]);
    case CliExitCode.overThreshold:
      return LintClassification(McpOutcome.failedGate, <McpDiagnostic>[
        McpDiagnostic.error(
          'gate.threshold',
          '$reportable ${_findings(reportable)} remain, over the '
              "organisation's ciGateThreshold.",
        ),
      ]);
    default:
      return LintClassification(McpOutcome.engineError, <McpDiagnostic>[
        McpDiagnostic.error(
          'run.failed',
          'The run ended with exit ${result.exitCode} and gave no reason.',
        ),
      ]);
  }
}

String _findings(int n) => n == 1 ? 'finding' : 'findings';

/// [result]'s classified problems; for a result made by code that did not
/// classify them, each problem under the kind its exit code names.
List<HeadlessFailure> _failuresOf(HeadlessRunResult result) {
  if (result.failures.isNotEmpty) return result.failures;
  if (result.problems.isEmpty) return const <HeadlessFailure>[];
  final (kind, code) = switch (result.exitCode) {
    CliExitCode.usage => (HeadlessFailureKind.usage, 'usage'),
    CliExitCode.dataError => (HeadlessFailureKind.input, 'input.import'),
    _ => (HeadlessFailureKind.engine, 'run.failed'),
  };
  return <HeadlessFailure>[
    for (final problem in result.problems) HeadlessFailure(kind, code, problem),
  ];
}

/// The baseline state of one finding: `new`, `existing`, or `null` when the
/// project has no baseline.
typedef LintBaselineState = String? Function(Violation violation);

/// No baseline: every finding's state is `null`.
String? noBaseline(Violation violation) => null;

/// The `--json` document of [result].
///
/// [limit] and [offset] page the findings; the counts and `total` cover
/// all of them. [engines] is the envelope's `engines` member and [design]
/// its `design`; [baseline] gives each finding's baseline state; [extra]
/// are warnings the caller adds (a withheld part, an unreadable baseline).
/// The body is present when the engines ran, whatever the outcome: the
/// findings of a run in which an engine failed stay, marked partial by the
/// outcome.
McpDocument buildLintDocument({
  required McpProgram program,
  required HeadlessRunResult result,
  int limit = CliArgsParser.kDefaultLimit,
  int offset = 0,
  List<McpEngine> engines = const <McpEngine>[],
  McpDesignFingerprint? design,
  LintBaselineState baseline = noBaseline,
  List<McpDiagnostic> extra = const <McpDiagnostic>[],
  LintRunClassifier classify = classifyLintRun,
}) {
  final classification = classify(result);
  final ran = result.statuses.isNotEmpty;
  return McpDocument(
    tool: program,
    command: kLintCommand,
    outcome: classification.outcome,
    engines: ran ? engines : const <McpEngine>[],
    design: ran ? design : null,
    body: ran
        ? _body(
            result,
            limit: limit,
            offset: offset,
            baseline: baseline,
          )
        : null,
    diagnostics: <McpDiagnostic>[
      ...classification.errors,
      ...extra,
      for (final note in result.diagnostics)
        McpDiagnostic(
          severity: McpSeverity.note,
          code: 'run.note',
          message: note,
        ),
    ],
  );
}

Map<String, Object?> _body(
  HeadlessRunResult result, {
  required int limit,
  required int offset,
  required LintBaselineState baseline,
}) {
  final root = result.project?.rootPath ?? '';
  final all = List<Violation>.of(result.violations)..sort(_findingOrder);
  final start = offset < all.length ? offset : all.length;
  final end = start + limit < all.length ? start + limit : all.length;
  final page = all.sublist(start, end);
  final counts = <Severity, int>{
    for (final v in result.reportableViolations) v.severity: 0,
  };
  for (final v in result.reportableViolations) {
    counts[v.severity] = counts[v.severity]! + 1;
  }
  const exporters = ViolationExporters();
  return <String, Object?>{
    'project': result.projectFilePath,
    'top': result.project?.topModule,
    'engine_runs': <Object?>[
      for (final id in result.statuses.keys.toList()..sort())
        _engineRun(result.statuses[id]!, result.engineOutcomes[id]),
    ],
    'counts': <String, Object?>{
      'fatal': counts[Severity.fatal] ?? 0,
      'error': counts[Severity.error] ?? 0,
      'warning': counts[Severity.warning] ?? 0,
      'note': counts[Severity.note] ?? 0,
      'suppressed': result.suppressedCount,
    },
    'total': all.length,
    'returned': page.length,
    'offset': offset,
    'truncated': end < all.length,
    'findings': <Object?>[
      for (final v in page)
        <String, Object?>{
          ...exporters.jsonElement(v),
          'raw': _raw(v.raw),
          'signature': baselineFingerprintFor(v, projectRoot: root),
          'baseline': baseline(v),
        },
    ],
  };
}

Map<String, Object?> _engineRun(
  EngineRunStatus status,
  EngineRunOutcome? outcome,
) {
  final phase = switch (status.phase) {
    EngineRunPhase.completed => 'completed',
    EngineRunPhase.unavailable => 'unavailable',
    EngineRunPhase.cancelled => 'cancelled',
    // An engine that never reached an end did not complete.
    EngineRunPhase.failed ||
    EngineRunPhase.idle ||
    EngineRunPhase.running => 'failed',
  };
  return <String, Object?>{
    'id': status.engineId,
    'phase': phase,
    'timed_out': outcome == EngineRunOutcome.timeout,
    'message': status.phase == EngineRunPhase.completed
        ? null
        : (status.error ?? 'the engine did not finish'),
  };
}

/// Findings in a fixed order, whatever order the engines finished in, so
/// a page is the same page on every run: file, line, column, engine, rule,
/// message.
int _findingOrder(Violation a, Violation b) {
  var c = a.location.file.compareTo(b.location.file);
  if (c != 0) return c;
  c = a.location.line.compareTo(b.location.line);
  if (c != 0) return c;
  c = a.location.column.compareTo(b.location.column);
  if (c != 0) return c;
  c = a.engineId.compareTo(b.engineId);
  if (c != 0) return c;
  c = a.ruleId.compareTo(b.ruleId);
  if (c != 0) return c;
  return a.message.compareTo(b.message);
}

/// The `raw` member: the engine's own facts (a CDC crossing's domains and
/// registers), without the SARIF structures a result was read with, which
/// the writers drop as well. `null` when there are none.
Object? _raw(Map<String, dynamic> raw) {
  final kept = <String, Object?>{
    for (final e in raw.entries)
      if (!SarifWriter.sarifResultKeys.contains(e.key))
        e.key: _jsonSafe(e.value),
  };
  return kept.isEmpty ? null : kept;
}

Object? _jsonSafe(Object? value) => switch (value) {
  null || bool() || int() || String() => value,
  final double d => d.isFinite ? d : d.toString(),
  final List<Object?> l => <Object?>[for (final e in l) _jsonSafe(e)],
  final Map<Object?, Object?> m => <String, Object?>{
    for (final e in m.entries) '${e.key}': _jsonSafe(e.value),
  },
  _ => value.toString(),
};

/// The `design` member for [project]: [kLintSourcesFingerprintScheme] over
/// its source files, or `null` when one cannot be read.
McpDesignFingerprint? lintSourcesFingerprint(LintProject project) {
  final lines = StringBuffer();
  for (final file in project.sourceFiles) {
    final List<int> bytes;
    try {
      bytes = File(file).readAsBytesSync();
    } on FileSystemException {
      return null;
    }
    final relative = p.isWithin(project.rootPath, file)
        ? p.relative(file, from: project.rootPath)
        : file;
    lines
      ..write(sha256.convert(bytes))
      ..write('  ')
      ..write(p.split(relative).join('/'))
      ..write('\n');
  }
  return McpDesignFingerprint(
    scheme: kLintSourcesFingerprintScheme,
    value: sha256.convert(utf8.encode(lines.toString())).toString(),
  );
}

/// The parts of a lint answer the open-core binary leaves out, each a
/// `licence.withheld` warning: the project's managed waivers, and, when the
/// CDC engine ran beside a `cdc.yaml`, the Pro CDC analysis. This binary
/// holds no Pro code and reads no licence, so the fix names LintCrux Pro.
List<McpDiagnostic> openCoreWithheld(
  LintProject project, {
  required bool cdcRan,
}) {
  const gate = McpTierGate(environmentVariable: kLintcruxLicenseEnv);
  McpDiagnostic withheld(String what) {
    final d = gate.withhold(what, tier: 'Pro');
    return McpDiagnostic.warning(
      d.code,
      d.message,
      fix:
          'LintCrux Pro does this under a Pro licence; this open-core '
          'command line reads no licence.',
    );
  }

  final managed = File(p.join(project.rootPath, kManagedWaiverFileName));
  final cdcYaml = <String>{
    p.join(project.rootPath, 'cdc.yaml'),
    for (final f in project.sourceFiles) p.join(p.dirname(f), 'cdc.yaml'),
  }.any((path) => File(path).existsSync());
  return <McpDiagnostic>[
    if (managed.existsSync())
      withheld(
        "Applying the project's managed waivers ($kManagedWaiverFileName)",
      ),
    if (cdcRan && cdcYaml)
      withheld('Tracing CDC clock trees and applying cdc.yaml'),
  ];
}
