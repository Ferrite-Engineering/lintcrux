// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The browser's persistence adapter for the two per-installation telemetry
/// values — the consent decision and the installation id.
///
/// Same suite-fixed keys as every other product ([kTelemetryConsentKey],
/// [kTelemetryInstallationIdKey]) and the same fail-soft contract; the store
/// is `SharedPreferences`, which in a browser is `localStorage`.
///
/// **Why the desktop adapter cannot serve here.** `LintcruxTelemetryStorage`
/// keeps both values in a JSON file so the Flutter-free `lintcrux --ci`
/// binary reads the consent the desktop app wrote — a real requirement, and
/// the reason LintCrux deviates from WaveCrux's preference-backed store. In a
/// browser every one of its `dart:io` calls fails: each read answers "never
/// answered" and each write is dropped. The viewer would ask for usage
/// statistics on every visit, forget the answer, and mint a new installation
/// id each session, which also makes "distinct installations" uncountable.
/// There is no headless surface in a browser, so nothing there needs the
/// file, and `SharedPreferences` is what the other three products already
/// use.
///
/// Every method **fails soft**: `crux_telemetry` never throws into a feature
/// flow. An unreadable store reads as "never answered", which collects
/// nothing, and an unwritable one loses the decision rather than the frame.
class LintcruxWebTelemetryStorage extends TelemetryStorage {
  /// Creates the adapter. Stateless — `SharedPreferences.getInstance()` is
  /// itself cached by the plugin.
  const LintcruxWebTelemetryStorage();

  @override
  Future<String?> read(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } on Object catch (_) {
      // Losing a preference write is not worth surfacing anything to anyone.
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } on Object catch (_) {
      // Same posture as write: a delete that cannot complete leaves the value
      // in place, and the caller learns about it from the disclosure not
      // appearing rather than from an exception on a privacy path.
    }
  }
}
