// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/providers/violation_selection_emitter.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_binding.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ViolationSelectionEmitter', () {
    late Directory peersDir;
    late LocalCxpClient client;
    final receivedFrames = <CxpMessage>[];

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      peersDir = Directory.systemTemp.createTempSync('lintcrux_emitter_');
      receivedFrames.clear();
    });

    tearDown(() async {
      try {
        await client.disconnect();
      } on Object {
        // best effort
      }
      if (peersDir.existsSync()) peersDir.deleteSync(recursive: true);
    });

    /// The shared runtime on an OS-chosen port, with a peer connected that
    /// subscribed to `notify_selection`, as a WaveCrux next to LintCrux is.
    Future<ProviderContainer> start({bool broadcastSelection = true}) async {
      final container = ProviderContainer(
        overrides: [
          selectedViolationProvider.overrideWith(
            _FakeSelectedViolationNotifier.new,
          ),
          cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding),
          cruxCxpLaunchSettingsProvider.overrideWithValue(
            CruxCxpSettings(
              enabled: true,
              port: 0,
              broadcastSelection: broadcastSelection,
            ),
          ),
          cruxCxpTransportAvailableProvider.overrideWithValue(true),
          cruxCxpManifestDirectoryProvider.overrideWith(
            (ref) async => peersDir.path,
          ),
        ],
      );
      addTearDown(container.dispose);
      final runtime = await container.read(cruxCxpRuntimeProvider.future);
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
        port: runtime!.boundPort!,
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
      // ever reaching the inbound stream, so there is no publicly observable
      // "subscription applied" signal from that package's API.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Realize the emitter (`ProjectTabContent` watches it per tab in
      // production).
      container.read(violationSelectionEmitterProvider);
      // Wait one microtask for the listen subscription to install.
      await Future<void>.delayed(Duration.zero);
      return container;
    }

    test(
      'emitter broadcasts NotifySelection on a violation selection, in every tier',
      () async {
        final container = await start();

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
        final container = await start();

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
        final container = await start();

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
        // The shared broadcast setting off must keep the emitter silent so
        // only explicit sends reach peers.
        final container = await start(broadcastSelection: false);

        container.read(selectedViolationProvider.notifier).select(_v);
        await _expectNeverTrue(() => receivedFrames.isNotEmpty);
        expect(receivedFrames, isEmpty);
      },
    );

    test(
      'auto-broadcast follows the setting at once: off, then on again',
      () async {
        final container = await start(broadcastSelection: false);
        final settings = container.read(cruxCxpSettingsProvider.notifier);

        container.read(selectedViolationProvider.notifier).select(_v);
        await _expectNeverTrue(() => receivedFrames.isNotEmpty);

        await settings.setBroadcastSelection(broadcastSelection: true);
        container.read(selectedViolationProvider.notifier).select(_vError);
        await _pollUntil(() => receivedFrames.isNotEmpty);
        expect(receivedFrames.single, isA<NotifySelection>());
      },
    );

    test(
      'auto-broadcast on (default): selecting a violation broadcasts',
      () async {
        // Positive control: the same setup with the default (broadcast on)
        // still emits — pins that the setting above is what suppresses the
        // broadcast, not the harness.
        final container = await start();

        container.read(selectedViolationProvider.notifier).select(_v);
        await _pollUntil(() => receivedFrames.isNotEmpty);
        expect(receivedFrames, hasLength(1));
        expect(receivedFrames.single, isA<NotifySelection>());
      },
    );
  });
}
