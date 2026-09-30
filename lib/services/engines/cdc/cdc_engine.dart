// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show Directory;

import 'package:crux_netlist/crux_netlist.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/cdc/cdc_domain_analysis.dart';
import 'package:lintcrux/services/engines/cdc/cdc_source_span.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';
import 'package:meta/meta.dart';

/// Clock-domain-crossing analysis as a LintCrux engine.
///
/// **One more engine in the existing pipeline, not a new product.** Findings
/// are ordinary [Violation]s, so they flow through the existing violation
/// store, waivers, trends, SARIF export and CXP cross-probe with no
/// CDC-specific code in any of those paths: this file is a translator from
/// crossings to violations and nothing more.
///
/// **Scope, stated plainly because over-claiming here is the real risk.** This
/// is *structural CDC lint*, not sign-off CDC. It has no clock-relationship
/// model — every pair of distinct clock nets is treated as asynchronous — and
/// it does not do reconvergence or reset-domain analysis. A tool that flags
/// five thousand crossings on a chip, of which nearly all are fine, teaches
/// engineers to ignore it and takes the rest of the suite's credibility with
/// it. The bounded honest version ships first on purpose.
class CdcEngine implements LintEngine {
  /// Creates the engine.
  ///
  /// CDC starts no binary of its own: it runs Yosys, resolved from
  /// [LintRunRequest.binary] per run (see [yosysExecutableFor]). The planner
  /// hands it the Yosys binary configuration (see `binaryEngineIdFor`).
  /// [processRunner] and [tempDirectory] are the seams handed to the
  /// `YosysRunner` built for each run.
  CdcEngine({
    this.processRunner = const DefaultProcessRunner(),
    this.tempDirectory,
    this.analysis = const CdcDomainAnalysis(),
    this.parser = const YosysJsonParser(),
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

  /// The domain analysis. Injectable so the engine can be tested without
  /// re-deriving crossings.
  final CdcDomainAnalysis analysis;

  /// The analysis to use for one run.
  ///
  /// A hook rather than a plain field read because the Pro overlay's analysis
  /// depends on the *request*: it loads `cdc.yaml` from the directory holding
  /// the sources, so it cannot be fixed at construction time. Open core has no
  /// per-run input and returns [analysis] unchanged.
  ///
  /// Resolving constraints from the source directory rather than from a
  /// provider is deliberate — it is the one approach that works identically in
  /// the GUI and in `lintcrux --ci`, and CI is where a CDC gate actually
  /// belongs.
  @protected
  @visibleForOverriding
  CdcDomainAnalysis analysisFor(LintRunRequest request) => analysis;

  /// The Yosys JSON parser.
  final YosysJsonParser parser;

  @override
  String get id => 'cdc';

  @override
  String get displayName => 'CDC';

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.verilog, HdlLanguage.systemVerilog},
    emitsStructuredOutput: true,
    // NOT CACHEABLE, and both reasons are load-bearing.
    //
    // The lint cache keys on (source fingerprints, request config, engine
    // version). For CDC the "engine version" is the *yosys* version, because
    // that is the only binary involved -- but the analysis itself is Dart in
    // this repo. So shipping an improved CDC analysis changes nothing about
    // the key, and every user with a warm cache keeps getting the old answer
    // from the new build. That is not a stale-data annoyance; it means a fix
    // cannot be delivered.
    //
    // Worse, the Pro layer reads `cdc.yaml` from beside the sources. It is not
    // in `sourceFiles`, so the key is blind to it: a user edits their
    // constraints, re-runs, and the findings do not move. The feature would
    // appear broken while working perfectly.
    //
    // The cost of opting out is one yosys invocation per run, which is what
    // the yosys check engine already pays.
    cacheable: false,
    // CDC is whole-design analysis by nature: a crossing is a relationship
    // between two modules, so re-analysing one changed file in isolation would
    // answer a different question. Incremental is not merely unimplemented
    // here, it is not meaningful.
  );

  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);

  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async {
    final probe = await YosysAvailabilityService(
      runner: processRunner,
      executableNameOverride: yosysExecutableFor(
        config,
        resolver: bundledBinaryResolver,
      ),
    ).probe();
    return probe.isAvailable ? probe.versionString : null;
  }

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    // Refuse rather than analyse a design we only have part of.
    //
    // CDC elaborates the WHOLE design -- it needs `flatten` for a crossing
    // between two instances to be visible at all. If the language router
    // dropped sources for this engine (VHDL, today: the CDC engine declares
    // only Verilog and SystemVerilog), the survivors reference modules that
    // are no longer present, Yosys fails `hierarchy -check` with a
    // missing-module error, and the user is told CDC "could not elaborate
    // the design" with a Yosys diagnostic that names a module rather than
    // the real cause.
    //
    // A per-file linter can legitimately skip what it does not understand.
    // An analysis over a whole design cannot: a CDC report from a partial
    // netlist is not a smaller report, it is a wrong one -- the crossings it
    // cannot see are exactly the ones spanning the excluded language.
    if (request.droppedSources.isNotEmpty) {
      final dropped = request.droppedSources;
      final shown = dropped.take(3).join(', ');
      final more = dropped.length > 3 ? ' and ${dropped.length - 3} more' : '';
      yield Violation(
        engineId: id,
        ruleId: 'cdc/unsupported-sources',
        severity: Severity.error,
        message:
            'CDC analysis did not run: ${dropped.length} source file(s) were '
            'excluded because this engine supports Verilog and SystemVerilog '
            'only ($shown$more). CDC elaborates the whole design, so a result '
            'from the remaining files would miss any crossing that involves '
            'the excluded ones.',
        location: SourceLocation(file: dropped.first, line: 1, column: 1),
      );
      return;
    }

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
      YosysRunRequest(
        sources: <YosysSourceFile>[
          for (final f in request.sourceFiles) YosysSourceFile(f),
        ],
        topModule: request.topModule,
        // `flatten` is required rather than cosmetic: without it every module
        // is its own scope and a crossing *between* two instances is invisible,
        // which is most of the crossings that matter.
        //
        // `opt` is deliberately absent. It folds and rewrites exactly the
        // structure this analysis reads — a two-flop synchronizer can be
        // retimed or merged, at which point a correct design starts reporting
        // as unsafe. A CDC-safe pass list is a real constraint, not a
        // preference.
        extraCommands: const <String>['flatten'],
      ),
    );

    // A Yosys that could not be started, timed out, could not be handed the
    // request, or ended without its JSON output is a tool failure, not a
    // property of the design. Reporting it as a finding would let a machine
    // without `yosys` produce a run that "completed" — one that a gate passes
    // and a baseline can freeze, turning CDC off for good. Only a genuine
    // non-zero Yosys exit on real RTL is a finding about the design.
    final YosysRunSuccess elaborated;
    switch (result) {
      case YosysRunSuccess():
        elaborated = result;
      case YosysRunFailure(:final stderr) when isYosysDesignFailure(result):
        yield Violation(
          engineId: id,
          ruleId: 'cdc/elaboration-failed',
          severity: Severity.error,
          message:
              'CDC analysis could not elaborate the design: ${stderr.trim()}',
          location: SourceLocation(
            file: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
            line: 1,
            column: 1,
          ),
        );
        return;
      case YosysRunFailure() || YosysRunTimeout() || YosysRunCancelled():
        throw yosysRunException(
          engineId: id,
          result: result,
          executable: executable,
        );
    }

    final NetlistModel model;
    try {
      model = parser.parse(elaborated.rawJson);
    } on Object catch (e) {
      yield Violation(
        engineId: id,
        ruleId: 'cdc/elaboration-failed',
        severity: Severity.error,
        message: 'CDC analysis could not read the elaborated netlist: $e',
        location: SourceLocation(
          file: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
          line: 1,
          column: 1,
        ),
      );
      return;
    }
    final cdc = analysisFor(
      request,
    ).analyze(model, topModuleName: request.topModule);
    final fallback = SourceLocation(
      file: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
      line: 1,
      column: 1,
    );

    var unsafe = 0;
    for (final crossing in cdc.crossings) {
      if (!crossing.isUnsafe) continue;
      unsafe++;
      yield _violationFor(crossing, fallback);
    }

    // ── Say what was analysed, even when nothing was wrong ────────────────
    //
    // Without this the engine is silent on a clean design, and silence is
    // indistinguishable from "the engine did not run", "no top module was
    // resolved", or "the whole design collapsed to one clock domain". A user
    // cannot act on that ambiguity, and the natural reading of it — that CDC
    // is broken — is the wrong one.
    //
    // `CdcAnalysisResult.diagnostics` existed for exactly this from the start
    // and was being discarded here, which made the field's own promise false.
    for (final note in cdc.diagnostics) {
      yield Violation(
        engineId: id,
        ruleId: 'cdc/analysis-note',
        severity: Severity.note,
        message: note,
        location: fallback,
      );
    }
    yield Violation(
      engineId: id,
      ruleId: 'cdc/summary',
      severity: Severity.note,
      message:
          'CDC analysed ${cdc.domains.length} clock domain(s) '
          '(${cdc.domains.map((d) => humanCdcClockName(d.clockName)).join(', ')}) '
          'and found '
          '${cdc.crossings.length} crossing(s), $unsafe unsafe.',
      location: fallback,
      raw: <String, dynamic>{
        'domains': cdc.domains.length,
        'crossings': cdc.crossings.length,
        'unsafe': unsafe,
      },
    );
  }

  /// Where a finding is reported: the **destination** register.
  ///
  /// That is where the unsafe sample happens and where a fix goes — adding a
  /// synchronizer is a change to the receiving side, not the driving one. The
  /// source register rides along in `relatedLocations` so the UI can show both
  /// ends of the crossing.
  ///
  /// The [fallback] is used only when Yosys recorded no `src` attribute. It
  /// deliberately keeps the old anchor shape rather than dropping the finding:
  /// a crossing you cannot place is still a crossing worth reporting. But note
  /// what it costs — every fallback finding lands on the same (file, line 1),
  /// so a waiver written against one waives all of them. That is the reason
  /// real spans matter here and not merely for navigation.
  Violation _violationFor(CdcCrossing crossing, SourceLocation fallback) {
    final location = _toLocation(crossing.destSpan) ?? fallback;
    final related = <SourceLocation>[
      if (_toLocation(crossing.sourceSpan) case final SourceLocation s) s,
    ];
    // Grammar, not decoration. The placeholder used to be the bare word
    // `Signal`, which produced "8-bit bus Signal crosses clk_a → clk_b" —
    // reading as though the net were called Signal. An unnamed net needs an
    // article, and a bus and a single bit need different ones.
    final named = crossing.netName != null;
    final busSubject = named
        ? '${crossing.width}-bit bus `${crossing.netName}`'
        : 'An unnamed ${crossing.width}-bit bus';
    final bitSubject = named ? '`${crossing.netName}`' : 'An unnamed signal';
    final src = humanCdcClockName(crossing.sourceClock);
    final dst = humanCdcClockName(crossing.destClock);
    final (ruleId, severity, message) = switch (crossing) {
      // Combinational logic between the two flops defeats the MTBF the chain
      // exists to provide — worse than no synchronizer, because it looks like
      // one to a reviewer.
      CdcCrossing(syncKind: CdcSyncKind.comboInSync) => (
        'cdc/combo-in-sync',
        Severity.error,
        'Combinational logic inside the synchronizer between '
            '${crossing.sourceClock} and ${crossing.destClock} — the two-flop '
            'chain no longer provides the settling time it exists for.',
      ),
      // Every bit individually two-flop synchronized, which is why this one is
      // an error rather than a pass: the bits resolve independently, so bits
      // that changed together in the source domain can land in different
      // destination cycles. The receiver sees a value that never existed. It is
      // more dangerous than leaving the bus unsynchronized because it looks
      // careful in review and all the metastability warnings go quiet.
      CdcCrossing(syncKind: CdcSyncKind.perBitSyncBus) => (
        'cdc/per-bit-sync-bus',
        Severity.error,
        '$busSubject crosses $src → $dst with a separate two-flop '
            'synchronizer per bit. Each bit is safe; the bus is not — bits '
            'can resolve in different cycles and the receiver sees a value '
            'that never existed. Use a handshake or an async FIFO.',
      ),
      // A bus crossing unsynchronized risks incoherence: the destination
      // latching a mix of old and new bits, a value that never existed in the
      // source domain. That is a different and more expensive bug than
      // metastability on a single bit, and it is nearly invisible in
      // simulation.
      CdcCrossing(width: final w) when w > 1 => (
        'cdc/unsync-multi-bit',
        Severity.error,
        '$busSubject crosses $src → $dst with no synchronizer. The '
            'destination can latch a mix of old and new bits — a value never '
            'present in the source domain.',
      ),
      _ => (
        'cdc/unsync-single-bit',
        Severity.warning,
        '$bitSubject crosses $src → $dst with no synchronizer; the '
            'destination flop can go metastable.',
      ),
    };

    return Violation(
      engineId: id,
      ruleId: ruleId,
      severity: severity,
      message: message,
      location: location,
      relatedLocations: related,
      raw: <String, dynamic>{
        'src_domain': crossing.sourceClock,
        'dst_domain': crossing.destClock,
        'width': crossing.width,
        'sync_kind': crossing.syncKind.name,
        'src_register': crossing.sourceRegisterPath,
        'dst_register': crossing.destRegisterPath,
        // `path` is the field the NetCrux cross-probe reads to highlight the
        // crossing in the schematic.
        if (crossing.netName case final String n) 'path': n,
      },
    );
  }

  /// Converts a Yosys-recovered span into the engine's location type.
  static SourceLocation? _toLocation(CdcSourceSpan? span) => span == null
      ? null
      : SourceLocation(file: span.file, line: span.line, column: span.column);

  @override
  void cancel() {
    // The Yosys run is a single short subprocess; there is no streaming parse
    // to interrupt. Left explicit rather than absent so a reader does not
    // assume cancellation was forgotten.
  }
}
