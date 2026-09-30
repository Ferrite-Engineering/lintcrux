// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted store of the most recently observed authoritative server time —
/// the `server_time` field of the update manifest fetched by `crux_updates`.
///
/// Wired into `crux_license`'s `observedServerTimeProvider` from `bootstrap()`
/// so the beta-expiry clock is reckoned against
/// `trustedBetaExpiryNow(DateTime.now(), observedServerTime: …)` rather than
/// the device clock alone.
///
/// Two properties make that hardening work:
///
/// * **Monotonic.** [record] only ever advances the value (it keeps the later
///   of the stored and the newly observed instant), so a stale cached manifest
///   or a server blip can never roll the trusted clock backward.
/// * **Persisted.** The value round-trips through `SharedPreferences`, so a
///   later *offline* launch still benefits from the last server time the app
///   ever saw — which is exactly the case a user rolling the device clock back
///   would otherwise exploit.
///
/// [build] returns `null` synchronously and kicks off the asynchronous load;
/// once the persisted value arrives the state updates and every watcher (the
/// beta-expiry providers, through the root override) re-evaluates.
///
/// `crux_updates` deliberately does not own this: the package emits the
/// observation through `observedServerTimeSinkProvider` and leaves persistence
/// to the host, which already has a preferences layer.
class ObservedServerTimeStore extends Notifier<DateTime?> {
  /// `SharedPreferences` key holding the ISO-8601 server time.
  static const String prefsKey = 'update.observedServerTime';

  @override
  DateTime? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Object {
      // No preferences backend (a pure-Dart unit-test host with no Flutter
      // binding). The watermark stays null, which is exactly the fresh-install
      // behaviour: beta expiry falls back to the device clock.
      return;
    }
    final iso = prefs.getString(prefsKey);
    final parsed = iso == null ? null : DateTime.tryParse(iso);
    if (parsed != null) _advanceTo(parsed);
  }

  /// Records an observed [serverTime], advancing (and persisting) the stored
  /// value only when it is strictly later than the current one.
  Future<void> record(DateTime serverTime) async {
    if (!_advanceTo(serverTime)) return;
    // Capture the just-advanced value synchronously — while the notifier is
    // provably still mounted — so the persist path never reads `state` across
    // the `getInstance()` gap. A container teardown mid-fetch disposes the
    // notifier even though it is keep-alive.
    final toPersist = state!;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, toPersist.toIso8601String());
    } on Object {
      // See [_load]. The in-memory watermark still advanced, so this session
      // is hardened; only the cross-launch guarantee is lost.
    }
  }

  /// Sets [state] to [candidate] when it is strictly later than the current
  /// value (or when nothing has been observed yet). Returns whether the state
  /// advanced.
  ///
  /// Both callers reach here after an asynchronous gap ([_load] after the
  /// preferences read, [record] from the post-fetch sink callback), so a
  /// disposed notifier must not touch `state` — bail first.
  bool _advanceTo(DateTime candidate) {
    if (!ref.mounted) return false;
    final current = state;
    if (current != null && !candidate.isAfter(current)) return false;
    state = candidate;
    return true;
  }
}

/// The persisted, monotonic observed-server-time store.
///
/// Keep-alive by construction (a plain top-level [NotifierProvider] is not
/// auto-disposing), which matters because `updateCheckServiceProvider`
/// captures this notifier at construction and calls [ObservedServerTimeStore.record]
/// after the network fetch resolves.
final NotifierProvider<ObservedServerTimeStore, DateTime?>
observedServerTimeStoreProvider =
    NotifierProvider<ObservedServerTimeStore, DateTime?>(
      ObservedServerTimeStore.new,
      name: 'observedServerTimeStoreProvider',
    );
