// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings-driven toggle for the lint-run cache.
///
/// When `true` (the default), `ParallelEngineRunner` consults
/// [lintRunCacheServiceProvider] before invoking each engine — a
/// hit serves the cached violations directly; a miss runs the
/// engine and stores the result.
///
/// When `false`, the runner bypasses the cache in both directions:
/// no lookups, no stores. Equivalent to the Open Core no-op service
/// from the runner's perspective — useful for users who suspect a
/// stale cache is masking an engine update.
///
/// The Pro overlay's `LintCacheSettingsSection` widget overrides
/// this provider with a notifier backed by `shared_preferences`.
final Provider<bool> lintCacheEnabledProvider = Provider<bool>((_) => true);
