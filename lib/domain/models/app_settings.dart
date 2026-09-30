// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/panel_layout_state.dart';
import 'package:meta/meta.dart';

/// Persistent application preferences for LintCrux.
///
/// Immutable value object — update via [copyWith]. Serialized to / from
/// its persisted JSON form via the shared `crux_settings` persistence
/// layer.
///
/// Composes a [CoreSettings] (cross-suite shared subset — see
/// `package:crux_settings`) plus LintCrux-specific fields. Consumers
/// can read either via the flat forwarder getters (`settings.themeMode`)
/// or via the explicit `settings.core.themeMode` traversal. Both work;
/// flat is preferred for brevity.
///
/// Mirrors the has-a composition pattern documented in
/// `wavecrux/lib/domain/models/app_settings.dart` — same structure, only
/// the product-specific fields differ.
@immutable
class AppSettings {
  /// Creates an [AppSettings]. Every parameter has a documented default
  /// so `const AppSettings()` returns the LintCrux baseline. To override
  /// [CoreSettings] fields (theme mode, locale, …), either pass an
  /// explicit [core] sub-object or use
  /// `const AppSettings().copyWith(themeMode: ..., locale: ...)`. The
  /// LintCrux-specific fields are direct constructor parameters because
  /// they don't have a cross-suite home.
  const AppSettings({
    this.core = const CoreSettings.defaults(),
    this.recentProjects = const <String>[],
    this.panelLayout = const PanelLayoutState(),
    this.engineBinaryOverrides = const <String, EngineBinaryOverride>{},
    this.cxpServerEnabled = true,
    this.cxpServerPort = defaultCxpServerPort,
    this.requestAttentionOnCrossProbe = true,
    this.broadcastSelectionOnCrossProbe = true,
    this.autoCheckForUpdates = true,
  });

  /// Default port the LintCrux CXP server binds to.
  ///
  /// Picked from the suite-wide CXP port assignment: WaveCrux
  /// uses 54322, NetCrux 54323, LintCrux 54324, SimCrux 54325.
  /// Users can override via [cxpServerPort] in Settings → Remote
  /// Control.
  static const int defaultCxpServerPort = 54324;

  /// The cross-suite shared subset of settings (theme, locale,
  /// diagnostics flag, plugin directories, theme overrides, …). Stored
  /// as a sub-object so LintCrux and the rest of the suite can share the
  /// model.
  final CoreSettings core;

  // ─── LintCrux-specific fields ────────────────────────────────────────

  /// Absolute paths of the most recently opened `.lintcrux` project
  /// files. Most-recent first. Capped at [maxRecentProjects] entries.
  /// Surfaced on the Welcome screen and (later) the empty-canvas state.
  final List<String> recentProjects;

  /// Maximum number of entries retained in [recentProjects].
  static const int maxRecentProjects = 10;

  /// Persistent visibility and size state for the viewer's four panes
  /// (rule browser, violations, violation details, run log). Driven by
  /// `panelLayoutNotifierProvider` at runtime and rehydrated on launch
  /// from the persisted `crux_settings` snapshot.
  final PanelLayoutState panelLayout;

  /// Per-engine binary-path overrides, keyed by
  /// [LintEngine.id] (`'verilator'`, `'verible'`, `'slang'`, `'ghdl'`,
  /// `'svlint'`, `'yosys'`). Missing keys default to
  /// [EngineBinaryOverride.autoDetect]. Set in Settings → Engines and
  /// consumed by the run-orchestration layer to build the
  /// `LintRunRequest.binary` for every engine invocation.
  final Map<String, EngineBinaryOverride> engineBinaryOverrides;

  /// Convenience: returns the override for [engineId], defaulting to
  /// [EngineBinaryOverride.autoDetect] when no override is stored.
  EngineBinaryOverride engineBinaryOverrideFor(String engineId) =>
      engineBinaryOverrides[engineId] ?? EngineBinaryOverride.autoDetect;

  /// Whether the CXP cross-probe server is started at boot.
  /// Defaults to `true` so first-launch users see cross-probe working
  /// without any configuration. Toggled in Settings → Remote Control.
  final bool cxpServerEnabled;

  /// TCP port the CXP server binds to on `127.0.0.1`. Defaults
  /// to [defaultCxpServerPort] (`54324`). Configurable in Settings →
  /// Remote Control so engineers running multiple LintCrux instances
  /// (or with a port conflict) can pick a different port.
  final int cxpServerPort;

  /// Whether an actionable inbound cross-probe (a highlight applied, a design
  /// artifact opened) requests the OS's attention (dock bounce / taskbar flash
  /// / Wayland urgency) without stealing focus. Defaults to `true`. Toggled in
  /// Settings → Remote Control. Gates the swappable `windowAttentionRequester`
  /// seam in `crux_window_chrome` via the CXP attention-gate provider.
  final bool requestAttentionOnCrossProbe;

  /// CXP Cross-Probe — whether the live selection auto-broadcast is active.
  /// When `true` (the default), selecting a violation announces it to
  /// connected peers via the Pro-tier `ViolationSelectionEmitter`
  /// (`notify_selection`), driving live cross-probe. When `false`, the
  /// automatic emitter is gated off and only explicit sends (the
  /// "Cross-probe to peer →" menu) reach peers. Toggled in Settings →
  /// Remote Control. Session-scoped in open-core (no preferences backend),
  /// matching the other CXP server fields.
  final bool broadcastSelectionOnCrossProbe;

  /// Whether the *automatic* update check (launch, periodic and
  /// on-resume) may run. Defaults to `true`.
  ///
  /// Read by `crux_updates`' `autoUpdateCheckEnabledProvider`, which the
  /// bootstrap overrides from this field. The manual "Check for Updates"
  /// action ignores it — a manual check always runs. Toggled in
  /// Settings → General.
  final bool autoCheckForUpdates;

  // ─── Forwarder getters into [core] ───────────────────────────────────
  // Preserve the flat API so call sites can write `settings.themeMode`
  // instead of `settings.core.themeMode`.

  /// Forwarder for [CoreSettings.themeMode].
  AppThemeMode get themeMode => core.themeMode;

  /// Forwarder for [CoreSettings.autoReloadMode].
  AutoReloadMode get autoReloadMode => core.autoReloadMode;

  /// Forwarder for [CoreSettings.autoSaveIntervalSeconds].
  int get autoSaveIntervalSeconds => core.autoSaveIntervalSeconds;

  /// Forwarder for [CoreSettings.locale].
  String get locale => core.locale;

  /// Forwarder for [CoreSettings.diagnosticsEnabled].
  bool get diagnosticsEnabled => core.diagnosticsEnabled;

  /// Forwarder for [CoreSettings.orientationLockMode].
  OrientationLockMode get orientationLockMode => core.orientationLockMode;

  /// Forwarder for [CoreSettings.autoHideChromeSeconds].
  int get autoHideChromeSeconds => core.autoHideChromeSeconds;

  /// Forwarder for [CoreSettings.userPluginDirectories].
  List<String> get userPluginDirectories => core.userPluginDirectories;

  /// Forwarder for [CoreSettings.pluginSafetyAcknowledged].
  bool get pluginSafetyAcknowledged => core.pluginSafetyAcknowledged;

  /// Forwarder for [CoreSettings.pluginLoadingDisabled].
  bool get pluginLoadingDisabled => core.pluginLoadingDisabled;

  /// Forwarder for [CoreSettings.perPluginDisabled].
  Map<String, bool> get perPluginDisabled => core.perPluginDisabled;

  /// Forwarder for [CoreSettings.activeThemeName].
  String get activeThemeName => core.activeThemeName;

  /// Forwarder for [CoreSettings.themeOverrides].
  Map<String, String> get themeOverrides => core.themeOverrides;

  /// Forwarder for [CoreSettings.restoreTabsOnLaunch].
  bool get restoreTabsOnLaunch => core.restoreTabsOnLaunch;

  /// Returns a copy with overridden fields.
  ///
  /// Accepts both the LintCrux-specific fields and the flat
  /// [CoreSettings] forwarders, so call sites can write
  /// `settings.copyWith(themeMode: AppThemeMode.light)` unchanged. Pass
  /// [core] directly to swap the entire sub-object at once.
  AppSettings copyWith({
    CoreSettings? core,
    // Flat core forwarders:
    AppThemeMode? themeMode,
    AutoReloadMode? autoReloadMode,
    int? autoSaveIntervalSeconds,
    String? locale,
    bool? diagnosticsEnabled,
    OrientationLockMode? orientationLockMode,
    int? autoHideChromeSeconds,
    List<String>? userPluginDirectories,
    bool? pluginSafetyAcknowledged,
    bool? pluginLoadingDisabled,
    Map<String, bool>? perPluginDisabled,
    String? activeThemeName,
    Map<String, String>? themeOverrides,
    bool? restoreTabsOnLaunch,
    // LintCrux-specific:
    List<String>? recentProjects,
    PanelLayoutState? panelLayout,
    Map<String, EngineBinaryOverride>? engineBinaryOverrides,
    bool? cxpServerEnabled,
    int? cxpServerPort,
    bool? requestAttentionOnCrossProbe,
    bool? broadcastSelectionOnCrossProbe,
    bool? autoCheckForUpdates,
  }) {
    final newCore =
        core ??
        this.core.copyWith(
          themeMode: themeMode,
          autoReloadMode: autoReloadMode,
          autoSaveIntervalSeconds: autoSaveIntervalSeconds,
          locale: locale,
          diagnosticsEnabled: diagnosticsEnabled,
          orientationLockMode: orientationLockMode,
          autoHideChromeSeconds: autoHideChromeSeconds,
          userPluginDirectories: userPluginDirectories,
          pluginSafetyAcknowledged: pluginSafetyAcknowledged,
          pluginLoadingDisabled: pluginLoadingDisabled,
          perPluginDisabled: perPluginDisabled,
          activeThemeName: activeThemeName,
          themeOverrides: themeOverrides,
          restoreTabsOnLaunch: restoreTabsOnLaunch,
        );
    return AppSettings(
      core: newCore,
      recentProjects: recentProjects ?? this.recentProjects,
      panelLayout: panelLayout ?? this.panelLayout,
      engineBinaryOverrides:
          engineBinaryOverrides ?? this.engineBinaryOverrides,
      cxpServerEnabled: cxpServerEnabled ?? this.cxpServerEnabled,
      cxpServerPort: cxpServerPort ?? this.cxpServerPort,
      requestAttentionOnCrossProbe:
          requestAttentionOnCrossProbe ?? this.requestAttentionOnCrossProbe,
      broadcastSelectionOnCrossProbe:
          broadcastSelectionOnCrossProbe ?? this.broadcastSelectionOnCrossProbe,
      autoCheckForUpdates: autoCheckForUpdates ?? this.autoCheckForUpdates,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppSettings) return false;
    if (other.core != core) return false;
    if (other.panelLayout != panelLayout) return false;
    if (other.recentProjects.length != recentProjects.length) return false;
    for (var i = 0; i < recentProjects.length; i++) {
      if (other.recentProjects[i] != recentProjects[i]) return false;
    }
    if (other.engineBinaryOverrides.length != engineBinaryOverrides.length) {
      return false;
    }
    for (final entry in engineBinaryOverrides.entries) {
      if (other.engineBinaryOverrides[entry.key] != entry.value) return false;
    }
    if (other.cxpServerEnabled != cxpServerEnabled) return false;
    if (other.cxpServerPort != cxpServerPort) return false;
    if (other.requestAttentionOnCrossProbe != requestAttentionOnCrossProbe) {
      return false;
    }
    if (other.broadcastSelectionOnCrossProbe !=
        broadcastSelectionOnCrossProbe) {
      return false;
    }
    if (other.autoCheckForUpdates != autoCheckForUpdates) return false;
    return true;
  }

  @override
  int get hashCode {
    final overrideKeys = engineBinaryOverrides.keys.toList()..sort();
    final overrideHash = Object.hashAll(
      overrideKeys.expand((k) => [k, engineBinaryOverrides[k]]),
    );
    return Object.hash(
      core,
      Object.hashAll(recentProjects),
      panelLayout,
      overrideHash,
      cxpServerEnabled,
      cxpServerPort,
      requestAttentionOnCrossProbe,
      broadcastSelectionOnCrossProbe,
      autoCheckForUpdates,
    );
  }

  @override
  String toString() =>
      'AppSettings('
      'themeMode: $themeMode, '
      'locale: $locale, '
      'diagnosticsEnabled: $diagnosticsEnabled, '
      'activeThemeName: $activeThemeName, '
      'recentProjects: $recentProjects, '
      'panelLayout: $panelLayout, '
      'cxpServerEnabled: $cxpServerEnabled, '
      'cxpServerPort: $cxpServerPort, '
      'requestAttentionOnCrossProbe: $requestAttentionOnCrossProbe, '
      'broadcastSelectionOnCrossProbe: $broadcastSelectionOnCrossProbe, '
      'autoCheckForUpdates: $autoCheckForUpdates'
      ')';
}
