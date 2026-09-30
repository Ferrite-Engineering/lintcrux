// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart' show writeJsonAtomic;
import 'package:lintcrux/core/telemetry/crux_telemetry_headless.dart';
import 'package:path/path.dart' as p;

/// LintCrux's persistence adapter for the two per-installation telemetry
/// values — the consent decision and the installation id.
///
/// ## Why this is a file and not `SharedPreferences`
///
/// WaveCrux stores both values in `SharedPreferences` under the suite-fixed
/// keys [kTelemetryConsentKey] and [kTelemetryInstallationIdKey]. LintCrux
/// keeps the same keys and the same class shape, but a different backing
/// store, for one product reason: **LintCrux has a headless surface.**
///
/// `lintcrux --ci` is a `dart build cli` binary with no `dart:ui`. It cannot
/// load a Flutter plugin, so it cannot read `SharedPreferences` — and the
/// rule that the headless runner transmits *only* on a stored affirmative
/// consent is worthless if the headless runner is structurally unable to read
/// the consent the user gave in the GUI. A mirror file written beside the
/// preference would be a second source of truth for a privacy decision, which
/// is exactly the kind of drift that ends with one surface transmitting after
/// the other was told not to. So there is one store, it is a plain JSON file,
/// and both surfaces read and write it through this class.
///
/// The path derivation mirrors `crux_cxp`'s `sharedCxpManifestDirectory()`:
/// environment-derived, no `path_provider`, resolvable identically from a
/// Flutter isolate and from a bare Dart process. Unlike the CXP directory the
/// leaf is **per product** — consent is answered once per product, not once per
/// suite — and the file is deliberately outside `AppSettings`, which is the
/// user's preference document and the thing they copy to a second machine.
/// Consent is a property of this installation, and the installation id is what
/// makes "distinct installations" countable; an id that arrived with a copied
/// settings file would make two machines look like one.
///
/// Every method **fails soft**. `crux_telemetry` never throws into a feature
/// flow, and this adapter sits underneath that promise: an unreadable store
/// reads as "never answered", which collects nothing, and an unwritable one
/// loses the decision rather than the frame.
class LintcruxTelemetryStorage extends TelemetryStorage {
  /// Creates the adapter.
  ///
  /// [filePathOverride] is the storage seam — tests point it at a temp file,
  /// and the headless tests point it at the same file the GUI half wrote,
  /// which is the whole point of the class. `null` resolves
  /// [lintcruxTelemetryStorePath].
  const LintcruxTelemetryStorage({this.filePathOverride});

  /// An explicit path, or `null` to resolve [lintcruxTelemetryStorePath].
  final String? filePathOverride;

  /// The absolute path of the backing document.
  String get filePath => filePathOverride ?? lintcruxTelemetryStorePath();

  @override
  Future<String?> read(String key) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      final value = decoded[key];
      return value is String ? value : null;
    } on Object catch (_) {
      // A store we cannot read is a store we do not have. `unset` collects
      // nothing, which is the safe direction in both surfaces.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      final file = File(filePath);
      // Read-modify-write rather than a per-key file: the two values are
      // written seconds apart on a first launch (the id when the envelope is
      // first assembled, the consent when the disclosure is answered) and one
      // document keeps them from disagreeing about whether this installation
      // exists.
      final current = <String, Object?>{};
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) current.addAll(decoded);
      }
      current[key] = value;
      // Atomic because the GUI and a concurrently running `lintcrux --ci` can
      // both hold this path: a torn write would present as "consent lost",
      // which re-prompts a user who already answered. `writeJsonAtomic`
      // creates the parent directory itself.
      await writeJsonAtomic(file, current);
    } on Object catch (_) {
      // Losing a preference write is not worth surfacing anything to anyone.
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return;
      final current = <String, Object?>{...decoded}..remove(key);
      // Read-modify-write and atomic for the same reasons as [write]: the
      // installation id shares this document and must survive a consent
      // reset, and `lintcrux --ci` can be reading the file while this runs.
      await writeJsonAtomic(file, current);
    } on Object catch (_) {
      // A store we cannot rewrite keeps the value it had. The reset is a
      // testing affordance; it does not get to throw either.
    }
  }
}

/// The absolute path of LintCrux's telemetry store.
///
/// - **macOS**: `$HOME/Library/Application Support/crux/telemetry/lintcrux.json`
/// - **Windows**: `%APPDATA%\crux\telemetry\lintcrux.json`
/// - **Linux / other POSIX**:
///   `${XDG_DATA_HOME:-$HOME/.local/share}/crux/telemetry/lintcrux.json`
///
/// Derived from the environment rather than from `path_provider` for the
/// reason spelled out on [LintcruxTelemetryStorage]: the headless binary must
/// resolve the same path the desktop app did, and `path_provider` is a plugin
/// it cannot load. The `crux/` parent is the suite-shared application-data root
/// `crux_cxp` already established; the `lintcrux.json` leaf is what keeps
/// consent a per-product answer.
///
/// [environment] and [operatingSystem] are injectable for tests. Throws
/// [StateError] when the required home/appdata variable is missing — callers
/// treat that as "no store", never as consent.
String lintcruxTelemetryStorePath({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;

  String requireEnv(String name) {
    final value = env[name];
    if (value == null || value.isEmpty) {
      throw StateError(
        'lintcruxTelemetryStorePath: \$$name is not set; cannot resolve the '
        'telemetry store directory',
      );
    }
    return value;
  }

  // Join in the style of the OS being ASKED ABOUT, not the one we happen to be
  // running on. `p.join` uses the host separator, so on a Windows host a query
  // for the macOS path came back with backslashes — which is how this first
  // showed up, as a Windows CI failure in tests that pass `operatingSystem:`
  // explicitly. In production the two always agree and nothing changes; the
  // distinction only matters when they differ, and when they differ the
  // caller's parameter is the one telling the truth.
  final ctx = os == 'windows' ? p.windows : p.posix;

  final String base;
  switch (os) {
    case 'macos':
      base = ctx.join(requireEnv('HOME'), 'Library', 'Application Support');
    case 'windows':
      base = requireEnv('APPDATA');
    default:
      final xdg = env['XDG_DATA_HOME'];
      base = (xdg != null && xdg.isNotEmpty)
          ? xdg
          : ctx.join(requireEnv('HOME'), '.local', 'share');
  }
  return ctx.join(base, 'crux', 'telemetry', 'lintcrux.json');
}
