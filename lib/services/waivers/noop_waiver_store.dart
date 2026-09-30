// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:lintcrux/domain/interfaces/waiver_store.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';

/// Open-core default [WaiverStore] — a permanent empty store.
///
/// The managed waiver system is a Pro feature.
/// Open-core ships this no-op so:
///
///   * Open-core code can read [waiverStoreProvider] unconditionally.
///   * `ManagedWaiverTransformer` is a safe no-op when no Pro store is
///     installed — every `match()` call returns `null`, so violations
///     pass through unchanged.
///   * The Pro overlay's `JsonFileWaiverStore` slots in via the standard
///     provider-override pattern with no consumer-side changes.
///
/// Mutation methods throw [UnsupportedError]. Open-core UI never wires
/// "Waive…" affordances (those are Pro), so the throws should only fire
/// from misuse — e.g. a Pro feature accidentally compiled against the
/// open-core build.
class NoopWaiverStore implements WaiverStore {
  /// Creates the empty store.
  NoopWaiverStore();

  final StreamController<WaiverStoreEvent> _events =
      StreamController<WaiverStoreEvent>.broadcast();

  @override
  List<Waiver> get all => const <Waiver>[];

  @override
  Waiver? match(Violation v) => null;

  @override
  Future<void> add(Waiver w) {
    throw UnsupportedError(
      'NoopWaiverStore.add is unsupported. The managed waiver system is a '
      'Pro feature; install the Pro overlay to enable persistent waivers.',
    );
  }

  @override
  Future<void> update(Waiver w) {
    throw UnsupportedError(
      'NoopWaiverStore.update is unsupported. The managed waiver system is '
      'a Pro feature; install the Pro overlay to enable persistent waivers.',
    );
  }

  @override
  Future<void> delete(String id) {
    throw UnsupportedError(
      'NoopWaiverStore.delete is unsupported. The managed waiver system is '
      'a Pro feature; install the Pro overlay to enable persistent waivers.',
    );
  }

  @override
  Future<void> loadFrom(List<String> paths) async {
    // Loading is a no-op — the store is permanently empty. Emit a
    // reload event so consumers wired to events get a consistent
    // signal whether or not a Pro store is installed.
    _events.add(const WaiversReloaded(0));
  }

  @override
  Future<void> save() async {
    // Nothing to persist.
  }

  @override
  Stream<WaiverStoreEvent> get events => _events.stream;

  /// Closes the event stream. Call from `ref.onDispose` when the
  /// owning ProviderContainer is torn down.
  Future<void> dispose() => _events.close();
}
