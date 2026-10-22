// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_netlist/crux_netlist.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/cdc/cdc_domain_analysis.dart';

// The combinational fan-in map the classifiers read (`combSources`) used to
// hold a separate set per output bit, each a copy of all the driving cell's
// inputs: outputs x inputs entries per cell. On OpenTitan earlgrey that was
// half a billion entries (13 GB) before a single crossing was looked at
// (lintcrux#31). The output bits of one cell now share one set; what each
// bit maps to is unchanged.

/// Records the context of every crossing it is asked about.
class _Recording extends CdcSyncClassifier {
  final List<CdcClassificationContext> seen = <CdcClassificationContext>[];

  @override
  CdcSyncKind classify(CdcClassificationContext context) {
    seen.add(context);
    return CdcSyncKind.none;
  }
}

Cell _cell(String name, String type, Map<String, List<int>> connections) =>
    Cell(
      name: name,
      type: type,
      parameters: const <String, String>{},
      attributes: const <String, String>{},
      portDirections: const <String, PortDirection>{},
      connections: <String, List<BitRef>>{
        for (final e in connections.entries)
          e.key: <BitRef>[for (final b in e.value) NetBit(b)],
      },
    );

/// clk_a (2) flop `a` -> 2-bit `$mux` -> clk_b (3) flop `b`, with bit 21 of
/// the mux output also driven by a `$not`.
NetlistModel _netlist() => NetlistModel(
  creator: 'hand-written',
  modules: <String, Module>{
    'top': Module(
      name: 'top',
      attributes: const <String, String>{'top': '1'},
      ports: const <String, Port>{},
      nets: const <String, Net>{},
      cells: <String, Cell>{
        'a': _cell('a', r'$dff', {
          'CLK': [2],
          'D': [4, 5],
          'Q': [10, 11],
        }),
        'mux': _cell('mux', r'$mux', {
          'A': [10, 11],
          'B': [12, 13],
          'S': [14],
          'Y': [20, 21],
        }),
        'inv': _cell('inv', r'$not', {
          'A': [15],
          'Y': [21],
        }),
        'b': _cell('b', r'$dff', {
          'CLK': [3],
          'D': [20, 21],
          'Q': [30, 31],
        }),
      },
    ),
  },
);

void main() {
  late Map<int, Set<int>> combSources;

  setUp(() {
    final classifier = _Recording();
    CdcDomainAnalysis(classifier: classifier).analyze(_netlist());
    expect(classifier.seen, isNotEmpty, reason: 'no crossing was classified');
    combSources = classifier.seen.first.combSources;
  });

  test('each output bit maps to every input of the cell driving it', () {
    expect(combSources[20], <int>{10, 11, 12, 13, 14});
  });

  test('a bit with two drivers maps to the inputs of both, in order', () {
    expect(combSources[21]!.toList(), <int>[10, 11, 12, 13, 14, 15]);
  });

  test('the output bits of one cell share one set', () {
    final netlist = _netlist();
    final cells = Map<String, Cell>.of(netlist.modules['top']!.cells)
      ..remove('inv');
    final classifier = _Recording();
    CdcDomainAnalysis(classifier: classifier).analyze(
      netlist.copyWith(
        modules: <String, Module>{
          'top': netlist.modules['top']!.copyWith(cells: cells),
        },
      ),
    );
    final shared = classifier.seen.first.combSources;
    expect(identical(shared[20], shared[21]), isTrue);
  });
}
