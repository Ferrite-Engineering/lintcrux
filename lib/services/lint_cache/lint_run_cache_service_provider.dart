// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;
import 'package:lintcrux/domain/interfaces/lint_run_cache_service.dart';

/// Internal per-project family providing one [LintRunCacheService] per
/// active project id.
///
/// Open-core keys one [NoopLintRunCacheService] per project; the Pro
/// overlay overrides the wrapper [lintRunCacheServiceProvider] with a
/// per-project SQLite-backed service. Distinct instances per project keep
/// two open projects' caches from sharing one in-memory handle.
final ProviderFamily<LintRunCacheService, String>
lintRunCacheServicePerProjectFamily =
    Provider.family<LintRunCacheService, String>(
      // Non-const on purpose: a fresh instance per project id makes the
      // per-project scoping observable by identity (a const would canonicalize
      // to one shared instance). The noop is stateless so this is harmless.
      // ignore: prefer_const_constructors
      (ref, projectId) => NoopLintRunCacheService(),
      name: 'lintRunCacheServicePerProject',
    );

/// Riverpod seam for [LintRunCacheService].
///
/// Open Core resolves to [NoopLintRunCacheService] — cache is a silent
/// no-op. Lifted to [perProjectScope] so each project owns
/// its own cache instance. The Pro overlay overrides this provider with
/// `SqliteLintRunCacheService` (per-project SQLite-backed implementation).
///
/// The provider is plain `Provider<LintRunCacheService>` rather than an
/// `AsyncNotifierProvider` because the Pro overlay opens its SQLite
/// database eagerly on first access through a memoized future inside the
/// service. Synchronous read keeps the runner integration unchanged when
/// the user flips the cache toggle on and off.
final Provider<LintRunCacheService> lintRunCacheServiceProvider =
    perProjectScope<LintRunCacheService>(
      'lint_run_cache_service',
      (ref, projectId) =>
          ref.watch(lintRunCacheServicePerProjectFamily(projectId)),
    );
