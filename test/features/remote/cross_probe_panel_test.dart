// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/providers/cross_probe_originate_gate_provider.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/remote/widgets/cross_probe_panel.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

import '../../support/telemetry_test_store.dart';

/// Widget tests for the docked cross-probe panel host
/// ([LintCruxCrossProbePanel]) — a thin host
/// over the shared `crux_cxp_ui.CrossProbePanel`, bridging LintCrux's live CXP
/// providers onto the shared controller contract.
Widget _wrap({
  required List<Override> overrides,
  Locale locale = const Locale('en'),
  Widget panel = const LintCruxCrossProbePanel(),
}) {
  return ProviderScope(
    overrides: [...telemetryDeclinedOverrides(), ...overrides],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 640,
          child: panel,
        ),
      ),
    ),
  );
}

class _FakeLifecycle extends CxpServerLifecycle {
  _FakeLifecycle(
    this._state, {
    this.ackHonored = true,
    this.ackReason,
    this.delivered = true,
    this.ackWait,
  });

  final CxpServerLifecycleState _state;
  final bool ackHonored;
  final String? ackReason;

  /// False models a peer that went away between the panel listing it and
  /// the send: the server reports `delivered: false` with no ack.
  final bool delivered;

  /// When set, the ack is held until this completes — the real server waits
  /// up to five seconds for it.
  final Future<void>? ackWait;
  final List<(String, CxpMessage)> sent = <(String, CxpMessage)>[];

  @override
  Future<CxpServerLifecycleState> build() async => _state;

  @override
  Future<({bool delivered, RequestHighlightAck? ack})> requestHighlight(
    String peerId,
    RequestHighlight request,
  ) async {
    sent.add((peerId, request));
    if (ackWait != null) await ackWait;
    if (!delivered) return (delivered: false, ack: null);
    return (
      delivered: true,
      ack: RequestHighlightAck(
        inReplyTo: 'req',
        honored: ackHonored,
        reason: ackReason,
      ),
    );
  }
}

/// A [SelectedViolationNotifier] pinned to [_fixed] so the panel's send has a
/// violation to encode without wiring the whole violation-table pipeline.
class _FixedSelectedViolation extends SelectedViolationNotifier {
  _FixedSelectedViolation(this._fixed);
  final Violation _fixed;

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

CxpServerLifecycleState _running() =>
    const CxpServerLifecycleState(running: true, boundPort: 54324);

void main() {
  group('LintCruxCrossProbePanel', () {
    testWidgets('shows the offline banner when the server is stopped', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                const CxpServerLifecycleState(running: false, boundPort: null),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cross_probe_offline_banner')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides the offline banner when the server is running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                _running(),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('cross_probe_offline_banner')),
        findsNothing,
      );
    });

    testWidgets('shows the peers-empty placeholder when no peers discovered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                _running(),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No peers discovered'), findsOneWidget);
    });

    testWidgets('renders a peer row (product + version + peerId)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                _running(),
              ),
            ),
            cxpPeersProvider.overrideWith(_FakePeersNotifier.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('wavecrux 0.7.0'), findsOneWidget);
      expect(find.textContaining('wavecrux-1'), findsOneWidget);
      // Each peer row carries the direct-send button, keyed by peer id.
      expect(
        find.byKey(const Key('cross_probe_send_wavecrux-1')),
        findsOneWidget,
      );
    });

    testWidgets('a rejected send (honored:false ack) raises a panel toast', (
      tester,
    ) async {
      final lifecycle = _FakeLifecycle(
        _running(),
        ackHonored: false,
        ackReason: 'no violation matches this rule in the current project',
      );
      await tester.pumpWidget(
        _wrap(
          overrides: [
            // Sending is Pro since the beta ended; these are about the send itself.
            licenseTierProvider.overrideWithValue(LicenseTier.pro),
            cxpServerLifecycleProvider.overrideWith(() => lifecycle),
            cxpPeersProvider.overrideWith(_FakePeersNotifier.new),
            selectedViolationProvider.overrideWith(
              () => _FixedSelectedViolation(_violation),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();

      expect(lifecycle.sent, hasLength(1));
      expect(lifecycle.sent.single.$2, isA<RequestHighlight>());
      expect(
        find.byKey(const Key('cross_probe_send_failure')),
        findsOneWidget,
      );
      expect(
        find.textContaining('no violation matches this rule'),
        findsOneWidget,
      );
    });

    testWidgets('a send to a peer that can no longer be reached raises a '
        'panel toast', (tester) async {
      // The peer is still listed, but it went away before the send: the
      // server reports the request as never delivered.
      final lifecycle = _FakeLifecycle(_running(), delivered: false);
      await tester.pumpWidget(
        _wrap(
          overrides: [
            // Sending is Pro since the beta ended; these are about the send itself.
            licenseTierProvider.overrideWithValue(LicenseTier.pro),
            cxpServerLifecycleProvider.overrideWith(() => lifecycle),
            cxpPeersProvider.overrideWith(_FakePeersNotifier.new),
            selectedViolationProvider.overrideWith(
              () => _FixedSelectedViolation(_violation),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();

      expect(lifecycle.sent, hasLength(1));
      final toast = find.byKey(const Key('cross_probe_send_failure'));
      expect(
        toast,
        findsOneWidget,
        reason:
            'a send is never a silent no-op; a press that reached nobody '
            'must say so',
      );
      expect(
        find.descendant(of: toast, matching: find.textContaining('wavecrux')),
        findsOneWidget,
        reason: 'the toast names the peer the send did not reach',
      );
    });

    testWidgets('a second failed send to the same peer raises its own toast', (
      tester,
    ) async {
      // Two failures to one peer compare equal. Published as-is, the second
      // would not notify the panel and the second press would be silent.
      final lifecycle = _FakeLifecycle(_running(), delivered: false);
      await tester.pumpWidget(
        _wrap(
          overrides: [
            // Sending is Pro since the beta ended; these are about the send itself.
            licenseTierProvider.overrideWithValue(LicenseTier.pro),
            cxpServerLifecycleProvider.overrideWith(() => lifecycle),
            cxpPeersProvider.overrideWith(_FakePeersNotifier.new),
            selectedViolationProvider.overrideWith(
              () => _FixedSelectedViolation(_violation),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final send = find.byKey(const Key('cross_probe_send_wavecrux-1'));
      final toast = find.byKey(const Key('cross_probe_send_failure'));

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(toast, findsOneWidget);

      // The first toast is gone by the time the user tries again.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(toast, findsNothing);

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(lifecycle.sent, hasLength(2));
      expect(toast, findsOneWidget, reason: 'the second press is not silent');
    });

    testWidgets('closing the panel while a send waits for its ack neither '
        'throws nor loses the probe count', (tester) async {
      final ackWait = Completer<void>();
      final lifecycle = _FakeLifecycle(
        _running(),
        // A refusal, so the send would also raise the failure toast on the
        // panel that is no longer there.
        ackHonored: false,
        ackWait: ackWait.future,
      );
      final telemetry = RecordingTelemetryService();
      final showPanel = ValueNotifier<bool>(true);
      addTearDown(showPanel.dispose);
      await tester.pumpWidget(
        _wrap(
          overrides: [
            telemetryServiceProvider.overrideWithValue(telemetry),
            // Sending is Pro since the beta ended; these are about the send itself.
            licenseTierProvider.overrideWithValue(LicenseTier.pro),
            cxpServerLifecycleProvider.overrideWith(() => lifecycle),
            cxpPeersProvider.overrideWith(_FakePeersNotifier.new),
            selectedViolationProvider.overrideWith(
              () => _FixedSelectedViolation(_violation),
            ),
          ],
          panel: ValueListenableBuilder<bool>(
            valueListenable: showPanel,
            builder: (_, show, _) => show
                ? const LintCruxCrossProbePanel()
                : const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pump();
      expect(lifecycle.sent, hasLength(1));

      // The user closes the panel inside the ack wait (up to five seconds in
      // the real server), which disposes the controller and its notifiers.
      showPanel.value = false;
      await tester.pump();
      expect(find.byType(LintCruxCrossProbePanel), findsNothing);

      ackWait.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        telemetry.only('cxp.crossprobe').properties,
        containsPair('honored', false),
        reason:
            'the probe reached the peer; closing the panel does not undo '
            'that, so it still counts',
      );
    });

    testWidgets('renders no unreachable rows when every peer is reachable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                _running(),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('renders a persistent warning row per unreachable peer', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                _running(),
              ),
            ),
            cxpDialFailuresProvider.overrideWith(_FakeDialFailuresNotifier.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.textContaining('wavecrux-9'), findsOneWidget);
      expect(find.textContaining('127.0.0.1:54399'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the events-empty placeholder with an empty log', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                _running(),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No cross-probe events'), findsOneWidget);
    });

    testWidgets('maps an inbound-request event onto the shared row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                _running(),
              ),
            ),
            cxpEventLogProvider.overrideWith(
              () => _SeededLogNotifier(
                CxpEventLog(
                  entries: [
                    CxpEventEntry(
                      timestamp: DateTime(2026, 5, 24, 12, 34, 56),
                      kind: CxpEventKind.inboundRequest,
                      summary: 'request_highlight from peer-99',
                      peerId: 'peer-99',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // The shared row subtitle is "<peerLabel> · <summary>"; the summary
      // carries the original wire text.
      expect(
        find.textContaining('request_highlight from peer-99'),
        findsOneWidget,
      );
      expect(find.textContaining('12:34:56'), findsOneWidget);
    });

    testWidgets('the clear-events button empties the log', (tester) async {
      await tester.pumpWidget(
        _wrap(
          overrides: [
            cxpServerLifecycleProvider.overrideWith(
              () => _FakeLifecycle(
                _running(),
              ),
            ),
            cxpEventLogProvider.overrideWith(
              () => _SeededLogNotifier(
                CxpEventLog(
                  entries: [
                    CxpEventEntry(
                      timestamp: DateTime(2026),
                      kind: CxpEventKind.peerConnected,
                      summary: 'wavecrux 0.7.0',
                      peerId: 'peer-99',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_clear_events')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No cross-probe events'), findsOneWidget);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(
            overrides: [
              cxpServerLifecycleProvider.overrideWith(
                () => _FakeLifecycle(
                  _running(),
                ),
              ),
              // Exercise the unreachable-peer warning row in every locale.
              cxpDialFailuresProvider.overrideWith(
                _FakeDialFailuresNotifier.new,
              ),
            ],
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the per-peer send button is a route to a Pro capability', () {
    // Origination is sold as Pro. The Pro overlay gates its own route (the
    // violation row's context-menu entry); this panel ships in open core and
    // its send button reaches the same capability, so it has to gate too.
    // Every test here pins the selection so that, absent a gate, the send
    // WOULD go through — which is what made the button a bypass.
    List<Override> gated({
      required bool beta,
      required LicenseTier tier,
      required _FakeLifecycle lifecycle,
    }) => [
      betaPeriodProvider.overrideWithValue(beta),
      licenseTierProvider.overrideWithValue(tier),
      cxpServerLifecycleProvider.overrideWith(() => lifecycle),
      cxpPeersProvider.overrideWith(_FakePeersNotifier.new),
      selectedViolationProvider.overrideWith(
        () => _FixedSelectedViolation(_violation),
      ),
    ];

    testWidgets('post-beta at Open Core: nothing is sent, and the user is '
        'told why', (tester) async {
      final lifecycle = _FakeLifecycle(_running());
      await tester.pumpWidget(
        _wrap(
          overrides: gated(
            beta: false,
            tier: LicenseTier.openCore,
            lifecycle: lifecycle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();

      expect(
        lifecycle.sent,
        isEmpty,
        reason:
            'the panel is open core and the send button reaches a Pro '
            'capability; without a gate here the overlay menu gate is a '
            'paywall with a second door',
      );
      expect(
        find.textContaining('requires LintCrux Pro'),
        findsOneWidget,
        reason: 'a denied press is never silent',
      );
    });

    testWidgets('post-beta at Pro: the send goes through', (tester) async {
      final lifecycle = _FakeLifecycle(_running());
      await tester.pumpWidget(
        _wrap(
          overrides: gated(
            beta: false,
            tier: LicenseTier.pro,
            lifecycle: lifecycle,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();

      expect(lifecycle.sent, hasLength(1));
      expect(find.textContaining('requires LintCrux Pro'), findsNothing);
    });

    testWidgets('EDU is feature-equivalent to Pro', (tester) async {
      final lifecycle = _FakeLifecycle(_running());
      await tester.pumpWidget(
        _wrap(
          overrides: gated(
            beta: false,
            tier: LicenseTier.edu,
            lifecycle: lifecycle,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();
      expect(lifecycle.sent, hasLength(1));
    });

    testWidgets('during the beta every tier sends', (tester) async {
      final lifecycle = _FakeLifecycle(_running());
      await tester.pumpWidget(
        _wrap(
          overrides: gated(
            beta: true,
            tier: LicenseTier.openCore,
            lifecycle: lifecycle,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();
      expect(lifecycle.sent, hasLength(1));
      expect(find.textContaining('requires LintCrux Pro'), findsNothing);
    });

    testWidgets('the panel asks the gate seam, so the Pro overlay can bind '
        'its own dialog', (tester) async {
      // The overlay overrides `crossProbeOriginateGateProvider` with its
      // activation choke point. That only guards anything if the panel
      // consults the seam rather than the tier directly.
      final lifecycle = _FakeLifecycle(_running());
      var asked = 0;
      await tester.pumpWidget(
        _wrap(
          overrides: [
            // A tier the default gate would ADMIT, so a send that still gets
            // through can only mean the seam was bypassed.
            ...gated(beta: true, tier: LicenseTier.pro, lifecycle: lifecycle),
            crossProbeOriginateGateProvider.overrideWith(
              (ref) => (_) {
                asked++;
                return false;
              },
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(lifecycle.sent, isEmpty);
    });
  });

  group('the send-failure toast is in the user language', () {
    // The shared panel falls back to English for this toast. Without the
    // app's strings it stayed English in every locale.
    Future<void> sendAndSettle(
      WidgetTester tester, {
      required Locale locale,
      required _FakeLifecycle lifecycle,
    }) async {
      await tester.pumpWidget(
        _wrap(
          locale: locale,
          overrides: [
            // Sending is Pro since the beta ended; these are about the send itself.
            licenseTierProvider.overrideWithValue(LicenseTier.pro),
            cxpServerLifecycleProvider.overrideWith(() => lifecycle),
            cxpPeersProvider.overrideWith(_FakePeersNotifier.new),
            selectedViolationProvider.overrideWith(
              () => _FixedSelectedViolation(_violation),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
      await tester.pumpAndSettle();
    }

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('a send that went nowhere, in $locale', (tester) async {
        await sendAndSettle(
          tester,
          locale: locale,
          lifecycle: _FakeLifecycle(_running(), delivered: false),
        );
        expect(
          find.text(lookupL10N(locale).crossProbeSendFailed('wavecrux')),
          findsOneWidget,
        );
      });

      testWidgets('a refusal with the peer reason, in $locale', (
        tester,
      ) async {
        const reason = 'no violation matches this rule';
        await sendAndSettle(
          tester,
          locale: locale,
          lifecycle: _FakeLifecycle(
            _running(),
            ackHonored: false,
            ackReason: reason,
          ),
        );
        expect(
          find.text(
            lookupL10N(locale).crossProbeSendRefused('wavecrux', reason),
          ),
          findsOneWidget,
          reason: 'the frame is translated; the reason is the peer words',
        );
      });
    }
  });

  group('LintCruxCrossProbePanel (locales)', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('denial snack renders without exception in $locale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            overrides: [
              betaPeriodProvider.overrideWithValue(false),
              licenseTierProvider.overrideWithValue(LicenseTier.openCore),
              cxpServerLifecycleProvider.overrideWith(
                () => _FakeLifecycle(_running()),
              ),
              cxpPeersProvider.overrideWith(_FakePeersNotifier.new),
            ],
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cross_probe_send_wavecrux-1')));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _FakePeersNotifier extends CxpPeersNotifier {
  @override
  List<CxpPeerManifest> build() {
    return [
      CxpPeerManifest(
        identity: const PeerIdentity(
          peerId: 'wavecrux-1',
          productName: 'wavecrux',
          productVersion: '0.7.0',
        ),
        host: '127.0.0.1',
        port: 54322,
        startedAt: DateTime.utc(2026),
        manifestPath: '/tmp/wavecrux-1.json',
      ),
    ];
  }
}

class _SeededLogNotifier extends CxpEventLogNotifier {
  _SeededLogNotifier(this._seed);

  final CxpEventLog _seed;

  @override
  CxpEventLog build() => _seed;
}

class _FakeDialFailuresNotifier extends CxpDialFailuresNotifier {
  @override
  List<CxpDialFailure> build() {
    return const [
      CxpDialFailure(
        peerId: 'wavecrux-9',
        host: '127.0.0.1',
        port: 54399,
        error: 'Connection refused',
        consecutiveFailures: 3,
        nextRetryAfterTicks: 4,
      ),
    ];
  }
}
