// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:lintcrux/domain/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Settings → CXP Cross-Probe preferences, persisted together.
///
/// The four fields are only ever read as a set (by the CXP server lifecycle
/// and the Settings section), so one codec keeps their keys in one place.
@immutable
class CxpSettings {
  /// Creates a [CxpSettings]; every field defaults to [AppSettings]'s own.
  const CxpSettings({
    this.serverEnabled = true,
    this.serverPort = AppSettings.defaultCxpServerPort,
    this.requestAttention = true,
    this.broadcastSelection = true,
  });

  /// Reads the CXP fields off [settings].
  CxpSettings.of(AppSettings settings)
    : serverEnabled = settings.cxpServerEnabled,
      serverPort = settings.cxpServerPort,
      requestAttention = settings.requestAttentionOnCrossProbe,
      broadcastSelection = settings.broadcastSelectionOnCrossProbe;

  /// Whether the CXP server runs.
  final bool serverEnabled;

  /// The CXP server's TCP port.
  final int serverPort;

  /// Whether an inbound cross-probe requests the OS's attention.
  final bool requestAttention;

  /// Whether selection is broadcast to peers as it changes.
  final bool broadcastSelection;

  /// [settings] with these CXP fields applied.
  AppSettings applyTo(AppSettings settings) => settings.copyWith(
    cxpServerEnabled: serverEnabled,
    cxpServerPort: serverPort,
    requestAttentionOnCrossProbe: requestAttention,
    broadcastSelectionOnCrossProbe: broadcastSelection,
  );

  @override
  bool operator ==(Object other) =>
      other is CxpSettings &&
      other.serverEnabled == serverEnabled &&
      other.serverPort == serverPort &&
      other.requestAttention == requestAttention &&
      other.broadcastSelection == broadcastSelection;

  @override
  int get hashCode => Object.hash(
    serverEnabled,
    serverPort,
    requestAttention,
    broadcastSelection,
  );

  @override
  String toString() =>
      'CxpSettings(serverEnabled: $serverEnabled, serverPort: $serverPort, '
      'requestAttention: $requestAttention, '
      'broadcastSelection: $broadcastSelection)';
}

/// `SharedPreferences` codec for [CxpSettings].
///
/// Each field is read on its own, so a missing or mistyped key falls back to
/// that field's default without discarding the others.
class CxpSettingsCodec implements SettingsCodec<CxpSettings> {
  /// Const constructor — the codec is stateless.
  const CxpSettingsCodec();

  /// Key for [CxpSettings.serverEnabled].
  static const String serverEnabledKey = 'settings.cxpServerEnabled';

  /// Key for [CxpSettings.serverPort].
  static const String serverPortKey = 'settings.cxpServerPort';

  /// Key for [CxpSettings.requestAttention].
  static const String requestAttentionKey =
      'settings.requestAttentionOnCrossProbe';

  /// Key for [CxpSettings.broadcastSelection].
  static const String broadcastSelectionKey =
      'settings.broadcastSelectionOnCrossProbe';

  @override
  Future<CxpSettings> load(SharedPreferences prefs) async {
    const defaults = CxpSettings();
    final port = _read<int>(prefs, serverPortKey);
    return CxpSettings(
      serverEnabled:
          _read<bool>(prefs, serverEnabledKey) ?? defaults.serverEnabled,
      serverPort: port != null && port > 0 && port <= 65535
          ? port
          : defaults.serverPort,
      requestAttention:
          _read<bool>(prefs, requestAttentionKey) ?? defaults.requestAttention,
      broadcastSelection:
          _read<bool>(prefs, broadcastSelectionKey) ??
          defaults.broadcastSelection,
    );
  }

  @override
  Future<void> save(SharedPreferences prefs, CxpSettings settings) async {
    await prefs.setBool(serverEnabledKey, settings.serverEnabled);
    await prefs.setInt(serverPortKey, settings.serverPort);
    await prefs.setBool(requestAttentionKey, settings.requestAttention);
    await prefs.setBool(broadcastSelectionKey, settings.broadcastSelection);
  }

  /// [prefs]' value under [key] when it is a [T], else null — a value of the
  /// wrong type reads as unset rather than throwing.
  static T? _read<T>(SharedPreferences prefs, String key) {
    final value = prefs.get(key);
    return value is T ? value : null;
  }
}
