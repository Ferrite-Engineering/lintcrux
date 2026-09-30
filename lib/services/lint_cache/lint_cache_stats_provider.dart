// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_cache_invalidation_event.dart';
import 'package:lintcrux/domain/models/lint_cache_stats.dart';
import 'package:lintcrux/services/lint_cache/lint_run_cache_service_provider.dart';

/// Reactive `Future<LintCacheStats>` provider that watches the
/// active [LintRunCacheService]'s invalidations stream and refreshes
/// whenever an event ticks.
///
/// Subscribers (the stats card in Settings → Lint Cache) get a
/// fresh snapshot after every store / lookup / invalidation cycle
/// without polling.
///
/// On the open-core no-op service this resolves to
/// [LintCacheStats.empty] and never refreshes (the stream is
/// empty).
final FutureProvider<LintCacheStats> lintCacheStatsProvider =
    FutureProvider<LintCacheStats>(buildLintCacheStats);

/// Build body of [lintCacheStatsProvider]. Top-level so
/// `lintcruxTabOverridesFactory` can re-bind the provider per tab with the
/// identical body — the stats must derive from the tab's own
/// `lintRunCacheServiceProvider` binding (the Pro overlay scopes the cache
/// service per tab, rooted at that tab's project), not the root-scope
/// no-op service.
Future<LintCacheStats> buildLintCacheStats(Ref ref) async {
  final service = ref.watch(lintRunCacheServiceProvider);
  final sub = service.invalidations.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return await service.stats();
}

/// Bare invalidation-event stream. Consumed by the invalidations
/// dialog so it can render the rolling log without subscribing to
/// the stats provider's `Future` lifecycle.
final StreamProvider<LintCacheInvalidationEvent>
lintCacheInvalidationsProvider = StreamProvider<LintCacheInvalidationEvent>(
  buildLintCacheInvalidations,
);

/// Build body of [lintCacheInvalidationsProvider]. Top-level so
/// `lintcruxTabOverridesFactory` can re-bind the provider per tab with
/// the identical body (same rationale as [buildLintCacheStats]).
Stream<LintCacheInvalidationEvent> buildLintCacheInvalidations(Ref ref) {
  final service = ref.watch(lintRunCacheServiceProvider);
  return service.invalidations;
}
