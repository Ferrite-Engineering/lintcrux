// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_codec.dart';

/// The [SettingsService] that reads and writes the Settings → General
/// "Restore tabs on launch" preference.
///
/// Override in tests with a `SettingsService(codec, prefsOverride: prefs)` so
/// the round trip runs against `SharedPreferences.setMockInitialValues`
/// rather than the platform plugin.
final Provider<SettingsService<bool>> restoreTabsSettingsServiceProvider =
    Provider<SettingsService<bool>>(
      (_) => const SettingsService<bool>(RestoreTabsSettingsCodec()),
      name: 'restoreTabsSettingsServiceProvider',
    );

/// Whether this launch rehydrates the persisted workspace document.
///
/// Read **synchronously** by `LintcruxWorkspaceNotifier.shouldRestoreOnLaunch`
/// before `WorkspaceService.load`. The default is `true`; `bootstrap` resolves
/// [loadRestoreTabsOnLaunch] once, before `runApp`, and overrides this with
/// the persisted answer.
///
/// **The launch gate must not await storage, and this seam is why.** The
/// obvious implementation — awaiting the settings service from inside the
/// notifier's `build` — hangs every widget test that touches a workspace.
/// `SharedPreferences.getInstance()` replies on the *real* event loop, which
/// the fake-async zone a `testWidgets` body runs in never advances, so a
/// future awaited before the first pump never completes and the test times
/// out rather than failing. Two nearby workarounds are also wrong: awaiting
/// `appSettingsProvider.future` additionally hands the launch to Riverpod's
/// failure retry (a throwing load stays pending across every retry), and
/// stubbing the settings *service* in tests resolves `appSettingsProvider`,
/// which panel-layout state watches — re-seeding panel state mid-test.
///
/// Resolving the value in `bootstrap` and handing the notifier a plain `bool`
/// removes the await entirely: production reads storage exactly once on the
/// real event loop where that is fine, and tests get a synchronous default
/// with no override and no storage call at all. A test that wants the
/// declining path overrides this provider with `false`.
final Provider<bool> launchRestoreDecisionProvider = Provider<bool>(
  (_) => RestoreTabsSettingsCodec.defaultValue,
  name: 'launchRestoreDecisionProvider',
);

/// Loads the persisted "Restore tabs on launch" preference, defaulting to
/// restoring on any failure.
///
/// Called once from `bootstrap`, before the widget tree exists. A failure
/// here means no preferences backend (plugin not registered, unreadable
/// store); losing a session because a *preference* was unreadable is the
/// worse of the two mistakes, so it resolves to `true`.
///
/// [service] is injectable for tests; production passes nothing.
Future<bool> loadRestoreTabsOnLaunch({SettingsService<bool>? service}) async {
  try {
    return await (service ??
            const SettingsService<bool>(RestoreTabsSettingsCodec()))
        .load();
  } on Object {
    return RestoreTabsSettingsCodec.defaultValue;
  }
}
