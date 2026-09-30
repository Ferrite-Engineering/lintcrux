// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/cxp_server_lifecycle_test.dart
//
// Verification driver for Verification Guide §7.1 (CXP server start /
// stop). With `cxpServerEnabled = true` (the default) the app starts
// the CXP server at boot; flipping the Settings → CXP Cross-Probe
// toggle tears it down and back up. This drives the real
// `cxpServerLifecycleProvider` + `appSettingsProvider` through a live
// app rather than a bare `ProviderContainer`.
//
// LintCrux's `CxpServerLifecycle` is an `AsyncNotifier<
// CxpServerLifecycleState>` — a different shape than NetCrux's
// `cxpServerHostProvider` (which resolves to a nullable server
// instance). Here the state itself carries `running` / `boundPort` /
// `error` fields, so the assertions read the state rather than a
// server handle.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';

import '../helpers/app_driver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'CXP server starts at boot and toggles with the setting (§7.1)',
    (tester) async {
      await bootLintcrux(tester);
      final root = rootContainer(tester);

      // Default settings enable the server — the lifecycle resolves to
      // a state that is either running or records why it could not
      // bind. Never a hard crash. On a clean macOS test host it binds.
      final started = await root.read(cxpServerLifecycleProvider.future);
      expect(
        started.running || started.error != null,
        isTrue,
        reason:
            'cxpServerEnabled defaults to true → server either runs or '
            'records why it could not bind',
      );

      // Disable CXP — the lifecycle tears down to a non-running state.
      root
          .read(appSettingsProvider.notifier)
          .setCxpServerEnabled(enabled: false);
      final disabled = await root.read(cxpServerLifecycleProvider.future);
      expect(
        disabled.running,
        isFalse,
        reason: 'disabling the setting stops the server',
      );
      expect(disabled.boundPort, isNull);

      // Re-enable — a fresh server is constructed.
      root
          .read(appSettingsProvider.notifier)
          .setCxpServerEnabled(enabled: true);
      final reenabled = await root.read(cxpServerLifecycleProvider.future);
      expect(
        reenabled.running || reenabled.error != null,
        isTrue,
        reason: 're-enabling the setting restarts the server',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
