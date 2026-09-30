// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart';
import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/cdc/cdc_domain_analysis.dart';

/// CDC engine, against the real EDU capstone design.
///
/// `cdc-soc-capstone` is LintCrux's CDC gate fixture and it is close to
/// ideal: a producer in `clk_a`, a consumer in `clk_b`, a `req` bit crossing
/// through a correct two-flop synchronizer, and an 8-bit `data` bus crossing
/// with nothing at all. One design containing both the safe and the unsafe
/// case is what makes the gate meaningful — a fixture with only the hazard
/// would pass a detector that flags everything.
///
/// The gates, restated as tests:
///   1. ingestion — the capstone parses
///   2. domains — the two domains are identified
///   3. crossings — `data` is flagged unsync-multi-bit and `req` is NOT
///      flagged
const _sources = <String>[
  'test/fixtures/verilog/cdc/soc_top.v',
  'test/fixtures/verilog/cdc/producer.v',
  'test/fixtures/verilog/cdc/consumer.v',
  'test/fixtures/verilog/cdc/sync2.v',
];

/// The capstone plus a top that uses the captured value downstream — the shape
/// that used to defeat synchronizer recognition. See `downstream_use.v`.
const _downstreamSources = <String>[
  ..._sources,
  'test/fixtures/verilog/cdc/downstream_use.v',
];

void main() {
  const analysis = CdcDomainAnalysis();
  late bool yosysAvailable;

  setUpAll(() async {
    final probe = await YosysAvailabilityService(
      runner: const DefaultProcessRunner(),
    ).probe();
    yosysAvailable = probe.isAvailable;
  });

  Future<NetlistModel?> elaborate({
    List<String> sources = _sources,
    String topModule = 'soc_top',
  }) async {
    final result = await YosysRunner().run(
      YosysRunRequest(
        sources: <YosysSourceFile>[
          for (final path in sources) YosysSourceFile(path),
        ],
        topModule: topModule,
        // `flatten` is required, not cosmetic: without it every module is its
        // own scope and a crossing between two instances is invisible. `opt` is
        // deliberately NOT run — it folds the very structure CDC reads.
        extraCommands: const <String>['flatten'],
      ),
    );
    if (result is! YosysRunSuccess) {
      fail(
        'yosys elaboration of the capstone failed: '
        '${result is YosysRunFailure ? result.stderr : result}',
      );
    }
    return const YosysJsonParser().parse(result.rawJson);
  }

  Future<CdcAnalysisResult> run() async =>
      analysis.analyze((await elaborate())!);

  Future<CdcAnalysisResult> runDownstream() async => analysis.analyze(
    (await elaborate(
      sources: _downstreamSources,
      topModule: 'downstream_use',
    ))!,
  );

  group('ingestion', () {
    test('the capstone elaborates and parses', () async {
      if (!yosysAvailable) {
        markTestSkipped('yosys not on PATH');
        return;
      }
      final model = await elaborate();
      expect(model, isNotNull);
      expect(model!.topModule, isNotNull);
      expect(model.topModule!.cells, isNotEmpty);
    });
  });

  group('clock inference and domain partitioning', () {
    test('exactly two clock domains are found', () async {
      if (!yosysAvailable) {
        markTestSkipped('yosys not on PATH');
        return;
      }
      final result = await run();
      expect(
        result.domains,
        hasLength(2),
        reason:
            'clk_a and clk_b; got '
            '${result.domains.map((d) => d.clockName).toList()}',
      );
      expect(
        result.domains.map((d) => d.clockName).toSet(),
        containsAll(<String>['clk_a', 'clk_b']),
      );
    });

    test('every register lands in exactly one domain', () async {
      if (!yosysAvailable) {
        markTestSkipped('yosys not on PATH');
        return;
      }
      final result = await run();
      final all = <String>[];
      for (final d in result.domains) {
        all.addAll(d.registerPaths);
      }
      expect(
        all.toSet(),
        hasLength(all.length),
        reason: 'a register in two domains would double-count every crossing',
      );
    });
  });

  group('crossing enumeration and classification', () {
    test('the unsynchronized data bus is flagged as multi-bit', () async {
      if (!yosysAvailable) {
        markTestSkipped('yosys not on PATH');
        return;
      }
      final result = await run();
      final unsafeMultiBit = result.crossings
          .where((c) => c.isUnsafe && c.width > 1)
          .toList();
      expect(
        unsafeMultiBit,
        isNotEmpty,
        reason:
            'the 8-bit data bus crosses clk_a -> clk_b with no synchronizer; '
            'crossings found: ${result.crossings}',
      );
      // Width matters: eight findings of one bit would be the wrong answer to
      // the right question. Incoherence is a property of the bus, not the bit.
      expect(unsafeMultiBit.first.width, greaterThan(1));
      expect(unsafeMultiBit.first.syncKind, CdcSyncKind.none);
    });

    test('the two-flop synchronized req is NOT flagged', () async {
      if (!yosysAvailable) {
        markTestSkipped('yosys not on PATH');
        return;
      }
      // The half of the gate that decides whether the engine is usable. A CDC
      // tool that cannot see a correct synchronizer flags every well-designed
      // crossing, and an engineer told their correct code is broken uninstalls
      // it. Crying wolf is worse than silence here.
      final result = await run();
      final safe = result.crossings.where(
        (c) => c.syncKind == CdcSyncKind.twoFlop,
      );
      expect(
        safe,
        isNotEmpty,
        reason:
            'the req bit crosses through sync2 and must be recognised as '
            'protected; crossings: ${result.crossings}',
      );
      expect(safe.every((c) => c.width == 1), isTrue);
    });

    test('crossings carry both clock names for the report', () async {
      if (!yosysAvailable) {
        markTestSkipped('yosys not on PATH');
        return;
      }
      final result = await run();
      expect(result.crossings, isNotEmpty);
      for (final c in result.crossings) {
        expect(c.sourceClock, isNotEmpty);
        expect(c.destClock, isNotEmpty);
        expect(
          c.sourceClock,
          isNot(c.destClock),
          reason: 'a same-domain pair is not a crossing and must not be listed',
        );
      }
    });
  });

  group('a captured value in use is not a synchronizer', () {
    // Both assertions here failed before the dedication check landed, and they
    // failed in the worst possible direction: the hazard was reported as
    // protected. The trigger is not exotic — it is registering a value you just
    // captured, which nearly every real design does somewhere downstream of a
    // crossing. A CDC tool that goes quiet when the design gets more realistic
    // is worse than one that was never installed.
    test(
      'a downstream flop does not make an unsynchronized bus safe',
      () async {
        if (!yosysAvailable) {
          markTestSkipped('yosys not on PATH');
          return;
        }
        final result = await runDownstream();
        final busCrossings = result.crossings
            .where((c) => c.width > 1)
            .toList();
        expect(
          busCrossings,
          isNotEmpty,
          reason: 'the data bus still crosses; crossings: ${result.crossings}',
        );
        expect(
          busCrossings.every((c) => c.isUnsafe),
          isTrue,
          reason:
              'nothing was added between the domains, so the bus is exactly as '
              'unprotected as it is in soc_top; got '
              '${busCrossings.map((c) => c.syncKind).toList()}',
        );
        expect(
          busCrossings.map((c) => c.syncKind),
          everyElement(CdcSyncKind.none),
          reason:
              'reporting twoFlop here is a false clean, and reporting '
              'comboInSync replaces "no synchronizer" with a milder finding',
        );
      },
    );

    test('the real synchronizer is still recognised alongside it', () async {
      if (!yosysAvailable) {
        markTestSkipped('yosys not on PATH');
        return;
      }
      // The other half: a fix that stopped recognising sync2 would pass the
      // test above by crying wolf on everything.
      final result = await runDownstream();
      final safe = result.crossings.where(
        (c) => c.syncKind == CdcSyncKind.twoFlop,
      );
      expect(
        safe,
        isNotEmpty,
        reason:
            'req still crosses through sync2, whose meta stage feeds nothing '
            'but ff; crossings: ${result.crossings}',
      );
      expect(safe.every((c) => c.width == 1), isTrue);
    });
  });

  group('findings name the net a reader would recognise', () {
    test(
      'the crossing carries the source net name, not a generated one',
      () async {
        if (!yosysAvailable) {
          markTestSkipped('yosys not on PATH');
          return;
        }
        // The name used to be read off the destination register's D bit, which
        // after `proc` is the output of the reset mux that pass just built. Its
        // only name is `$`-prefixed, so it was discarded and every crossing in a
        // design written with a reset — that is, every real design — reported as
        // "An unnamed 8-bit bus".
        final result = await run();
        final bus = result.crossings.firstWhere((c) => c.width > 1);
        expect(
          bus.netName,
          'data',
          reason: 'crossings: ${result.crossings}, name: ${bus.netName}',
        );
      },
    );
  });

  group('bounded by design', () {
    test('a single-domain design reports no crossings, and says why', () {
      // Silence and "nothing to analyse" look identical to a user. A design
      // that elaborated to one clock when they expected two should learn that
      // from the tool rather than from a blank report.
      const empty = NetlistModel(creator: 'test', modules: <String, Module>{});
      final result = analysis.analyze(empty);
      expect(result.crossings, isEmpty);
      expect(result.diagnostics, isNotEmpty);
    });
  });
}
