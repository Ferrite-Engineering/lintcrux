// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:file_selector/file_selector.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:meta/meta.dart';

/// Desktop "Import SARIF report" ingestion.
///
/// Wraps the existing [SarifFileLoader] with the malformed-safety
/// guarantee the desktop flow requires: a bad or truncated SARIF
/// must surface a typed [SarifLoadException] **and leave any previously
/// imported report intact** — never a partial replacement of the display
/// store.
///
/// It achieves that by streaming the picked file into a throw-away
/// scratch [InMemoryViolationStore] first. Only once the loader has
/// completed successfully are the parsed violations committed — wholesale
/// — into the caller's display store. If the loader throws mid-stream,
/// the scratch store absorbs whatever was partially parsed and is
/// discarded; the display store is never touched.
class SarifImportService {
  /// Creates a [SarifImportService] over [_loader].
  const SarifImportService(this._loader);

  final SarifFileLoader _loader;

  /// Imports [file] into [display], replacing its contents with the
  /// imported report's violations on success.
  ///
  /// Returns the parsed [SarifReport] (engine list / run metadata).
  /// Throws [SarifLoadException] on any read/parse failure, in which case
  /// [display] is guaranteed untouched.
  Future<SarifReport> importFromXFile(
    XFile file, {
    required ViolationStore display,
  }) async {
    final scratch = InMemoryViolationStore();
    try {
      // Parse into the scratch store; a malformed document throws here,
      // before a single violation reaches [display].
      final report = await _loader.loadFromXFile(file, store: scratch);
      commitInto(display, scratch);
      return report;
    } finally {
      await scratch.dispose();
    }
  }

  /// Wholesale-replaces every engine bucket in [display] with the buckets
  /// held by [source]. Engines present in [display] but absent from
  /// [source] are cleared, so [display] ends up an exact mirror of
  /// [source] rather than a union with stale prior engines.
  ///
  /// Exposed for the import service's own use and for tests that need to
  /// assert the commit semantics directly.
  @visibleForTesting
  static void commitInto(ViolationStore display, ViolationStore source) {
    final incoming = source.byEngine;
    // Clear engines that the incoming report no longer contains.
    for (final engineId in display.byEngine.keys.toList()) {
      if (!incoming.containsKey(engineId)) {
        display.replaceFromEngine(engineId, const <Violation>[]);
      }
    }
    // Replace / add each incoming engine's set.
    for (final entry in incoming.entries) {
      display.replaceFromEngine(entry.key, List<Violation>.of(entry.value));
    }
  }
}
