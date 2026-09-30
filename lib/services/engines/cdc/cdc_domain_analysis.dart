// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart';
import 'package:lintcrux/services/engines/cdc/cdc_clock_resolver.dart';
import 'package:lintcrux/services/engines/cdc/cdc_source_span.dart';
import 'package:meta/meta.dart';

/// Renders a clock net name for a human reader.
///
/// Yosys names a generated clock after the cell that produced it, and that
/// name carries the full source path:
///
///     $and$/Users/me/proj/rtl/soc/clocking.v:24$1_Y
///
/// Fine as an identifier, unusable in a sentence — it lands in the middle of
/// every crossing message, and on a real tree the paths are long enough to
/// bury the part the reader needs. The file and line inside it are the useful
/// part, though: they point at the RTL that made the clock. Keep those, drop
/// the rest.
///
/// A source-declared name (`clk_a`, `div2`) is already what the engineer
/// called it and passes through untouched.
String humanCdcClockName(String raw) {
  if (!raw.startsWith(r'$')) return raw;
  final m = RegExp(r'([^/\\$]+\.s?v):(\d+)').firstMatch(raw);
  if (m != null) return 'generated clock (${m.group(1)}:${m.group(2)})';
  return 'generated clock';
}

/// A clock domain: one clock and the registers it drives.
@immutable
class CdcClockDomain {
  /// Creates a domain.
  const CdcClockDomain({
    required this.domainKey,
    required this.clockName,
    required this.registerPaths,
  });

  /// Opaque key from the [CdcClockResolver]. Two registers share a domain iff
  /// they share this key — the open-core resolver makes it the clock net bit,
  /// the Pro resolver makes it the root of the traced clock tree.
  final Object domainKey;

  /// Best-effort human name for the clock.
  final String clockName;

  /// Hierarchical paths of the registers this clock drives.
  final List<String> registerPaths;

  @override
  String toString() =>
      'CdcClockDomain($clockName, ${registerPaths.length} registers)';
}

/// How a crossing is (or is not) protected.
enum CdcSyncKind {
  /// No recognized synchronizer.
  none,

  /// A two-flop synchronizer chain in the destination domain.
  twoFlop,

  /// Three or more flops in series. Same protection, more MTBF margin.
  multiFlop,

  /// A two-flop chain with combinational logic between the flops, which
  /// defeats the MTBF the chain exists to provide.
  comboInSync,

  /// A bus whose bits are each independently two-flop synchronized. Every bit
  /// is individually safe and the bus as a whole is **not** — see
  /// [CdcCrossing.isUnsafe].
  perBitSyncBus,

  /// A data bus qualified by a separately-synchronized handshake. Safe: the
  /// bus is stable by the time the qualifier arrives.
  handshakeQualified,

  /// A gray-coded pointer crossing, the async-FIFO idiom. Safe: only one bit
  /// changes per step, so a mis-sampled value is always adjacent-in-time
  /// rather than arbitrary.
  grayCoded,

  /// The crossing is between clocks the user declared synchronous, so it is
  /// not an asynchronous crossing at all.
  declaredSynchronous,
}

/// One clock-domain crossing.
@immutable
class CdcCrossing {
  /// Creates a crossing.
  const CdcCrossing({
    required this.sourceRegisterPath,
    required this.destRegisterPath,
    required this.sourceClock,
    required this.destClock,
    required this.width,
    required this.syncKind,
    this.sourceSpan,
    this.destSpan,
    this.netName,
  });

  /// The register whose Q drives the crossing.
  final String sourceRegisterPath;

  /// The register that samples it in another domain.
  final String destRegisterPath;

  /// Source clock name.
  final String sourceClock;

  /// Destination clock name.
  final String destClock;

  /// Number of bits crossing together.
  ///
  /// **The field the multi-bit rule turns on.** A single bit crossing
  /// unsynchronized risks metastability; a *bus* crossing unsynchronized risks
  /// incoherence — the destination latching a mix of old and new bits, a value
  /// that never existed in the source domain. The second is the more expensive
  /// bug and the harder one to find in simulation, which is why width is
  /// carried rather than derived later.
  final int width;

  /// How the crossing is protected.
  final CdcSyncKind syncKind;

  /// Where the source register was written, when Yosys recorded it.
  final CdcSourceSpan? sourceSpan;

  /// Where the destination register was written. This is the position a
  /// finding reports, because the destination is where the unsafe sample
  /// happens and where a fix goes.
  final CdcSourceSpan? destSpan;

  /// The crossing net's human name, when one exists.
  final String? netName;

  /// Whether this crossing is unprotected.
  ///
  /// [CdcSyncKind.perBitSyncBus] counts as unsafe **on purpose**, and it is the
  /// one entry here that surprises people. Synchronizing a bus one bit at a
  /// time looks like the careful thing to do and is the classic wrong fix: each
  /// bit resolves independently, so bits that changed together in the source
  /// domain can land in different destination cycles and the receiver sees a
  /// value that never existed. It is more dangerous than an unsynchronized bus
  /// because it looks correct in review and the metastability warnings all go
  /// away.
  bool get isUnsafe => switch (syncKind) {
    CdcSyncKind.twoFlop ||
    CdcSyncKind.multiFlop ||
    CdcSyncKind.handshakeQualified ||
    CdcSyncKind.grayCoded ||
    CdcSyncKind.declaredSynchronous => false,
    CdcSyncKind.none ||
    CdcSyncKind.comboInSync ||
    CdcSyncKind.perBitSyncBus => true,
  };

  /// Copy with replaced fields.
  CdcCrossing copyWith({CdcSyncKind? syncKind}) => CdcCrossing(
    sourceRegisterPath: sourceRegisterPath,
    destRegisterPath: destRegisterPath,
    sourceClock: sourceClock,
    destClock: destClock,
    width: width,
    syncKind: syncKind ?? this.syncKind,
    sourceSpan: sourceSpan,
    destSpan: destSpan,
    netName: netName,
  );

  @override
  String toString() =>
      'CdcCrossing($sourceRegisterPath[$sourceClock] -> '
      '$destRegisterPath[$destClock], ${width}b, ${syncKind.name})';
}

/// Result of one CDC pass.
@immutable
class CdcAnalysisResult {
  /// Creates a result.
  const CdcAnalysisResult({
    required this.domains,
    required this.crossings,
    this.diagnostics = const <String>[],
  });

  /// Recovered clock domains, in discovery order.
  final List<CdcClockDomain> domains;

  /// Every crossing found between two distinct domains.
  final List<CdcCrossing> crossings;

  /// Non-fatal notes — an unnamed clock, a register whose clock could not be
  /// resolved. Surfaced rather than dropped: a CDC tool that quietly analysed
  /// less than the whole design is worse than one that says so.
  final List<String> diagnostics;
}

/// A register, reduced to what CDC analysis needs.
@immutable
class CdcRegister {
  /// Creates a register record.
  const CdcRegister({
    required this.path,
    required this.domainKey,
    required this.clockBit,
    required this.dBits,
    required this.qBits,
    this.span,
  });

  /// Cell instance path.
  final String path;

  /// Domain key from the resolver.
  final Object domainKey;

  /// The raw net bit driving `CLK`, before domain resolution.
  final int clockBit;

  /// Net bits reaching `D`.
  final List<int> dBits;

  /// Net bits driven by `Q`.
  final List<int> qBits;

  /// Where the register was written.
  final CdcSourceSpan? span;
}

/// Everything the classifier needs to reason about the receiving side.
@immutable
class CdcClassificationContext {
  /// Creates a context.
  const CdcClassificationContext({
    required this.module,
    required this.registers,
    required this.driverOf,
    required this.combSources,
    required this.destination,
    required this.source,
    required this.width,
    this.readersOf = const <int, Set<String>>{},
    this.portBits = const <int>{},
  });

  /// The module under analysis.
  final Module module;

  /// Every register, by cell path.
  final Map<String, CdcRegister> registers;

  /// Net bit -> the register path driving it.
  final Map<int, String> driverOf;

  /// Net bit -> the net bits feeding the combinational cell that drives it.
  final Map<int, Set<int>> combSources;

  /// The register sampling the crossing.
  final CdcRegister destination;

  /// The register driving it.
  final CdcRegister source;

  /// How many bits cross together.
  final int width;

  /// Net bit -> the cell paths that read it as an input.
  ///
  /// This is what makes "is this a synchronizer?" answerable. A two-flop chain's
  /// first stage exists *only* to feed the second; a flop whose output is also
  /// read by anything else is a captured value in use, not a sync stage. Without
  /// fan-out the two are structurally identical and the classifier cannot tell
  /// them apart — see [BasicCdcSyncClassifier].
  final Map<int, Set<String>> readersOf;

  /// Net bits that reach a module port.
  ///
  /// A port is a reader the cell list cannot show: the value leaves the module,
  /// so the flop driving it is observable from outside and cannot be a private
  /// synchronizer stage.
  final Set<int> portBits;

  /// Whether [stage]'s output exists solely to feed [next].
  ///
  /// The question every synchronizer-recognising classifier has to answer
  /// before it calls a chain a chain. A staging flop is private by definition;
  /// one whose value is also read by a datapath, or leaves the module, is a
  /// captured value in use and the crossing behind it is still unprotected.
  ///
  /// Conservative when fan-out was not supplied: returns `true`, so a context
  /// built by hand behaves as it did before this existed rather than silently
  /// reclassifying.
  bool isDedicatedStage(CdcRegister stage, CdcRegister next) {
    if (readersOf.isEmpty && portBits.isEmpty) return true;
    for (final bit in stage.qBits) {
      if (portBits.contains(bit)) return false;
      for (final reader in readersOf[bit] ?? const <String>{}) {
        if (reader != next.path) return false;
      }
    }
    return true;
  }
}

/// Recognizes what protects a crossing, if anything.
///
/// Open core recognizes the two-flop chain and combinational logic inside it —
/// enough to avoid crying wolf on correctly-written code, which is the minimum
/// bar: a checker that cries wolf poisons trust. The Pro
/// classifier adds the idioms that need real structural analysis: N-flop
/// chains, handshake qualification, gray-coded pointers, and the per-bit-
/// synchronized bus.
@immutable
// A strategy interface, not a callback. The Pro implementation carries parsed
// constraints and a handshake index as state and is selected at
// registry-construction time; a bare function type could express neither, and
// collapsing it would put the tier seam somewhere less obvious.
// ignore: one_member_abstracts
abstract class CdcSyncClassifier {
  /// Const constructor for subclasses.
  const CdcSyncClassifier();

  /// Classifies the protection on one crossing.
  CdcSyncKind classify(CdcClassificationContext context);
}

/// The open-core classifier: two-flop chains and combinational logic in them.
///
/// **A synchronizer stage is a flop whose output is dedicated to the next
/// stage.** That requirement is the whole correctness of this class, and
/// leaving it out is not a missing refinement — it inverts the answer. "Some
/// same-domain flop reads `dest.Q`" describes a two-flop synchronizer and it
/// equally describes ordinary RTL registering a value it just captured, which
/// is one of the most common shapes in any design. Without the dedication
/// check, this:
///
/// ```verilog
/// always @(posedge clk_b) captured <= data_bus;   // unsynchronized crossing
/// always @(posedge clk_b) scratch  <= captured;   // ordinary downstream use
/// ```
///
/// reports the crossing as a protected two-flop chain — a **false clean on a
/// real hazard**, which is the one outcome a CDC tool may never produce. The
/// same gap made a crossing whose captured value fed any combinational logic
/// report as `comboInSync`, replacing "this bus crosses with no synchronizer"
/// with a different and much less alarming finding.
class BasicCdcSyncClassifier extends CdcSyncClassifier {
  /// Creates the classifier.
  const BasicCdcSyncClassifier();

  @override
  CdcSyncKind classify(CdcClassificationContext context) {
    final dest = context.destination;
    for (final r in context.registers.values) {
      if (r.path == dest.path) continue;
      if (r.domainKey != dest.domainKey) continue;
      // Direct wire from dest.Q into r.D → a candidate two-flop chain.
      if (r.dBits.any(dest.qBits.contains)) {
        if (!context.isDedicatedStage(dest, r)) continue;
        return CdcSyncKind.twoFlop;
      }
      // Reached only through combinational logic → the MTBF is gone. Only
      // meaningful when dest is a dedicated stage; otherwise this is a captured
      // value feeding a datapath and the crossing itself is the finding.
      for (final bit in r.dBits) {
        final via = context.combSources[bit];
        if (via != null && via.any(dest.qBits.contains)) {
          if (!context.isDedicatedStage(dest, r)) continue;
          return CdcSyncKind.comboInSync;
        }
      }
    }
    return CdcSyncKind.none;
  }
}

/// Recovers clock domains from an elaborated netlist and enumerates the
/// crossings between them.
///
/// **Deliberately structural, and deliberately bounded in open core.** The two
/// decisions that determine whether a CDC tool is usable — what counts as a
/// clock, and what counts as a synchronizer — are delegated to
/// [CdcClockResolver] and [CdcSyncClassifier] so the analysis itself never
/// branches on licence tier. Open core supplies the pessimistic pair: every
/// distinct clock net is its own asynchronous domain, and only the two-flop
/// chain is recognized as protection.
///
/// Saying that plainly matters more here than in most analyses. A CDC tool that
/// flags five thousand crossings on a chip, of which four thousand nine hundred
/// are fine, teaches engineers to ignore it — and takes the rest of the suite's
/// credibility with it. The honest bounded version ships first on purpose.
class CdcDomainAnalysis {
  /// Creates an analysis.
  const CdcDomainAnalysis({
    this.clockResolver = const LiteralCdcClockResolver(),
    this.classifier = const BasicCdcSyncClassifier(),
  });

  /// How registers are grouped into domains, and which pairs are asynchronous.
  final CdcClockResolver clockResolver;

  /// How the receiving side is recognized.
  final CdcSyncClassifier classifier;

  /// Yosys register primitives. `$dff` family plus the async-reset variants;
  /// the sync-reset `$sdff*` family carries the same `CLK` port.
  static bool isRegister(String cellType) =>
      cellType.startsWith(r'$dff') ||
      cellType.startsWith(r'$adff') ||
      cellType.startsWith(r'$sdff');

  /// Analyses [topModuleName] within [netlist].
  CdcAnalysisResult analyze(NetlistModel netlist, {String? topModuleName}) {
    final module = topModuleName != null
        ? netlist.modules[topModuleName]
        : netlist.topModule;
    if (module == null) {
      return const CdcAnalysisResult(
        domains: <CdcClockDomain>[],
        crossings: <CdcCrossing>[],
        diagnostics: <String>['no top module to analyse'],
      );
    }

    final diagnostics = <String>[];
    final netNames = _netNamesByBit(module);

    // ── Step 1: registers, and the clock each is driven by ────────────────
    final registers = <String, CdcRegister>{};
    for (final entry in module.cells.entries) {
      final cell = entry.value;
      if (!isRegister(cell.type)) continue;
      final clkBits = bitsOf(cell.connections['CLK']);
      if (clkBits.isEmpty) {
        diagnostics.add('${entry.key}: register with no CLK connection');
        continue;
      }
      registers[entry.key] = CdcRegister(
        path: entry.key,
        clockBit: clkBits.first,
        domainKey: clockResolver.domainKeyFor(clkBits.first, module),
        dBits: bitsOf(cell.connections['D']),
        qBits: bitsOf(cell.connections['Q']),
        span: CdcSourceSpan.parse(cell.attributes['src']),
      );
    }

    // ── Step 2: partition into domains ────────────────────────────────────
    final byDomain = <Object, List<String>>{};
    final clockBitFor = <Object, int>{};
    for (final r in registers.values) {
      byDomain.putIfAbsent(r.domainKey, () => <String>[]).add(r.path);
      clockBitFor.putIfAbsent(r.domainKey, () => r.clockBit);
    }
    final domains = <CdcClockDomain>[
      for (final e in byDomain.entries)
        CdcClockDomain(
          domainKey: e.key,
          clockName: clockResolver.domainNameFor(e.key, netNames),
          registerPaths: List.unmodifiable(e.value..sort()),
        ),
    ]..sort((a, b) => a.clockName.compareTo(b.clockName));

    if (domains.length < 2) {
      // One domain cannot cross itself. Reported rather than silently empty so
      // a user who expected two clocks learns their design elaborated to one.
      diagnostics.add(
        'only ${domains.length} clock domain(s) found — no crossings possible',
      );
      return CdcAnalysisResult(
        domains: domains,
        crossings: const <CdcCrossing>[],
        diagnostics: diagnostics,
      );
    }

    // ── Step 3: which register drives each net bit ────────────────────────
    final driverOf = <int, String>{};
    for (final r in registers.values) {
      for (final bit in r.qBits) {
        driverOf[bit] = r.path;
      }
    }

    // Combinational fan-in: a bit driven by a non-register cell resolves back
    // to whatever registers feed that cell. One level of indirection covers the
    // muxes and inverters `proc` leaves behind without turning this into a
    // general cone walk, which belongs to NetCrux.
    final combSources = <int, Set<int>>{};
    for (final entry in module.cells.entries) {
      final cell = entry.value;
      if (isRegister(cell.type)) continue;
      final outputs = <int>[];
      final inputs = <int>[];
      for (final c in cell.connections.entries) {
        final bits = bitsOf(c.value);
        // Yosys names combinational outputs Y / Q; everything else is an input.
        if (c.key == 'Y' || c.key == 'Q') {
          outputs.addAll(bits);
        } else {
          inputs.addAll(bits);
        }
      }
      for (final o in outputs) {
        combSources.putIfAbsent(o, () => <int>{}).addAll(inputs);
      }
    }

    // Fan-out: who reads each bit. Needed to tell a synchronizer stage from a
    // captured value in use — see [BasicCdcSyncClassifier]. CLK and reset
    // inputs are excluded deliberately: a flop sharing the clock net is not a
    // reader of the crossing, and counting it would mark every stage
    // non-dedicated and undo the two-flop recognition entirely.
    const clockAndResetPorts = <String>{
      'CLK',
      'ARST',
      'SRST',
      'RST',
      'CLR',
      'PRE',
      'SET',
      'EN',
    };
    final readersOf = <int, Set<String>>{};
    for (final entry in module.cells.entries) {
      for (final c in entry.value.connections.entries) {
        if (c.key == 'Y' || c.key == 'Q') continue;
        if (clockAndResetPorts.contains(c.key)) continue;
        for (final bit in bitsOf(c.value)) {
          readersOf.putIfAbsent(bit, () => <String>{}).add(entry.key);
        }
      }
    }
    final portBits = <int>{
      for (final port in module.ports.values)
        if (port.direction != PortDirection.input) ...bitsOf(port.bits),
    };

    // ── Step 4: enumerate crossings ───────────────────────────────────────
    final crossings = <CdcCrossing>[];
    for (final dest in registers.values) {
      // Group the source registers feeding this register's D by domain, so an
      // 8-bit bus crossing produces ONE finding of width 8 rather than eight
      // findings of width 1. That distinction is the whole multi-bit story.
      final sourcesByRegister = <String, int>{};
      final netNameFor = <String, String>{};
      for (final bit in dest.dBits) {
        for (final src in _resolveSources(bit, driverOf, combSources)) {
          final srcReg = registers[src];
          if (srcReg == null) continue;
          if (!clockResolver.isAsynchronous(
            CdcDomainQuery(
              sourceKey: srcReg.domainKey,
              destKey: dest.domainKey,
              module: module,
              netNames: netNames,
            ),
          )) {
            continue;
          }
          sourcesByRegister[src] = (sourcesByRegister[src] ?? 0) + 1;
          // Name the crossing after the net leaving the SOURCE register, not
          // the destination's D bit. After `proc` the D bit is the output of
          // the reset/enable mux the pass just built — an internal net whose
          // only name is a `$`-prefixed one, which the filter below then drops,
          // so every crossing in a design written with a reset came out
          // "unnamed". The source's Q is the wire the user actually declared.
          final name = _preferredName(srcReg.qBits, netNames);
          if (name != null) netNameFor.putIfAbsent(src, () => name);
        }
      }

      for (final e in sourcesByRegister.entries) {
        final srcReg = registers[e.key]!;
        crossings.add(
          CdcCrossing(
            sourceRegisterPath: e.key,
            destRegisterPath: dest.path,
            sourceClock: clockResolver.domainNameFor(
              srcReg.domainKey,
              netNames,
            ),
            destClock: clockResolver.domainNameFor(dest.domainKey, netNames),
            width: e.value,
            sourceSpan: srcReg.span,
            destSpan: dest.span,
            netName: netNameFor[e.key],
            syncKind: classifier.classify(
              CdcClassificationContext(
                module: module,
                registers: registers,
                driverOf: driverOf,
                combSources: combSources,
                destination: dest,
                source: srcReg,
                width: e.value,
                readersOf: readersOf,
                portBits: portBits,
              ),
            ),
          ),
        );
      }
    }

    crossings.sort((a, b) => a.destRegisterPath.compareTo(b.destRegisterPath));

    return CdcAnalysisResult(
      domains: domains,
      crossings: List.unmodifiable(crossings),
      diagnostics: List.unmodifiable(diagnostics),
    );
  }

  /// Registers driving [bit], directly or through one level of logic.
  static Set<String> _resolveSources(
    int bit,
    Map<int, String> driverOf,
    Map<int, Set<int>> combSources,
  ) {
    final direct = driverOf[bit];
    if (direct != null) return {direct};
    final out = <String>{};
    for (final upstream in combSources[bit] ?? const <int>{}) {
      final d = driverOf[upstream];
      if (d != null) out.add(d);
    }
    return out;
  }

  /// The name a user would recognise for the net carrying [bits], if any.
  static String? _preferredName(List<int> bits, Map<int, String> netNames) {
    for (final bit in bits) {
      final name = netNames[bit];
      if (name != null && !name.startsWith(r'$')) return name;
    }
    return null;
  }

  /// Net bit id → the name of the net carrying it.
  ///
  /// One bit typically carries several names after `flatten` — the top-level
  /// wire, each instance's port alias, and the `$flatten\…` internals — and
  /// which one is kept decides whether a finding reads `data` or reads
  /// "unnamed". Taking the first (the old `putIfAbsent`) meant taking whichever
  /// Yosys happened to emit first, and `$`-prefixed names sort ahead of real
  /// ones, so the generated name usually won and was then discarded as
  /// unusable. Preference order: a top-level name, then any declared name, then
  /// a generated one.
  static Map<int, String> _netNamesByBit(Module module) {
    final out = <int, String>{};
    void offer(int bit, String name) {
      final existing = out[bit];
      if (existing == null || _nameRank(name) < _nameRank(existing)) {
        out[bit] = name;
      }
    }

    for (final entry in module.nets.entries) {
      for (final bit in entry.value.bits) {
        if (bit is NetBit) offer(bit.netId, entry.key);
      }
    }
    // Ports win outright: a port name is the one the reader definitely wrote.
    for (final entry in module.ports.entries) {
      for (final bit in entry.value.bits) {
        if (bit is NetBit) out[bit.netId] = entry.key;
      }
    }
    return out;
  }

  /// Lower is better. Generated names last, hierarchical aliases in between.
  static int _nameRank(String name) {
    if (name.startsWith(r'$')) return 2;
    return name.contains('.') ? 1 : 0;
  }

  /// Net bit ids on a connection, ignoring constants.
  static List<int> bitsOf(List<BitRef>? refs) => <int>[
    if (refs != null)
      for (final r in refs)
        if (r is NetBit) r.netId,
  ];
}
