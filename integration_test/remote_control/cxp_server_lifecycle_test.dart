// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/cxp_server_lifecycle_test.dart
//
// Verification driver for Verification Guide §7.1 (CXP server start /
// stop). With the CXP enable setting on (the default) the app starts the CXP
// server at boot; flipping the Settings → CXP Cross-Probe toggle tears it
// down and back up. This drives the real shared `cruxCxpRuntimeProvider` and
// `cruxCxpSettingsProvider` through a live app rather than a bare
// `ProviderContainer`.
//
// The runtime is a nullable value: null when CXP is off, otherwise the
// running server, whose `isAvailable` / `unavailableReason` say whether the
// socket bound.

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'CXP server starts at boot and toggles with the setting (§7.1)',
    (tester) async {
      await bootLintcrux(tester);
      final root = rootContainer(tester);

      // Default settings enable the server — the runtime resolves to a
      // server that is either available or records why it could not bind.
      // Never a hard crash. On a clean macOS test host it binds.
      final started = await root.read(cruxCxpRuntimeProvider.future);
      expect(
        started != null &&
            (started.isAvailable || started.unavailableReason != null),
        isTrue,
        reason:
            'the enable setting defaults to true → the server either runs '
            'or records why it could not bind',
      );

      // Disable CXP — the runtime tears down.
      await root
          .read(cruxCxpSettingsProvider.notifier)
          .setEnabled(enabled: false);
      final disabled = await root.read(cruxCxpRuntimeProvider.future);
      expect(
        disabled,
        isNull,
        reason: 'disabling the setting stops the server',
      );
      expect(root.read(cruxCxpServerStatusProvider).running, isFalse);

      // Re-enable — a fresh server is constructed.
      await root
          .read(cruxCxpSettingsProvider.notifier)
          .setEnabled(enabled: true);
      final reenabled = await root.read(cruxCxpRuntimeProvider.future);
      expect(
        reenabled != null &&
            (reenabled.isAvailable || reenabled.unavailableReason != null),
        isTrue,
        reason: 're-enabling the setting restarts the server',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
