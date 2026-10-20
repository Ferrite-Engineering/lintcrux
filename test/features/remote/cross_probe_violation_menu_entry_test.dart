// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/widgets/cross_probe_violation_menu_entry.dart';
import 'package:lintcrux/plugins/violation_context_menu_provider.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_binding.dart';

import '../../support/telemetry_test_store.dart';

/// The "Cross-probe to" item of a violation row's right-click menu, in every
/// tier: it is the open core's default entry, built from the shared submenu.

final List<(PeerIdentity, CrossProbeSelection?)> _sent = [];

class _FakeDispatcher extends CrossProbeDispatcher {
  _FakeDispatcher() : super(_unread);

  static T _unread<T>(ProviderListenable<T> provider) =>
      throw UnimplementedError('the fake reads nothing');

  @override
  Future<CrossProbeOutcome> send(
    PeerIdentity peer,
    CrossProbeSelection? selection, {
    String? label,
  }) async {
    _sent.add((peer, selection));
    return CrossProbeOutcome(CrossProbeOutcomeKind.sent, target: label);
  }
}

const _violation = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  location: SourceLocation(file: '/proj/src/cpu_alu.sv', line: 42, column: 7),
  message: 'unused',
);

PeerIdentity _peer(
  String product,
  int startedAt, {
  Set<String> capabilities = const <String>{},
}) => PeerIdentity(
  peerId: '$product-7-$startedAt',
  productName: product,
  productVersion: '1.2.0',
  capabilities: capabilities,
);

Widget _host(List<PeerIdentity> peers, {List<Override> extra = const []}) {
  final entry = buildCrossProbeViolationMenuEntry();
  return ProviderScope(
    overrides: [
      ...telemetryDeclinedOverrides(),
      cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding),
      cruxCxpPeersProvider.overrideWithValue(peers),
      cruxCxpServerStatusProvider.overrideWithValue((
        running: true,
        port: 54324,
        problem: null,
      )),
      cruxCxpRuntimeProvider.overrideWith((_) async => null),
      crossProbeDispatcherProvider.overrideWith((_) => _FakeDispatcher()),
      ...extra,
    ],
    child: MaterialApp(
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
      ),
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => entry.onActivate(context, ref, _violation),
              child: Text(entry.labelBuilder(context)),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(_sent.clear);

  test('the open core’s default violation menu offers it, with no tier', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final entries = container.read(violationContextMenuEntriesProvider);
    expect(entries.map((e) => e.id), <String>['crossProbeTo']);
  });

  testWidgets('lists the peer products, and choosing one sends the element '
      'kind it shows', (tester) async {
    await tester.pumpWidget(
      _host(<PeerIdentity>[
        _peer('wavecrux', 1),
        _peer('netcrux', 1),
        _peer('simcrux', 1),
      ]),
    );
    expect(find.text('Cross-probe to'), findsOneWidget);

    await tester.tap(find.text('Cross-probe to'));
    await tester.pumpAndSettle();
    expect(find.text('WaveCrux'), findsOneWidget);
    expect(find.text('NetCrux'), findsOneWidget);
    expect(find.text('SimCrux'), findsOneWidget);

    await tester.tap(find.text('NetCrux'));
    await tester.pumpAndSettle();

    expect(_sent, hasLength(1));
    final (peer, selection) = _sent.single;
    expect(peer.productName, 'netcrux');
    // NetCrux is shown the module the source file declares.
    expect(crossProbeElementFor(selection!, peer)?.kind, ElementKind.scope);
    expect(crossProbeElementFor(selection, peer)?.path, 'cpu_alu');
  });

  testWidgets('WaveCrux gets the source citation, LintCrux its own rule', (
    tester,
  ) async {
    await tester.pumpWidget(_host(<PeerIdentity>[_peer('wavecrux', 1)]));
    await tester.tap(find.text('Cross-probe to'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WaveCrux'));
    await tester.pumpAndSettle();

    final (wave, selection) = _sent.single;
    expect(
      crossProbeElementFor(selection!, wave)?.path,
      '/proj/src/cpu_alu.sv:42:7',
    );
    expect(
      crossProbeElementFor(selection, _peer('lintcrux', 1))?.kind,
      ElementKind.rule,
    );
    expect(
      selection.metadata['lintcrux.violation_severity'],
      'warning',
    );
  });

  testWidgets('with no peer running the item says so and explains what to '
      'start', (tester) async {
    await tester.pumpWidget(_host(const <PeerIdentity>[]));
    expect(find.text('Cross-probe to (no peers running)'), findsOneWidget);

    await tester.tap(find.text('Cross-probe to (no peers running)'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Start WaveCrux, NetCrux, LintCrux or SimCrux'),
      findsOneWidget,
    );
    expect(_sent, isEmpty);
    // Let the toast expire, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 10));
  });
}
