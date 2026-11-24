// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The engines the `spec/mcp/` goldens are written against: a Verilator and
/// a Verible that report fixed findings on `spec/fixtures/design/rtl/`, and
/// the ways an engine run ends badly. Every finding below is what the
/// goldens were derived from by hand; nothing here runs a process.
library;

import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:path/path.dart' as p;

/// How the spec's Verible run ends.
enum SpecScenario {
  /// Both engines complete.
  ok,

  /// Verible is killed by the watchdog.
  timesOut,

  /// Verible is not installed.
  missing,

  /// Verible crashes.
  crashes;

  /// The scenario named [name] in `spec/mcp/cases.json`.
  static SpecScenario named(String name) => switch (name) {
    'ok' => ok,
    'times_out' => timesOut,
    'missing' => missing,
    'crashes' => crashes,
    _ => throw ArgumentError.value(name, 'engines'),
  };
}

/// An engine that reports [findings] for each source it is handed, or
/// throws [failure].
class SpecEngine implements LintEngine {
  /// An engine called [id] at [version].
  SpecEngine(this.id, this.version, this.findings, {this.failure});

  @override
  final String id;

  /// What `detectVersion` answers.
  final String version;

  /// The findings for one source file, by its absolute path.
  final List<Violation> Function(String file) findings;

  /// Thrown from the run instead of reporting, when given.
  final Object? failure;

  /// The requests this engine was run with.
  final List<LintRunRequest> requests = <LintRunRequest>[];

  @override
  String get displayName => id;

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog, HdlLanguage.verilog},
  );

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => version;

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    requests.add(request);
    final e = failure;
    // The engine exceptions implement Exception rather than extend it.
    // ignore: only_throw_errors
    if (e != null) throw e;
    for (final file in request.sourceFiles) {
      yield* Stream<Violation>.fromIterable(findings(file));
    }
  }

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  void cancel() {}
}

Violation _v(
  String engine,
  String rule,
  Severity severity,
  String message,
  String file,
  int line,
  int column, {
  List<SourceLocation> related = const <SourceLocation>[],
  Map<String, dynamic> raw = const <String, dynamic>{},
}) => Violation(
  engineId: engine,
  ruleId: rule,
  severity: severity,
  message: message,
  location: SourceLocation(file: file, line: line, column: column),
  relatedLocations: related,
  raw: raw,
);

/// Verilator's findings on `rtl/top.sv` and `rtl/fifo.sv`.
List<Violation> verilatorFindings(String file) => switch (p.basename(file)) {
  'top.sv' => <Violation>[
    _v(
      'verilator',
      'verilator/WIDTH',
      Severity.warning,
      "Operator ASSIGNW expects 8 bits on the Assign RHS, but Assign RHS's "
          "CONST '32'h1' generates 32 bits.",
      file,
      6,
      14,
      related: <SourceLocation>[
        SourceLocation(file: file, line: 4, column: 22),
      ],
      raw: <String, dynamic>{'widthExpected': 8, 'widthActual': 32},
    ),
    _v(
      'verilator',
      'verilator/UNUSEDSIGNAL',
      Severity.warning,
      "Signal is not used: 'dbg'",
      file,
      7,
      9,
    ),
    // Inside `// verilator lint_off UNUSEDSIGNAL` (lines 8 to 10).
    _v(
      'verilator',
      'verilator/UNUSEDSIGNAL',
      Severity.warning,
      "Signal is not used: 'dbg_unused'",
      file,
      9,
      9,
    ),
  ],
  'fifo.sv' => <Violation>[
    _v(
      'verilator',
      'verilator/UNUSEDSIGNAL',
      Severity.warning,
      "Signal is not used: 'spare'",
      file,
      6,
      15,
    ),
  ],
  _ => const <Violation>[],
};

/// Verible's findings on `rtl/fifo.sv`.
List<Violation> veribleFindings(String file) => switch (p.basename(file)) {
  'fifo.sv' => <Violation>[
    _v(
      'verible',
      'verible/explicit-begin',
      Severity.note,
      'All block constructs shall explicitly use begin/end.',
      file,
      7,
      3,
    ),
  ],
  _ => const <Violation>[],
};

/// The spec's two engines, Verible ending as [scenario] says.
EngineRegistry specRegistry(SpecScenario scenario) => EngineRegistry(
  <LintEngine>[
    SpecEngine('verilator', '5.020', verilatorFindings),
    SpecEngine(
      'verible',
      'v0.0-3946-g851d3ff4',
      veribleFindings,
      failure: switch (scenario) {
        SpecScenario.ok => null,
        SpecScenario.timesOut => const EngineTimedOutException(
          engineId: 'verible',
          timeout: Duration(seconds: 300),
        ),
        SpecScenario.missing => const EngineNotAvailableException(
          engineId: 'verible',
          reason: 'verible was not found on PATH',
        ),
        SpecScenario.crashes => StateError('verible stopped with signal 11'),
      },
    ),
  ],
);
