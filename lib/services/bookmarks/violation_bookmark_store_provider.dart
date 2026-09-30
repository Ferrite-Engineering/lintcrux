// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';

/// Open-core extension point through which the Pro overlay
/// contributes a Pro-grade [ViolationBookmarkStore] implementation.
///
/// Open Core ships [NoopViolationBookmarkStore] (`listAll` returns an empty
/// list; mutations silently no-op) — the bookmark feature is Pro. The Pro
/// overlay's `proOverrides` replaces this provider with one that returns a
/// `JsonFileViolationBookmarkStore` (reading / writing
/// `<project-root>/.lintcrux-bookmarks.json` with stale-detection integration
/// into `lintRunCompletionEventProvider`).
final Provider<ViolationBookmarkStore> violationBookmarkStoreProvider =
    Provider<ViolationBookmarkStore>(
      (_) => const NoopViolationBookmarkStore(),
    );
