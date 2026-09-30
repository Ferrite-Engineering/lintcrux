// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/cxp_inbound_highlight_journey_test.dart
//
// Receive-side CXP journey, end to end in a running app: a real
// LocalCxpClient peer connects over a real socket to the live app
// server and sends RequestHighlight. The ACTIVE tab's violation store
// resolves the element, the visible table narrows and selects the row,
// and the peer gets RequestHighlightAck(honored: true) back over the
// wire.
//
// This is the inbound counterpart to the Pro repo's
// cxp_originate journey (which proves the outbound direction). Together
// they cover the whole chain now that the transport carries connector
// traffic and the per-tab scoping resolves the ACTIVE tab.
//
// Why the project is opened through openFixtureProject rather than
// seeded at root scope: the violation store the handler searches is a
// PER-TAB provider resolved through activeTabContainerHandleProvider at
// dispatch time. A root-scope seed would pass against a store no user
// can reach and would not catch a regression in the active-tab
// resolution.

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';

import '../helpers/app_driver.dart';
import '../helpers/cxp_test_barrier.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'inbound RequestHighlight resolves against the ACTIVE tab and acks '
    'honored (real socket over the live app server)',
    (tester) async {
      // Seeding the violation table trips the debug-only first-build
      // provider self-invalidation wart (PENDING.md "Known issues"). It
      // can land on a frame after the triggering line, so filter it at
      // the source rather than reaching for `takeException` later.
      tolerateKnownFirstBuildWart();
      final projectDir = Directory.systemTemp.createTempSync(
        'lintcrux_cxp_inbound_',
      );
      final manifestDir = Directory.systemTemp.createTempSync(
        'lintcrux_cxp_inbound_manifest_',
      );
      addTearDown(() {
        for (final dir in [projectDir, manifestDir]) {
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // Best-effort cleanup.
          }
        }
      });

      // Hermetic manifest dir so discovery finds no real peers and this
      // run does not litter the developer's app-support directory.
      await bootLintcrux(
        tester,
        extraOverrides: [
          cxpManifestDirectoryProvider.overrideWith((ref) async {
            return manifestDir.path;
          }),
        ],
      );
      final root = rootContainer(tester);

      // Open a real project through the File → Open seam, then seed a
      // completed run into THAT tab's store.
      final projectPath = await createFixtureProject(
        projectDir,
        sources: {'rtl/cpu.sv': 'module cpu; endmodule\n'},
      );
      final tab = await openFixtureProject(tester, projectPath);
      final sourceFile = '${projectDir.path}/rtl/cpu.sv';
      final unusedLine =
          "%Warning-UNUSEDSIGNAL: $sourceFile:42:5: Signal is not used: 'sum'";
      final widthLine =
          '%Warning-WIDTH: $sourceFile:88:3: Operator ASSIGN expects '
          '8 bits on the Assign RHS.';
      final violations = parseVerilatorFixture(projectDir.path, [
        unusedLine,
        widthLine,
      ]);
      expect(violations, hasLength(2));
      await seedLintRun(tester, tab, violations: violations);
      expect(tab.read(selectedViolationProvider), isNull);

      // Connect a real peer to the live server's socket.
      final serverState = await root.read(cxpServerLifecycleProvider.future);
      expect(
        serverState.running,
        isTrue,
        reason:
            'the CXP server did not start on this host '
            '(error: ${serverState.error})',
      );
      final port = serverState.boundPort;
      expect(port, isNotNull);

      final peer = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'lintcrux-cxp-inbound-it-peer',
          productName: 'wavecrux',
          productVersion: '0.0.0-test',
          capabilities: <String>{'request_highlight'},
        ),
      );
      addTearDown(peer.dispose);

      // Record acks and errors; the barrier round-trips its own
      // unknown-kind ErrorResponse through this same stream, so filter
      // those out by code rather than by type.
      final acks = <RequestHighlightAck>[];
      final errors = <ErrorResponse>[];
      final sub = peer.inbound.listen((inbound) {
        final message = inbound.message;
        if (message is RequestHighlightAck) {
          acks.add(message);
        } else if (message is ErrorResponse &&
            message.code != CxpErrorCode.unknownKind) {
          errors.add(message);
        }
      });
      addTearDown(sub.cancel);
      await peer.connect(
        host: '127.0.0.1',
        port: port!,
        token: cxpProcessAuthToken,
      );
      await cxpRoundTripBarrier(peer);

      // 1. Highlight a violation the active tab really holds.
      final target = violations.firstWhere((v) => v.location.line == 88);
      peer.send(
        RequestHighlight(
          element: ElementId(
            kind: ElementKind.rule,
            path: LintCruxNameResolver.encodeViolationAsRulePath(target)!,
          ),
        ),
      );
      final acked = await pumpUntil(tester, () => acks.isNotEmpty);
      expect(acked, isTrue, reason: 'the peer never received an ack');
      expect(acks.single.honored, isTrue, reason: acks.single.reason);

      // The ACTIVE tab's table really moved: the row is selected and
      // visible (the handler clears filters so it cannot be hidden).
      expect(tab.read(selectedViolationProvider), target);
      expect(visibleViolations(tab), contains(target));

      // 2. Highlight a violation the tab does NOT hold — honored:false
      // with a reason, and the prior selection is left alone rather than
      // silently cleared.
      acks.clear();
      peer.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.rule,
            path: 'verilator/NOSUCHRULE@/nowhere/absent.sv:1:1',
          ),
        ),
      );
      final refused = await pumpUntil(tester, () => acks.isNotEmpty);
      expect(refused, isTrue, reason: 'the peer never received a refusal ack');
      expect(acks.single.honored, isFalse);
      expect(acks.single.reason, contains('No matching violation'));
      expect(
        tab.read(selectedViolationProvider),
        target,
        reason: 'an unhonoured highlight must not disturb the selection',
      );

      expect(
        errors,
        isEmpty,
        reason: 'no protocol errors on the supported request path',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
