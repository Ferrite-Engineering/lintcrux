// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';

/// Live count of bookmarked violations for the active project.
///
/// Re-evaluates whenever [violationBookmarkStoreProvider]'s `changed`
/// stream emits. The count badge on the violations-table header
/// reads this value; the bookmark panel ignores it (it reads
/// `listAll()` directly so it can render the full list).
///
/// Open-core ships [NoopViolationBookmarkStore] whose `listAll()`
/// returns an empty list and `changed` never emits, so this provider
/// settles on `0` once the initial future resolves. The Pro overlay's
/// `JsonFileViolationBookmarkStore` makes the count reactive.
final StreamProvider<int> bookmarkedViolationsCountProvider =
    StreamProvider<int>(buildBookmarkedViolationsCount);

/// Build body of [bookmarkedViolationsCountProvider]. Top-level so
/// `lintcruxTabOverridesFactory` can re-bind the provider per tab with the
/// identical body — the count must derive from the tab's own
/// `violationBookmarkStoreProvider` binding (the Pro overlay scopes the
/// bookmark store per tab), not the root-scope no-op store.
Stream<int> buildBookmarkedViolationsCount(Ref ref) async* {
  final store = ref.watch(violationBookmarkStoreProvider);
  // Initial snapshot.
  yield (await store.listAll()).length;
  // React to mutations.
  await for (final _ in store.changed) {
    yield (await store.listAll()).length;
  }
}
