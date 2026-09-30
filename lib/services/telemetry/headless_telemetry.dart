// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:lintcrux/core/telemetry/crux_telemetry_headless.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_storage.dart';
import 'package:lintcrux/domain/models/engine_run_outcome.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';

/// The headless-consent rule, implemented.
///
/// > `lintcrux --ci` and other headless invocations send nothing unless the
/// > GUI app on the same machine has stored an affirmative consent state; a
/// > machine that has never shown the first-launch dialog never transmits.
///
/// Three states, and the middle one is the point:
///
/// * **`enabled`** — the user answered yes in the desktop app's disclosure (or
///   in Settings → Privacy). The run's counters are sent.
/// * **`disabled`** — the user answered no. Nothing is sent.
/// * **`unset`** — the disclosure has never been shown on this machine.
///   Nothing is sent, **and nothing is asked**. A CI job must never block on a
///   dialog, and silence must never be read as a yes; `unset` is the state a
///   container that has never run the GUI is permanently in, so treating it as
///   consent would mean every CI fleet in the world opted in by accident.
///
/// ## Why this is not `LiveTelemetryService`
///
/// It would be, if it could be. `crux_telemetry`'s live service reaches
/// `TelemetryEventQueue`, which imports `path_provider`; the barrel also pulls
/// `flutter_riverpod` and `flutter/foundation`. All three are Flutter, and the
/// `lintcrux` binary that `dart build cli` produces has no `dart:ui`, so
/// importing any of them fails the CLI build outright. What this class *does*
/// reuse is every part of the payload that could otherwise drift: the
/// [TelemetryEvent] and [TelemetryEnvelope] models, `coalesceTelemetryEvents`,
/// `buildTelemetryBatches`, and the endpoint constants — all re-exported by
/// `core/telemetry/crux_telemetry_headless.dart`. The serializer is the shared
/// one; only the driving loop is local.
///
/// ## The flush decision
///
/// **This class sends before the process exits, under a hard budget, and drops
/// what it cannot deliver. It writes no queue.**
///
/// The alternative — record into a disk queue and let the next GUI launch post
/// it, which is what the desktop app does — was rejected for a specific
/// reason. On a CI runner there is no next GUI launch. The container is torn
/// down after the job, so the queue would be written and never read; on a
/// long-lived runner it would be written, capped at 2000 events / 7 days, and
/// *still* never read. Either way `trigger: cli` — the whole reason the
/// headless path is instrumented, since "manual vs auto-reload vs CI usage
/// mix" is the roadmap question — would be permanently empty while the file
/// grew. A queue nobody drains is not a queue, it is disk usage.
///
/// So the send is synchronous with the run, and the two costs that buys are
/// paid down explicitly:
///
/// * **CI wall time.** One POST, [postTimeout] of 5 s, and a [flushBudget] of
///   5 s over the whole attempt. A lint job must not get measurably slower
///   because it reports a counter.
/// * **Delivery.** There is no retry and no backoff, because there is no
///   second chance to retry into. A run whose POST times out loses its
///   counters. That is the documented failure mode of this entire pipeline —
///   losing a counter is always better than costing the user something — and
///   it is *why* the desktop app, which does have a next launch, keeps a queue
///   and this does not.
///
/// Nothing here throws: every method is wrapped, exactly as
/// `LiveTelemetryService` is, for the same reason. A CI gate that failed
/// because telemetry could not reach the network would be an outage of the
/// user's build system caused by our analytics.
class HeadlessTelemetry {
  /// Creates a reporter.
  ///
  /// [consent] and [installationId] come from [resolve], which reads the same
  /// store the desktop app writes. [client] and [now] are the test seams.
  HeadlessTelemetry({
    required this.consent,
    required this.installationId,
    required this.appVersion,
    required this.endpoint,
    this.licenseTier = 'openCore',
    this.clientOverride,
    DateTime Function()? now,
    this.postTimeout = kHeadlessTelemetryPostTimeout,
    this.flushBudget = kHeadlessTelemetryFlushBudget,
  }) : sessionStart = (now ?? DateTime.now)();

  /// Resolves the reporter for this invocation from the on-disk consent store.
  ///
  /// Returns a reporter whose [transmits] is `false` — recording nothing,
  /// sending nothing, touching no network — unless the stored consent is
  /// exactly [TelemetryConsentState.enabled]. It never writes to the store, so
  /// a headless run cannot mint an installation id for a machine that has
  /// never consented: the id is a per-installation identifier, and creating
  /// one for an installation that declined (or was never asked) is precisely
  /// the thing the tri-state exists to prevent.
  ///
  /// Under `--dart-define=TELEMETRY_DEV=true` the endpoint becomes the staging
  /// dataset, exactly as it does in the GUI. The dev flag deliberately does
  /// **not** relax the consent rule here: in the GUI, `unset` counts as
  /// enabled under the dev flag so end-to-end staging verification needs no
  /// UI, but a headless process has no UI to skip and the rule it would be
  /// skipping is the headless-consent rule itself. A dev build still needs a stored
  /// `enabled`.
  static Future<HeadlessTelemetry> resolve({
    required String appVersion,
    TelemetryStorage storage = const LintcruxTelemetryStorage(),
    String licenseTier = 'openCore',
    bool dev = kTelemetryDev,
    http.Client? client,
    DateTime Function()? now,
  }) async {
    var consent = TelemetryConsentState.unset;
    String? installationId;
    try {
      consent =
          TelemetryConsentState.tryParse(
            await storage.read(kTelemetryConsentKey),
          ) ??
          TelemetryConsentState.unset;
      if (consent == TelemetryConsentState.enabled) {
        installationId = await storage.read(kTelemetryInstallationIdKey);
      }
    } on Object catch (_) {
      // A store we cannot read is a store that has not consented.
      consent = TelemetryConsentState.unset;
      installationId = null;
    }
    return HeadlessTelemetry(
      consent: consent,
      installationId: installationId,
      appVersion: appVersion,
      endpoint: telemetryEndpointFor(dev: dev),
      licenseTier: licenseTier,
      clientOverride: client,
      now: now,
    );
  }

  /// The consent this machine stored, as read at [resolve] time.
  final TelemetryConsentState consent;

  /// The installation id the desktop app minted, or `null` when the store held
  /// none. A `null` id makes [transmits] false: the envelope's
  /// `installation_id` is not optional and inventing one here would create an
  /// identity the user never agreed to.
  final String? installationId;

  /// The running build's version — the `app_version` envelope field.
  final String appVersion;

  /// The ingest URL. Production, or the staging dataset under `TELEMETRY_DEV`.
  final Uri endpoint;

  /// The `license_tier` envelope field. Open core reports `openCore`; the Pro
  /// overlay's CLI passes its own resolved tier.
  final String licenseTier;

  /// Per-POST timeout.
  final Duration postTimeout;

  /// Ceiling on the whole [flush] attempt.
  final Duration flushBudget;

  /// When this headless invocation started — the `session_start` envelope
  /// field. Nothing records when it *ends*: session duration is on the
  /// never-collect list, so it is not merely unsent, it is never computed.
  final DateTime sessionStart;

  /// A caller-owned HTTP client, or `null` to build (and close) one per flush.
  /// The tests' `MockClient` seam.
  final http.Client? clientOverride;

  final List<TelemetryEvent> _events = <TelemetryEvent>[];

  /// Whether this invocation may transmit at all.
  ///
  /// The single predicate every other method consults. `false` for `unset`,
  /// `false` for `disabled`, and `false` when no installation id was stored.
  bool get transmits =>
      consent == TelemetryConsentState.enabled && installationId != null;

  /// Events recorded so far. Always empty when [transmits] is false — a
  /// non-consenting run does not merely fail to *send* the counters, it never
  /// builds them.
  List<TelemetryEvent> get pending =>
      List<TelemetryEvent>.unmodifiable(_events);

  /// Records `run.completed` for this headless invocation.
  void recordRunCompleted({required int engines}) {
    _record(
      'run.completed',
      <String, Object?>{
        'trigger': telemetryEnumToken(LintRunTrigger.cli),
        'engines': engines,
      },
    );
  }

  /// Records one `engine.run`, from the same [EngineRunOutcome] the desktop
  /// app reports, so a CI run and a workstation run are the same measurement.
  void recordEngineOutcome(String engineId, EngineRunOutcome outcome) {
    _record('engine.run', <String, Object?>{
      'engine': telemetryEngineToken(engineId),
      'status': telemetryEnumToken(outcome),
    });
  }

  void _record(String name, Map<String, Object?> properties) {
    if (!transmits) return;
    try {
      _events.add(TelemetryEvent(name, properties: properties));
    } on Object catch (_) {
      // Never throws into the run — see the class doc.
    }
  }

  /// Sends everything recorded, then returns. Never throws.
  ///
  /// Resolves when the attempt is over — successfully or not. A caller that
  /// wants the process to exit promptly gets that for free: the whole call is
  /// bounded by [flushBudget].
  Future<void> flush() async {
    if (!transmits || _events.isEmpty) return;
    final client = clientOverride ?? http.Client();
    try {
      await _post(client).timeout(flushBudget);
    } on Object catch (_) {
      // Dropped. There is no next launch to hand this to — see the class doc.
    } finally {
      _events.clear();
      // Only close a client we own; an injected one belongs to the caller.
      if (clientOverride == null) client.close();
    }
  }

  Future<void> _post(http.Client client) async {
    final envelope = TelemetryEnvelope(
      installationId: installationId!,
      appVersion: appVersion,
      product: 'lintcrux',
      // `crux_telemetry`'s own derivation reads `defaultTargetPlatform` from
      // `flutter/foundation`, which this binary cannot link.
      os: headlessTelemetryOsSlug(),
      // A headless run is a desktop-class host by construction: there is no
      // browser, and LintCrux has no phone or tablet target.
      formFactor: 'desktop',
      // No display language exists in a headless process. `en` matches the
      // package's own seam default rather than guessing from `LANG`, which
      // reports the machine's locale and not the app's.
      locale: 'en',
      licenseTier: licenseTier,
      sessionStart: sessionStart,
      userAgentName: 'LintCrux',
    );

    for (final batch in buildTelemetryBatches(
      envelope,
      coalesceTelemetryEvents(_events),
    )) {
      final response = await client
          .post(
            endpoint,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'User-Agent': envelope.userAgent,
            },
            body: batch.body,
          )
          .timeout(postTimeout);
      // A rejection is not retried and not reported: there is nowhere to
      // report it to, and the next CI run will send a fresh batch anyway.
      if (response.statusCode < 200 || response.statusCode >= 300) return;
    }
  }
}

/// Per-POST timeout for a headless flush.
///
/// Much shorter than the GUI's 15 s: a desktop app posting in the background
/// can afford to wait, and a CI job cannot. Five seconds is long enough for a
/// healthy edge and short enough that an unreachable one is invisible in a job
/// that already spent a minute running lint engines.
const Duration kHeadlessTelemetryPostTimeout = Duration(seconds: 5);

/// Ceiling on the whole headless flush, including every batch.
///
/// The hard answer to "how much can telemetry lengthen a CI job". A headless
/// run produces at most one `run.completed` and one `engine.run` per engine —
/// well inside a single batch — so this only ever bites when the network does.
const Duration kHeadlessTelemetryFlushBudget = Duration(seconds: 5);

/// The `os` slug for a headless invocation, derived without Flutter.
///
/// `crux_telemetry`'s `telemetryOsSlug()` reads `defaultTargetPlatform` from
/// `flutter/foundation`, which the CLI binary cannot link.
/// `Platform.operatingSystem` already returns exactly the Worker's slugs for
/// every platform LintCrux runs headless on; anything else (`fuchsia`, or a
/// future value) falls back to `linux`, matching how the shared derivation
/// treats it. A value outside the Worker's set rejects the **whole** batch with
/// a 400 the client never sees, so the fallback is a constant rather than a
/// pass-through of whatever the platform said.
///
/// The set is spelled out here rather than imported because
/// `kTelemetryOperatingSystems` lives in the same Flutter-importing library as
/// the derivation; `headless_telemetry_test.dart` asserts the two agree.
String headlessTelemetryOsSlug({String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  return const <String>{
        'macos',
        'windows',
        'linux',
        'ios',
        'android',
      }.contains(os)
      ? os
      : 'linux';
}
