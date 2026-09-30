// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/remote/providers/violation_selection_emitter.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_server.dart';

Future<void> _pollUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not satisfied within 2s');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Fails if [condition] becomes true at any point over a short window.
Future<void> _expectNeverTrue(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(milliseconds: 200));
  while (DateTime.now().isBefore(deadline)) {
    expect(condition(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// SelectedViolationNotifier override that bypasses
/// [visibleViolationsProvider] (which depends on the project pipeline
/// the test doesn't bootstrap). Lets the test drive selection
/// directly via `select()` / `clear()`.
class _FakeSelectedViolationNotifier extends SelectedViolationNotifier {
  @override
  Violation? build() => state;
}

/// Seeds [appSettingsProvider] with a fixed [AppSettings] so tests can flip
/// `broadcastSelectionOnCrossProbe` for the auto-broadcast gate.
class _SeedSettingsNotifier extends AppSettingsNotifier {
  _SeedSettingsNotifier(this._seed);
  final AppSettings _seed;

  @override
  AppSettings build() => _seed;
}

const _v = Violation(
  engineId: 'verilator',
  ruleId: 'verilator/UNUSEDSIGNAL',
  severity: Severity.warning,
  message: 'Signal cpu.alu.sum[7:0] is declared but unused',
  location: SourceLocation(file: '/abs/path/cpu.sv', line: 42, column: 5),
);

const _vError = Violation(
  engineId: 'slang',
  ruleId: 'slang/ImplicitConvert',
  severity: Severity.error,
  message: 'Implicit width conversion',
  location: SourceLocation(file: '/abs/path/bus.sv', line: 7, column: 3),
);

void main() {
  group('ViolationSelectionEmitter', () {
    late LintCruxCxpServer server;
    late LocalCxpClient client;
    final receivedFrames = <CxpMessage>[];

    setUp(() async {
      receivedFrames.clear();
      server = LintCruxCxpServer(
        peerId: 'lintcrux-test',
        port: 0,
        onInbound: (_) {},
      );
      await server.start();
      client = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'wavecrux-test',
          productName: 'wavecrux-test',
          productVersion: '0.0.1',
        ),
      );
      client.inbound.listen((m) => receivedFrames.add(m.message));
      await client.connect(
        host: '127.0.0.1',
        port: server.boundPort!,
        token: cxpProcessAuthToken,
      );
      client.send(
        const Subscribe(
          subscriptions: [CxpSubscription(messageKind: 'notify_selection')],
        ),
      );
      // Wait for the subscribe handshake before broadcasting. Not
      // poll-able: `crux_cxp`'s server applies a peer's `Subscribe`
      // message synchronously in its line handler and returns before
      // ever reaching the `onInbound` callback (see
      // `_PeerConnection._onLine` in crux_cxp/cxp_server.dart), so
      // there is no publicly observable "subscription applied" signal
      // from this package's API short of adding one to the shared
      // `crux_cxp` package (out of scope here — it's consumed by
      // WaveCrux/NetCrux/SimCrux too).
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    tearDown(() async {
      try {
        await client.disconnect();
      } on Object {
        // best effort
      }
      await server.stop();
    });

    test(
      'emitter broadcasts NotifySelection on a violation selection, in every tier',
      () async {
        final container = ProviderContainer(
          overrides: [
            selectedViolationProvider.overrideWith(
              _FakeSelectedViolationNotifier.new,
            ),
            // Inject the running server via the lifecycle's broadcast
            // surface — the emitter calls
            // `ref.read(cxpServerLifecycleProvider.notifier).broadcast`.
            cxpServerLifecycleProvider.overrideWith(
              () => _RealLifecycleStub(server),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Realize the emitter (`ProjectTabContent` watches it per tab in
        // production).
        container.read(violationSelectionEmitterProvider);

        // Wait one microtask for the listen subscription to install.
        await Future<void>.delayed(Duration.zero);

        container.read(selectedViolationProvider.notifier).select(_v);
        await _pollUntil(() => receivedFrames.isNotEmpty);

        expect(receivedFrames, hasLength(1));
        final msg = receivedFrames.single;
        expect(msg, isA<NotifySelection>());
        final sel = msg as NotifySelection;
        expect(sel.elements, hasLength(1));
        expect(sel.elements.first.kind, ElementKind.rule);
        expect(
          sel.elements.first.path,
          'verilator/UNUSEDSIGNAL@/abs/path/cpu.sv:42:5',
        );
        expect(sel.displayName, 'verilator/UNUSEDSIGNAL');
        expect(sel.metadata['lintcrux.violation_severity'], 'warning');
        expect(sel.metadata['lintcrux.message'], _v.message);
      },
    );

    test(
      'severity metadata is the enum.name (e.g. "error" for an error)',
      () async {
        final container = ProviderContainer(
          overrides: [
            selectedViolationProvider.overrideWith(
              _FakeSelectedViolationNotifier.new,
            ),
            cxpServerLifecycleProvider.overrideWith(
              () => _RealLifecycleStub(server),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(violationSelectionEmitterProvider);
        await Future<void>.delayed(Duration.zero);

        container.read(selectedViolationProvider.notifier).select(_vError);
        await _pollUntil(() => receivedFrames.isNotEmpty);
        expect(
          (receivedFrames.single as NotifySelection)
              .metadata['lintcrux.violation_severity'],
          'error',
        );
      },
    );

    test(
      'long messages are truncated to 200 chars with trailing ellipsis',
      () async {
        final container = ProviderContainer(
          overrides: [
            selectedViolationProvider.overrideWith(
              _FakeSelectedViolationNotifier.new,
            ),
            cxpServerLifecycleProvider.overrideWith(
              () => _RealLifecycleStub(server),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(violationSelectionEmitterProvider);
        await Future<void>.delayed(Duration.zero);

        final longMessage = 'X' * 500;
        final longViolation = Violation(
          engineId: 'verilator',
          ruleId: 'verilator/HUGEMESSAGE',
          severity: Severity.warning,
          message: longMessage,
          location: const SourceLocation(file: '/abs/x.sv', line: 1, column: 1),
        );
        container
            .read(selectedViolationProvider.notifier)
            .select(longViolation);
        await _pollUntil(() => receivedFrames.isNotEmpty);
        final emitted =
            (receivedFrames.single as NotifySelection)
                    .metadata['lintcrux.message']!
                as String;
        expect(emitted.length, 200);
        expect(emitted.endsWith('…'), isTrue);
      },
    );

    test(
      'cxpPathFor formats <ruleId>@<file>:<line>:<column>',
      () {
        expect(
          cxpPathFor(_v),
          'verilator/UNUSEDSIGNAL@/abs/path/cpu.sv:42:5',
        );
      },
    );

    test(
      'auto-broadcast off: selecting a violation does NOT broadcast',
      () async {
        // `broadcastSelectionOnCrossProbe: false` must keep the emitter
        // silent so only explicit sends reach peers.
        final container = ProviderContainer(
          overrides: [
            appSettingsProvider.overrideWith(
              () => _SeedSettingsNotifier(
                const AppSettings(broadcastSelectionOnCrossProbe: false),
              ),
            ),
            selectedViolationProvider.overrideWith(
              _FakeSelectedViolationNotifier.new,
            ),
            cxpServerLifecycleProvider.overrideWith(
              () => _RealLifecycleStub(server),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(violationSelectionEmitterProvider);
        await Future<void>.delayed(Duration.zero);

        container.read(selectedViolationProvider.notifier).select(_v);
        await _expectNeverTrue(() => receivedFrames.isNotEmpty);
        expect(receivedFrames, isEmpty);
      },
    );

    test(
      'auto-broadcast on (default): selecting a violation broadcasts',
      () async {
        // Positive control: the same setup with the default (broadcast on)
        // still emits — pins that the setting above is what suppresses the
        // broadcast, not the harness.
        final container = ProviderContainer(
          overrides: [
            appSettingsProvider.overrideWith(
              () => _SeedSettingsNotifier(const AppSettings()),
            ),
            selectedViolationProvider.overrideWith(
              _FakeSelectedViolationNotifier.new,
            ),
            cxpServerLifecycleProvider.overrideWith(
              () => _RealLifecycleStub(server),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(violationSelectionEmitterProvider);
        await Future<void>.delayed(Duration.zero);

        container.read(selectedViolationProvider.notifier).select(_v);
        await _pollUntil(() => receivedFrames.isNotEmpty);
        expect(receivedFrames, hasLength(1));
        expect(receivedFrames.single, isA<NotifySelection>());
      },
    );
  });
}

/// Override of [CxpServerLifecycle] that points at the real, already-
/// running [LintCruxCxpServer] supplied by the test. The constructor
/// installs the server reference via the private `_server` field —
/// not legal — so we instead rebuild the base class to expose
/// `broadcast` that delegates to our server directly.
class _RealLifecycleStub extends CxpServerLifecycle {
  _RealLifecycleStub(this._injected);
  final LintCruxCxpServer _injected;

  @override
  Future<CxpServerLifecycleState> build() async {
    return CxpServerLifecycleState(
      running: true,
      boundPort: _injected.boundPort,
      peerId: _injected.selfIdentity.peerId,
    );
  }

  @override
  void broadcast(CxpMessage message) => _injected.broadcast(message);
}
