// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_license/crux_license.dart';
import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/policy/lintcrux_policy_keys.dart';
import 'package:lintcrux/domain/enums/elaboration_time_limit.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/services/persistence/auto_update_check_settings_provider.dart';
import 'package:lintcrux/services/persistence/diagnostics_enabled_settings_provider.dart';
import 'package:lintcrux/services/persistence/elaboration_time_limit_settings_provider.dart';
import 'package:lintcrux/services/persistence/engine_binary_overrides_settings_provider.dart';
import 'package:lintcrux/services/persistence/locale_settings_provider.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_provider.dart';

/// Manages the [AppSettings] for the running app.
///
/// `build()` returns the model defaults and every mutator updates the
/// in-memory state immediately. Persistence is per-field rather than
/// whole-model: [setAutoCheckForUpdates] round-trips through
/// [autoUpdateCheckSettingsServiceProvider], [setDiagnosticsEnabled] through
/// [diagnosticsEnabledSettingsServiceProvider], [setElaborationTimeLimit]
/// through [elaborationTimeLimitSettingsServiceProvider], the engine binary
/// overrides through [engineBinaryOverridesSettingsServiceProvider] (seeded at
/// launch from [launchEngineBinaryOverridesProvider]), and the theme name and
/// token overrides reach `cruxColorThemeProvider` through the bootstrap
/// bridge. The
/// CXP Cross-Probe settings are not here: `cruxCxpSettingsProvider` owns and
/// saves them. The remaining fields (panel layout) are session-scoped in
/// open-core.
///
/// Mirrors the WaveCrux `appSettingsProvider` notifier pattern.
final NotifierProvider<AppSettingsNotifier, AppSettings> appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(
      AppSettingsNotifier.new,
    );

/// Notifier backing [appSettingsProvider].
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // Restore the one field open-core actually persists. Synchronous default
    // first (so consumers never see a null / loading state), then overlay the
    // stored value when it arrives — the same shape `ShortcutBindingsNotifier`
    // uses for its persisted key bindings.
    unawaited(_restoreAutoCheckForUpdates());
    unawaited(_restoreRestoreTabsOnLaunch());
    unawaited(_restoreLocale());
    unawaited(_restoreDiagnosticsEnabled());
    unawaited(_restoreElaborationTimeLimit());
    // Synchronous, unlike the restores above: the overrides pick the binary
    // the first run starts, and a restored tab runs as soon as it opens.
    return AppSettings(
      engineBinaryOverrides: ref.read(launchEngineBinaryOverridesProvider),
    );
  }

  /// Set once the user changes the Language preference at run time — same
  /// guard as [_restoreTabsTouched]: the asynchronous build-time restore
  /// must not overwrite a click that landed before it resolved.
  bool _localeTouched = false;

  Future<void> _restoreLocale() async {
    final String stored;
    try {
      stored = await ref.read(localeSettingsServiceProvider).load();
    } on Object {
      // See [_restoreAutoCheckForUpdates] — no preferences backend.
      return;
    }
    if (!ref.mounted || _localeTouched) return;
    if (state.core.locale == stored) return;
    state = state.copyWith(locale: stored);
  }

  /// Persists the UI language ([CoreSettings.locale]); `app.dart` watches
  /// it and rebuilds `MaterialApp.locale`, so the switch applies live.
  void setLocale(String locale) {
    _localeTouched = true;
    if (state.core.locale == locale) return;
    state = state.copyWith(locale: locale);
    unawaited(_persistLocale(locale));
  }

  Future<void> _persistLocale(String locale) async {
    try {
      await ref.read(localeSettingsServiceProvider).save(locale);
    } on Object {
      // See [_persistAutoCheckForUpdates]: no preferences backend. The
      // in-memory state already changed, so the picker still works for the
      // running session.
    }
  }

  /// Set once the user changes the restore-tabs preference at run time.
  ///
  /// The build-time restore below is asynchronous, so a toggle flipped
  /// before it resolves would otherwise be overwritten by the value that was
  /// on disk when the app started — the user's click silently undone a
  /// moment later.
  bool _restoreTabsTouched = false;

  Future<void> _restoreRestoreTabsOnLaunch() async {
    final bool stored;
    try {
      stored = await ref.read(restoreTabsSettingsServiceProvider).load();
    } on Object {
      // See [_restoreAutoCheckForUpdates] — no preferences backend.
      return;
    }
    if (!ref.mounted || _restoreTabsTouched) return;
    if (state.restoreTabsOnLaunch == stored) return;
    state = state.copyWith(restoreTabsOnLaunch: stored);
  }

  /// Set once the user changes the auto-check preference at run time — same
  /// guard as [_restoreTabsTouched]: the asynchronous build-time restore
  /// must not overwrite a toggle that landed before it resolved.
  bool _autoCheckTouched = false;

  Future<void> _restoreAutoCheckForUpdates() async {
    final bool stored;
    try {
      stored = await ref.read(autoUpdateCheckSettingsServiceProvider).load();
    } on Object {
      // No preferences backend — a pure-Dart unit-test host with no Flutter
      // binding, or a platform where the plugin is unavailable. Keeping the
      // model default (automatic checks on) is the right answer in both
      // cases, and a settings restore is never worth failing a launch over.
      return;
    }
    if (!ref.mounted || _autoCheckTouched) return;
    if (state.autoCheckForUpdates == stored) return;
    state = state.copyWith(autoCheckForUpdates: stored);
  }

  /// Replaces the whole settings object. Used by the bootstrap
  /// override to seed the notifier from the persisted snapshot.
  void replace(AppSettings next) {
    if (state == next) return;
    state = next;
  }

  /// Updates the active theme mode (light / dark / system).
  void setThemeMode(AppThemeMode mode) {
    if (state.themeMode == mode) return;
    state = state.copyWith(themeMode: mode);
  }

  /// Sets the active color-theme preset id (e.g. `crux-dark`,
  /// `solarized-dark`). Wired through `cruxColorThemeProvider` by the
  /// LintCrux notifier override — the in-memory theme rebuilds from
  /// the persisted name + overrides on the next read.
  void setActiveThemeName(String name) {
    if (state.core.activeThemeName == name) return;
    state = state.copyWith(activeThemeName: name);
  }

  /// Replaces the flat token-path override map fed into the
  /// `cruxColorThemeProvider` bridge. Pass an empty map to clear all
  /// overrides.
  void setThemeOverrides(Map<String, String> overrides) {
    if (_overrideMapsEqual(state.core.themeOverrides, overrides)) return;
    state = state.copyWith(
      themeOverrides: Map<String, String>.unmodifiable(overrides),
    );
  }

  static bool _overrideMapsEqual(
    Map<String, String> a,
    Map<String, String> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Updates the auto-reload-on-source-change mode (auto / prompt / off).
  void setAutoReloadMode(AutoReloadMode mode) {
    if (state.autoReloadMode == mode) return;
    state = state.copyWith(autoReloadMode: mode);
  }

  /// Set once the user changes the diagnostics preference at run time —
  /// same guard as [_restoreTabsTouched].
  bool _diagnosticsTouched = false;

  Future<void> _restoreDiagnosticsEnabled() async {
    final bool stored;
    try {
      stored = await ref.read(diagnosticsEnabledSettingsServiceProvider).load();
    } on Object {
      // See [_restoreAutoCheckForUpdates] — no preferences backend.
      return;
    }
    if (!ref.mounted || _diagnosticsTouched) return;
    if (state.diagnosticsEnabled == stored) return;
    state = state.copyWith(diagnosticsEnabled: stored);
  }

  /// Sets and persists the diagnostics-enabled flag: the release-build
  /// opt-in `diagnosticsEnabledProvider` reads for the Tab Diagnostics
  /// drawer and the App Diagnostics dialog.
  void setDiagnosticsEnabled({required bool enabled}) {
    _diagnosticsTouched = true;
    if (state.diagnosticsEnabled == enabled) return;
    state = state.copyWith(diagnosticsEnabled: enabled);
    unawaited(_persistDiagnosticsEnabled(enabled));
  }

  Future<void> _persistDiagnosticsEnabled(bool enabled) async {
    try {
      await ref.read(diagnosticsEnabledSettingsServiceProvider).save(enabled);
    } on Object {
      // See [_persistAutoCheckForUpdates]: no preferences backend. The
      // in-memory state already changed, so the switch still works for the
      // running session.
    }
  }

  /// Set once the user changes the Yosys time limit at run time — same guard
  /// as [_restoreTabsTouched].
  bool _elaborationTimeLimitTouched = false;

  Future<void> _restoreElaborationTimeLimit() async {
    final ElaborationTimeLimit stored;
    try {
      stored = await ref
          .read(elaborationTimeLimitSettingsServiceProvider)
          .load();
    } on Object {
      // See [_restoreAutoCheckForUpdates] — no preferences backend.
      return;
    }
    if (!ref.mounted || _elaborationTimeLimitTouched) return;
    if (state.elaborationTimeLimit == stored) return;
    state = state.copyWith(elaborationTimeLimit: stored);
  }

  /// Sets and persists how long an engine that elaborates the design with
  /// Yosys may run (see [AppSettings.elaborationTimeLimit]). Takes effect on
  /// the next run.
  void setElaborationTimeLimit(ElaborationTimeLimit limit) {
    _elaborationTimeLimitTouched = true;
    if (state.elaborationTimeLimit == limit) return;
    state = state.copyWith(elaborationTimeLimit: limit);
    unawaited(_persistElaborationTimeLimit(limit));
  }

  Future<void> _persistElaborationTimeLimit(ElaborationTimeLimit limit) async {
    try {
      await ref.read(elaborationTimeLimitSettingsServiceProvider).save(limit);
    } on Object {
      // See [_persistAutoCheckForUpdates]: no preferences backend. The
      // in-memory state already changed, so the next run still uses it.
    }
  }

  /// Sets the per-engine binary override for [engineId].
  /// Passing [EngineBinaryOverride.autoDetect] removes the override
  /// entry entirely (so the persisted blob doesn't carry redundant
  /// auto-detect markers).
  ///
  /// Recorded as [LintCruxAuditKinds.engineConfigChanged]. Repointing an
  /// engine changes which binary runs against the organization's RTL, so
  /// "which lint tool actually produced this result" stops being answerable
  /// from the result alone — which is exactly the question an audit trail
  /// exists to answer later.
  void setEngineBinaryOverride(
    String engineId,
    EngineBinaryOverride override,
  ) {
    final current = state.engineBinaryOverrides;
    final next = Map<String, EngineBinaryOverride>.from(current);
    if (override == EngineBinaryOverride.autoDetect) {
      next.remove(engineId);
    } else {
      next[engineId] = override;
    }
    if (_overridesEqual(current, next)) return;
    state = state.copyWith(engineBinaryOverrides: next);
    unawaited(_persistEngineBinaryOverrides(next));
    _recordEngineConfigChange(<String, Object?>{
      'engineId': engineId,
      'source': override.source.name,
      // Whether a custom path was supplied, never what it is — see below.
      'hasCustomPath': (override.path ?? '').isNotEmpty,
    });
  }

  /// Clears every per-engine binary override.
  void clearEngineBinaryOverrides() {
    if (state.engineBinaryOverrides.isEmpty) return;
    final cleared = state.engineBinaryOverrides.keys.toList()..sort();
    state = state.copyWith(
      engineBinaryOverrides: const <String, EngineBinaryOverride>{},
    );
    unawaited(
      _persistEngineBinaryOverrides(const <String, EngineBinaryOverride>{}),
    );
    _recordEngineConfigChange(<String, Object?>{
      'engineId': null,
      'source': 'clearedAll',
      'engines': cleared,
    });
  }

  Future<void> _persistEngineBinaryOverrides(
    Map<String, EngineBinaryOverride> overrides,
  ) async {
    try {
      await ref
          .read(engineBinaryOverridesSettingsServiceProvider)
          .save(
            overrides,
          );
    } on Object {
      // See [_persistAutoCheckForUpdates]: no preferences backend. The
      // in-memory state already changed, so the override still applies to
      // this session's runs.
    }
  }

  /// Records an engine-configuration change.
  ///
  /// **The binary PATH is deliberately not in the payload.** A user's engine
  /// override is a filesystem path that routinely carries their username, and
  /// this file is read by whoever runs the organization's log shipper. Which
  /// engine was repointed, and whether it is now explicit or auto-detected, is
  /// what an administrator needs; where it points is on the machine.
  void _recordEngineConfigChange(Map<String, Object?> payload) {
    ref
        .read(cruxAuditRecorderProvider)
        .record(
          LintCruxAuditKinds.engineConfigChanged,
          payload: payload,
        );
  }

  /// Toggles whether the automatic (launch / periodic / on-resume)
  /// update check may run. The manual "Check for Updates" action is
  /// unaffected. Read back by `crux_updates`' `autoUpdateCheckEnabledProvider`
  /// through the bootstrap override.
  void setAutoCheckForUpdates({required bool enabled}) {
    _autoCheckTouched = true;
    if (state.autoCheckForUpdates == enabled) return;
    state = state.copyWith(autoCheckForUpdates: enabled);
    unawaited(_persistAutoCheckForUpdates(enabled: enabled));
  }

  Future<void> _persistAutoCheckForUpdates({required bool enabled}) async {
    try {
      await ref.read(autoUpdateCheckSettingsServiceProvider).save(enabled);
    } on Object {
      // See [_restoreAutoCheckForUpdates]: no preferences backend. The
      // in-memory state already changed, so the toggle still works for the
      // running session.
    }
  }

  /// Toggles whether the persisted workspace document is rehydrated at
  /// launch.
  ///
  /// The gate itself lives in `LintcruxWorkspaceNotifier.shouldRestoreOnLaunch`
  /// and reads the persisted value through
  /// `restoreTabsSettingsServiceProvider` at launch, *before* the workspace
  /// document is loaded — so a change made here takes effect on the next
  /// launch, not the current one. Turning it off leaves the document on disk
  /// untouched: flipping it back on restores the session that was there.
  void setRestoreTabsOnLaunch({required bool enabled}) {
    _restoreTabsTouched = true;
    if (state.restoreTabsOnLaunch == enabled) return;
    state = state.copyWith(restoreTabsOnLaunch: enabled);
    unawaited(_persistRestoreTabsOnLaunch(enabled: enabled));
  }

  Future<void> _persistRestoreTabsOnLaunch({required bool enabled}) async {
    try {
      await ref.read(restoreTabsSettingsServiceProvider).save(enabled);
    } on Object {
      // See [_restoreAutoCheckForUpdates]: no preferences backend. The
      // in-memory state already changed, so the toggle still reads back
      // correctly for the running session.
    }
  }

  static bool _overridesEqual(
    Map<String, EngineBinaryOverride> a,
    Map<String, EngineBinaryOverride> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
