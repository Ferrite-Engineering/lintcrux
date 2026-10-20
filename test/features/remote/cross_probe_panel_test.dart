// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_binding.dart';

import '../../support/telemetry_test_store.dart';

/// Widget tests for the docked cross-probe panel ([LintCruxCrossProbePanel]):
/// the shared, bound panel with LintCrux's selection and close behaviour. The
/// peer list, the event log, the unreachable rows and the send outcomes are the
/// shared runtime's own tests; what is LintCrux's is which selection a row
/// sends and how the panel closes.

/// Every send the fake dispatcher saw in the current test.
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

/// A [SelectedViolationNotifier] pinned to [_fixed] so the panel's send has a
/// violation to encode without wiring the whole violation-table pipeline.
class _FixedSelectedViolation extends SelectedViolationNotifier {
  _FixedSelectedViolation(this._fixed);
  final Violation? _fixed;

  @override
  Violation? build() => _fixed;
}

const _violation = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  location: SourceLocation(file: '/a.sv', line: 3, column: 1),
  message: 'unused',
);

const _wavecrux = PeerIdentity(
  peerId: 'wavecrux-1',
  productName: 'wavecrux',
  productVersion: '0.7.0',
);

Widget _wrap({
  List<PeerIdentity> peers = const <PeerIdentity>[],
  bool running = true,
  Violation? selected = _violation,
  Locale locale = const Locale('en'),
  List<Override> extra = const <Override>[],
}) {
  return ProviderScope(
    overrides: [
      ...telemetryDeclinedOverrides(),
      cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding),
      cruxCxpPeersProvider.overrideWithValue(peers),
      cruxCxpServerStatusProvider.overrideWithValue((
        running: running,
        port: running ? 54324 : null,
        problem: null,
      )),
      cruxCxpUnreachablePeersProvider.overrideWith(
        (_) => Stream<List<CxpDialFailure>>.value(const <CxpDialFailure>[]),
      ),
      cruxCxpRuntimeProvider.overrideWith((_) async => null),
      crossProbeDispatcherProvider.overrideWith((_) => _FakeDispatcher()),
      selectedViolationProvider.overrideWith(
        () => _FixedSelectedViolation(selected),
      ),
      ...extra,
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(
        body: SizedBox(
          width: 360,
          height: 640,
          child: LintCruxCrossProbePanel(),
        ),
      ),
    ),
  );
}

void main() {
  setUp(_sent.clear);

  group('LintCruxCrossProbePanel', () {
    testWidgets('is the shared bound panel', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byType(CruxCrossProbePanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the shared peers-empty placeholder with no peers', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('No peers connected'), findsOneWidget);
    });

    testWidgets('renders a connected peer row with its send button', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(peers: const [_wavecrux]));
      await tester.pumpAndSettle();
      expect(find.textContaining('wavecrux 0.7.0'), findsOneWidget);
      expect(
        find.byKey(const Key('cross_probe_send_wavecrux-1')),
        findsOneWidget,
      );
    });

    testWidgets('a peer row sends the active tab’s selected violation, named '
        'in every kind it has', (tester) async {
      await tester.pumpWidget(_wrap(peers: const [_wavecrux]));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();

      expect(_sent, hasLength(1));
      expect(_sent.single.$1.peerId, 'wavecrux-1');
      final selection = _sent.single.$2!;
      expect(
        selection.candidates.map((c) => c.kind),
        <ElementKind>[
          ElementKind.rule,
          ElementKind.scope,
          ElementKind.source,
        ],
      );
      expect(selection.metadata['lintcrux.violation_severity'], 'warning');
      // WaveCrux is shown the source citation.
      expect(
        crossProbeElementFor(selection, _wavecrux)?.path,
        '/a.sv:3:1',
      );
    });

    testWidgets('with nothing selected the send carries no selection, and the '
        'shared send says so', (tester) async {
      await tester.pumpWidget(
        _wrap(peers: const [_wavecrux], selected: null),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();

      expect(_sent.single.$2, isNull);
    });

    testWidgets('the shared panel closes through the panel-layout flag', (
      tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        _wrap(
          extra: [
            panelLayoutProvider.overrideWith(PanelLayoutNotifier.new),
          ],
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(LintCruxCrossProbePanel)),
      );
      container
          .read(panelLayoutProvider.notifier)
          .setCrossProbeVisible(visible: true);
      expect(container.read(panelLayoutProvider).crossProbeVisible, isTrue);

      final panel = tester.widget<CruxCrossProbePanel>(
        find.byType(CruxCrossProbePanel),
      );
      panel.onClose();
      expect(container.read(panelLayoutProvider).crossProbeVisible, isFalse);
    });

    for (final locale in L10N.supportedLocales) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(peers: const [_wavecrux], locale: locale),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
