// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/domain/models/baseline_violation.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';

/// Live mirror of the entire bookmark set indexed by fingerprint.
///
/// Watches [violationBookmarkStoreProvider] and re-emits the full
/// fingerprint → bookmark map on every successful mutation. The
/// bookmark column icon and the bookmark panel consume this provider
/// to perform O(1) bookmark-state lookup per row.
///
/// Picking a map over a per-violation family provider keeps the
/// virtualized violations table fast — each row reads the map and
/// looks up its own fingerprint in O(1), rather than registering N
/// individual provider subscriptions for N visible rows.
///
/// With no project open the store is the [NoopViolationBookmarkStore],
/// which returns an empty list and never emits on `changed`, so this
/// stream settles immediately on an empty map.
final StreamProvider<Map<String, BookmarkedViolation>>
violationBookmarkLookupMapProvider =
    StreamProvider<Map<String, BookmarkedViolation>>(
      buildViolationBookmarkLookupMap,
    );

/// Build body of [violationBookmarkLookupMapProvider]. Top-level so
/// `lintcruxTabOverridesFactory` can re-bind the provider per tab with the
/// identical body: the map must derive from the tab's own
/// `violationBookmarkStoreProvider` binding, not the root-scope no-op
/// store.
Stream<Map<String, BookmarkedViolation>> buildViolationBookmarkLookupMap(
  Ref ref,
) async* {
  final store = ref.watch(violationBookmarkStoreProvider);
  Future<Map<String, BookmarkedViolation>> snapshot() async {
    final all = await store.listAll();
    return <String, BookmarkedViolation>{
      for (final bm in all) bm.fingerprint: bm,
    };
  }

  yield await snapshot();
  await for (final _ in store.changed) {
    yield await snapshot();
  }
}

/// Computes the [BookmarkedViolation.fingerprint] for a given live
/// [Violation] in the project rooted at [projectRoot] (the tab's
/// `currentProjectProvider` root) using the same root-relative FNV-1a
/// scheme the baseline subsystem uses. Exposed here so the bookmark column
/// icon, the toggle action, the panel and the dialog all derive the
/// fingerprint identically.
///
/// Delegates to the identity-memoized [baselineFingerprintFor] — the
/// bookmark column icon calls this per visible row on every rebuild, so
/// caching by instance keeps the virtualized table fast and shares the cache
/// with the baseline "Only new" derive. Byte-identical to
/// [BaselineFingerprint.forProject] on the same fields.
String computeBookmarkFingerprint(
  Violation violation, {
  required String projectRoot,
}) => baselineFingerprintFor(violation, projectRoot: projectRoot);
