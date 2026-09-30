// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_config.dart';

/// A process-lifetime [TelemetryStorage] the telemetry tests drive.
///
/// `crux_telemetry` ships `InMemoryTelemetryStorage`, which is the same thing;
/// this exists so a LintCrux test can seed a consent value in one line and
/// assert what was written without importing the package's internals twice.
class TelemetryTestStore extends TelemetryStorage {
  /// Creates a store, optionally pre-seeded with [seed] — the test equivalent
  /// of "an installation that already answered on a previous launch".
  TelemetryTestStore([Map<String, String>? seed])
    : values = <String, String>{...?seed};

  /// Convenience: a store whose consent is [TelemetryConsentState.enabled] and
  /// which already holds a well-formed installation id — the state a machine
  /// is in after the desktop app's disclosure was answered yes.
  factory TelemetryTestStore.consented({
    String installationId = '00000000-0000-4000-8000-000000000001',
  }) => TelemetryTestStore(<String, String>{
    kTelemetryConsentKey: TelemetryConsentState.enabled.name,
    kTelemetryInstallationIdKey: installationId,
  });

  /// Convenience: a store whose consent is [TelemetryConsentState.disabled],
  /// the state a machine is in after the disclosure was answered no.
  factory TelemetryTestStore.declined() => TelemetryTestStore(<String, String>{
    kTelemetryConsentKey: TelemetryConsentState.disabled.name,
  });

  /// The values currently held. Mutable so a test can assert on writes.
  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// A [TelemetryService] that keeps every event it is handed.
///
/// The per-event tests bind this through `telemetryServiceProvider` and then
/// drive the real code path, so what they assert is that the *feature* records
/// the event — not that a recording helper works.
class RecordingTelemetryService implements TelemetryService {
  /// Every event recorded so far, in order.
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  /// The events named [name].
  Iterable<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name);

  /// The single event named [name]. Fails loudly when there is not exactly
  /// one, because "fired twice" is as much a defect as "did not fire".
  TelemetryEvent only(String name) => named(name).single;

  @override
  void record(TelemetryEvent event) => events.add(event);
}

/// Telemetry pinned to an installation that already answered "no", for a
/// test that is not about telemetry.
///
/// Since the public beta ended, telemetry is live. The service needs the
/// product's [CruxTelemetryConfig] (the package deliberately has no default,
/// so a product that forgets it fails loudly), and an installation that has
/// not answered the disclosure gets it as a first-launch prompt over the
/// app, the same kind of blocker the EULA gate is. The production overrides
/// supply both; a test that mounts the app, or a container, without them
/// pins the one state that keeps telemetry out of its way: LintCrux's own
/// config, and a store that has already declined. Nothing is sent, nothing
/// is queued, and nothing is prompted.
///
/// A test that spreads `lintcruxTelemetryOverrides` already binds both
/// providers and must not add these (Riverpod rejects a second override of
/// one provider in a container).
List<Override> telemetryDeclinedOverrides() => <Override>[
  cruxTelemetryConfigProvider.overrideWithValue(lintcruxTelemetryConfig),
  telemetryStorageProvider.overrideWithValue(TelemetryTestStore.declined()),
];
