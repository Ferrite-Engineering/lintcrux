// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show Directory, FileSystemException;

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
import 'package:lintcrux/services/engines/cdc/cdc_netlist_reader.dart';
import 'package:lintcrux/services/engines/cdc/cdc_source_span.dart';
import 'package:lintcrux/services/engines/cdc/sv_package_use.dart';
import 'package:lintcrux/services/engines/yosys/yosys_elaboration.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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
    this.netlistReader = const CdcNetlistReader(),
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

  /// No longer consulted: the netlist is read by [netlistReader], which
  /// streams the document instead of decoding it whole. Kept so a subclass
  /// that forwards it still compiles.
  final YosysJsonParser parser;

  /// Reads the elaborated netlist, keeping only what the analysis uses.
  final CdcNetlistReader netlistReader;

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
        raw: const <String, dynamic>{Violation.analysisFailedKey: true},
      );
      return;
    }

    // SystemVerilog goes through yosys-slang when this Yosys has it. The
    // built-in `read_verilog -sv` stops on package scoping, `void` functions
    // and other constructs every package-based design uses; slang reads the
    // language. Verilog-only designs keep the built-in reader.
    final hasSystemVerilog = yosysSourcesFor(
      request,
    ).any((s) => s.language == YosysSourceLanguage.systemVerilog);
    final slang = hasSystemVerilog && await _hasSlang(request);

    // The netlist stays on disk and is read as a stream: a flattened SoC
    // writes hundreds of megabytes of JSON (OpenTitan earlgrey: 864 MB), and
    // holding that as a string and decoding it whole needed more memory than
    // the analysis itself. The directory is removed once the netlist is read.
    final scratch = _netlistScratchDirectory();
    final DesignElaboration elaborated;
    final NetlistModel? model;
    final Object? readError;
    try {
      // A Yosys that could not be started, timed out, could not be handed
      // the request, or ended without its JSON output is a tool failure, not
      // a property of the design: the helper throws for those. Reporting one
      // as a finding would let a machine without `yosys` produce a run that
      // "completed" — one that a gate passes and a baseline can freeze,
      // turning CDC off for good. Only a genuine non-zero Yosys exit on real
      // RTL is a finding about the design.
      elaborated = await elaborateDesign(
        request,
        engineId: id,
        processRunner: processRunner,
        tempDirectory: tempDirectory,
        bundledBinaryResolver: bundledBinaryResolver,
        // `flatten` is required rather than cosmetic: without it every module
        // is its own scope and a crossing *between* two instances is
        // invisible, which is most of the crossings that matter.
        //
        // `opt` is deliberately absent. It folds and rewrites exactly the
        // structure this analysis reads — a two-flop synchronizer can be
        // retimed or merged, at which point a correct design starts reporting
        // as unsafe. A CDC-safe pass list is a real constraint, not a
        // preference.
        extraCommands: const <String>['flatten'],
        frontend: slang ? YosysFrontend.slang : YosysFrontend.verilog,
        slangOptions: slang ? slangOptionsFor(request) : const <String>[],
        netlistPath: scratch == null
            ? null
            : p.join(scratch.path, 'netlist.json'),
      );
      (model, readError) = switch (elaborated) {
        DesignElaborated() => _readNetlist(elaborated, request.topModule),
        DesignElaborationFailed() => (null, null),
      };
    } finally {
      _removeScratch(scratch);
    }

    switch (elaborated) {
      case DesignElaborated():
        break;
      case DesignElaborationFailed(:final stderr):
        // The built-in reader refused a design built on packages: say what
        // would read it instead of handing over a parser error that reads
        // like a bug in the user's RTL.
        if (hasSystemVerilog && !slang) {
          final use = await findSvPackageUse(<String>[
            for (final s in yosysSourcesFor(request))
              if (s.language == YosysSourceLanguage.systemVerilog) s.path,
          ]);
          if (use != null) {
            yield _needsSlangFor(use, stderr);
            return;
          }
        }
        yield Violation(
          engineId: id,
          ruleId: 'cdc/elaboration-failed',
          severity: Severity.error,
          message:
              'CDC analysis could not elaborate the design'
              '${slang ? ' (SystemVerilog read with yosys-slang)' : ''}: '
              '${stderr.trim()}',
          location: SourceLocation(
            file: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
            line: 1,
            column: 1,
          ),
          // A finding about the run, not the design: the headless binary
          // fails the run on it rather than counting it as one error.
          raw: const <String, dynamic>{Violation.analysisFailedKey: true},
        );
        return;
    }

    if (model == null) {
      yield Violation(
        engineId: id,
        ruleId: 'cdc/elaboration-failed',
        severity: Severity.error,
        message:
            'CDC analysis could not read the elaborated netlist: '
            '$readError',
        location: SourceLocation(
          file: request.sourceFiles.isEmpty ? '' : request.sourceFiles.first,
          line: 1,
          column: 1,
        ),
        raw: const <String, dynamic>{Violation.analysisFailedKey: true},
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
    // Every span goes through this before it becomes a location: yosys-slang
    // names files relative to the directory Yosys ran in.
    final paths = YosysSpanPathResolver(request);

    var unsafe = 0;
    var reviewed = 0;
    for (final crossing in cdc.crossings) {
      // A reviewed crossing is one the classifier left unprotected and the
      // user accepted with a reason. It is reported as a note rather than
      // dropped: a waived hazard that vanishes from the table is
      // indistinguishable from one the analysis never saw.
      if (crossing.syncKind == CdcSyncKind.reviewed) {
        reviewed++;
        yield _reviewedNoteFor(crossing, fallback, paths);
        continue;
      }
      if (!crossing.isUnsafe) continue;
      unsafe++;
      yield _violationFor(crossing, fallback, paths);
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
          '${cdc.crossings.length} crossing(s), $unsafe unsafe'
          '${reviewed > 0 ? ', $reviewed reviewed' : ''}.'
          '${slang ? ' SystemVerilog was read with yosys-slang.' : ''}',
      location: fallback,
      raw: <String, dynamic>{
        'domains': cdc.domains.length,
        'crossings': cdc.crossings.length,
        'unsafe': unsafe,
        'reviewed': reviewed,
      },
    );
  }

  /// The note a reviewed crossing is reported as.
  ///
  /// Same anchor as the finding it replaces (the destination register, the
  /// source attached), and the same `raw` keys, so a waiver, a baseline or a
  /// cross-probe written against the error keeps working against the note.
  /// The reason the user gave is in the message, because that is what a
  /// reviewer six months later needs to see without opening the constraints
  /// file.
  Violation _reviewedNoteFor(
    CdcCrossing crossing,
    SourceLocation fallback,
    YosysSpanPathResolver paths,
  ) {
    final location = _toLocation(crossing.destSpan, paths) ?? fallback;
    final related = <SourceLocation>[
      if (_toLocation(crossing.sourceSpan, paths) case final SourceLocation s)
        s,
    ];
    final src = humanCdcClockName(crossing.sourceClock);
    final dst = humanCdcClockName(crossing.destClock);
    return Violation(
      engineId: id,
      ruleId: 'cdc/reviewed-crossing',
      severity: Severity.note,
      message:
          '${_subjectFor(crossing)} crosses $src → $dst unsynchronized and '
          'is a reviewed crossing, accepted with the reason: '
          '${crossing.reviewReason}',
      location: location,
      relatedLocations: related,
      raw: <String, dynamic>{
        ..._rawFor(crossing),
        'review_reason': crossing.reviewReason,
      },
    );
  }

  /// The grammatical subject for [crossing]: a named or unnamed bus for a
  /// multi-bit crossing, a named or unnamed signal for a single bit.
  ///
  /// Grammar, not decoration. The placeholder used to be the bare word
  /// `Signal`, which produced "8-bit bus Signal crosses clk_a → clk_b",
  /// reading as though the net were called Signal. An unnamed net needs an
  /// article, and a bus and a single bit need different ones.
  static String _subjectFor(CdcCrossing crossing) {
    final named = crossing.netName != null;
    if (crossing.width > 1) {
      return named
          ? '${crossing.width}-bit bus `${crossing.netName}`'
          : 'An unnamed ${crossing.width}-bit bus';
    }
    return named ? '`${crossing.netName}`' : 'An unnamed signal';
  }

  /// The machine-readable fields every crossing finding carries.
  static Map<String, dynamic> _rawFor(CdcCrossing crossing) =>
      <String, dynamic>{
        'src_domain': crossing.sourceClock,
        'dst_domain': crossing.destClock,
        'width': crossing.width,
        'sync_kind': crossing.syncKind.name,
        'src_register': crossing.sourceRegisterPath,
        'dst_register': crossing.destRegisterPath,
        // `path` is the field the NetCrux cross-probe reads to highlight the
        // crossing in the schematic.
        if (crossing.netName case final String n) 'path': n,
      };

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
  Violation _violationFor(
    CdcCrossing crossing,
    SourceLocation fallback,
    YosysSpanPathResolver paths,
  ) {
    final location = _toLocation(crossing.destSpan, paths) ?? fallback;
    final related = <SourceLocation>[
      if (_toLocation(crossing.sourceSpan, paths) case final SourceLocation s)
        s,
    ];
    // The per-bit and multi-bit rules below fire only for width > 1, and the
    // single-bit rule only for width 1, so one subject serves all four arms.
    final subject = _subjectFor(crossing);
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
        '$subject crosses $src → $dst with a separate two-flop '
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
        '$subject crosses $src → $dst with no synchronizer. The '
            'destination can latch a mix of old and new bits — a value never '
            'present in the source domain.',
      ),
      _ => (
        'cdc/unsync-single-bit',
        Severity.warning,
        '$subject crosses $src → $dst with no synchronizer; the '
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
      raw: _rawFor(crossing),
    );
  }

  /// Converts a Yosys-recovered span into the engine's location type, its
  /// file named the way the project names it (see [YosysSpanPathResolver]).
  static SourceLocation? _toLocation(
    CdcSourceSpan? span,
    YosysSpanPathResolver paths,
  ) => span == null
      ? null
      : SourceLocation(
          file: paths.resolve(span.file),
          line: span.line,
          column: span.column,
        );

  /// The `read_slang` options CDC elaborates with.
  ///
  /// CDC reads no assertion, so `--ignore-assertions` removes the one way an
  /// SVA construct yosys-slang cannot lower could stop the read. And
  /// `--ignore-initial` drops initial blocks and declaration initializers,
  /// which describe simulation start-up rather than structure; without it a
  /// `$readmemh` in an `initial` block or a `$value$plusargs` call stops the
  /// read (OpenTitan's memory primitives do both).
  static const List<String> slangOptions = <String>[
    '--ignore-initial',
    '--ignore-assertions',
  ];

  /// The per-engine option (`perEngineOptions.cdc.blackboxedModules`)
  /// listing modules yosys-slang reads as black boxes: their ports are kept,
  /// their contents are not elaborated. For a behavioural model slang cannot
  /// lower, such as an analog macro's (OpenTitan's `rglts_pdm_3p3v`). Each
  /// entry must be a bare module name; anything else fails the run before
  /// Yosys starts. Ignored when the built-in reader is used.
  static const String blackboxedModulesOption = 'blackboxedModules';

  /// [slangOptions] plus one `--blackboxed-module` per entry of
  /// [blackboxedModulesOption].
  @visibleForTesting
  static List<String> slangOptionsFor(LintRunRequest request) => <String>[
    ...slangOptions,
    if (request.options[blackboxedModulesOption] case final List<Object?> names)
      for (final name in names.whereType<String>()) '--blackboxed-module $name',
  ];

  /// A fresh directory for one run's netlist file, under [tempDirectory] or
  /// the system temp directory, or `null` when none can be made: the netlist
  /// then reaches the engine in memory, as it did before it was kept on disk.
  Directory? _netlistScratchDirectory() {
    try {
      return (tempDirectory ?? Directory.systemTemp).createTempSync(
        'lintcrux_cdc_',
      );
    } on FileSystemException {
      return null;
    }
  }

  static void _removeScratch(Directory? scratch) {
    if (scratch == null) return;
    try {
      scratch.deleteSync(recursive: true);
    } on FileSystemException {
      // A temp directory left behind is not worth failing the run over.
    }
  }

  /// The netlist of [elaborated], or the reason it could not be read.
  (NetlistModel?, Object?) _readNetlist(
    DesignElaborated elaborated,
    String? topModule,
  ) {
    try {
      final file = elaborated.netlistFile;
      return (
        file != null
            ? netlistReader.readFile(file, topModule: topModule)
            : netlistReader.readString(
                elaborated.rawJson,
                topModule: topModule,
              ),
        null,
      );
    } on Object catch (e) {
      return (null, e);
    }
  }

  /// Whether the Yosys this run starts has the yosys-slang frontend. Cached
  /// per executable by `crux_yosys`, so asking on every run costs one probe
  /// per binary per process.
  Future<bool> _hasSlang(LintRunRequest request) => YosysAvailabilityService(
    runner: EngineYosysProcessRunner(processRunner),
    executableNameOverride: yosysExecutableFor(
      request.binary,
      resolver: bundledBinaryResolver,
    ),
  ).probeSlang();

  /// The finding for a package-based design the built-in reader refused
  /// because this Yosys has no yosys-slang.
  ///
  /// One finding, at the package [use] that makes the design need slang,
  /// marked as an analysis failure so the headless binary exits `3`: nothing
  /// was analysed. The Yosys error is kept, first line only, so a reader can
  /// still see what stopped the built-in reader.
  Violation _needsSlangFor(SvPackageUse use, String stderr) {
    final lines = stderr
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    final error = lines.firstWhere(
      (l) => l.contains('ERROR'),
      orElse: () => lines.isEmpty ? '' : lines.first,
    );
    return Violation(
      engineId: id,
      ruleId: 'cdc/needs-slang-frontend',
      severity: Severity.error,
      message:
          'CDC analysis did not run: this design uses SystemVerilog packages '
          '(`${use.construct}` in ${p.basename(use.file)}, line ${use.line}), '
          'and the Yosys in use has no yosys-slang frontend, so its built-in '
          'reader stopped${error.isEmpty ? '' : ' ($error)'}. CDC reads '
          'SystemVerilog with yosys-slang when the Yosys it runs has it. '
          'Install a Yosys that includes yosys-slang, such as the OSS CAD '
          'Suite (github.com/YosysHQ/oss-cad-suite-build), and select it in '
          'Settings > Engines > Yosys check, or pass --yosys-path.',
      location: SourceLocation(file: use.file, line: use.line, column: 1),
      raw: const <String, dynamic>{Violation.analysisFailedKey: true},
    );
  }

  @override
  void cancel() {
    // The Yosys run is a single subprocess and the netlist read that follows
    // it is synchronous, so there is nothing to interrupt in between. Left
    // explicit rather than absent so a reader does not assume cancellation
    // was forgotten.
  }
}
