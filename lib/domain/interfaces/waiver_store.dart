// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';

/// Persistence + matching interface for [Waiver]s.
///
/// Open Core ships a no-op implementation that only honors source
/// pragmas (e.g. `// verilator lint_off RULE`). The Pro overlay
/// supplies `JsonFileWaiverStore` that reads/writes a
/// `.lintcrux-waivers.json` file with metadata, expiry, and audit
/// fields. The Enterprise overlay supplies a shared waiver
/// repository with approval workflow.
///
/// The interface is shaped so consumers (the violation table, the
/// inspector, the export pipeline) never need to know which tier's
/// implementation is active.
abstract class WaiverStore {
  /// All waivers currently loaded for the project. Unmodifiable.
  List<Waiver> get all;

  /// Match a violation against all loaded waivers; returns the
  /// matching waiver or `null`. Implementations must respect
  /// [Waiver.expiresAt] — expired waivers do not match.
  Waiver? match(Violation v);

  /// Persist a new waiver. Open Core's no-op implementation throws
  /// [UnsupportedError]; Pro implementations append to the JSON file
  /// and emit a [WaiverAdded] event.
  Future<void> add(Waiver w);

  /// Update an existing waiver (e.g. extend expiry, change reason).
  /// Identified by [Waiver.id].
  Future<void> update(Waiver w);

  /// Delete a waiver by [id]. Logged in the Enterprise audit trail.
  Future<void> delete(String id);

  /// Load waivers from one or more files. Implementations replace the
  /// current in-memory set with what they read; concurrent in-flight
  /// `add`/`update`/`delete` calls finish before the swap.
  Future<void> loadFrom(List<String> paths);

  /// Persist the current in-memory set back to its source file(s).
  /// No-op for stores that don't persist (e.g. the Open Core source-
  /// pragma-only implementation).
  Future<void> save();

  /// Stream of mutations.
  Stream<WaiverStoreEvent> get events;
}

/// Change notification for [WaiverStore.events].
sealed class WaiverStoreEvent {
  const WaiverStoreEvent();
}

/// A new waiver was added.
class WaiverAdded extends WaiverStoreEvent {
  /// Creates a [WaiverAdded] event.
  const WaiverAdded(this.waiver);

  /// The newly-added waiver.
  final Waiver waiver;
}

/// An existing waiver was updated.
class WaiverUpdated extends WaiverStoreEvent {
  /// Creates a [WaiverUpdated] event.
  const WaiverUpdated(this.waiver);

  /// The updated waiver (post-change).
  final Waiver waiver;
}

/// A waiver was deleted.
class WaiverDeleted extends WaiverStoreEvent {
  /// Creates a [WaiverDeleted] event.
  const WaiverDeleted(this.waiverId);

  /// ID of the waiver that was deleted.
  final String waiverId;
}

/// The in-memory waiver set was reloaded from disk.
class WaiversReloaded extends WaiverStoreEvent {
  /// Creates a [WaiversReloaded] event.
  const WaiversReloaded(this.count);

  /// Number of waivers after reload.
  final int count;
}
