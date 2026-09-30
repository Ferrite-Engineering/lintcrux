// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:lintcrux/domain/interfaces/baseline_store.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';

/// Open-core [BaselineStore] returning `null` for the active baseline
/// and rejecting mutations with [UnsupportedError].
///
/// The baseline & delta workflow is a Pro feature. This is the default of
/// `baselineStoreProvider`, which the open core never reads; the Pro overlay
/// binds the provider to the JSON-backed implementation that persists to
/// `<project-root>/.lintcrux-baseline.json`, and falls back to this store for
/// a tab with no project, or with a project that has no root to write under.
///
/// Mirrors the shape of `NoopWaiverStore` exactly so the two no-op
/// implementations are interchangeable in tests and reviewer
/// expectations.
class NoopBaselineStore implements BaselineStore {
  /// Creates a no-op store.
  NoopBaselineStore();

  final StreamController<LintBaseline?> _events =
      StreamController<LintBaseline?>.broadcast();

  @override
  Future<LintBaseline?> activeBaseline() async => null;

  @override
  Future<void> setBaseline(LintBaseline baseline) async {
    throw UnsupportedError(
      'Setting a baseline requires LintCrux Pro. '
      'See https://docs.lintcrux.app/baselines',
    );
  }

  @override
  Future<void> clearBaseline() async {
    // Clearing on a permanently-empty store is a no-op rather than a
    // throw, matching the convention from NoopWaiverStore's delete()
    // — idempotent removal stays cheap for callers that fire it
    // defensively.
  }

  @override
  Stream<LintBaseline?> watch() => _events.stream;

  /// Closes the broadcast stream. Call from `ref.onDispose`.
  Future<void> dispose() => _events.close();
}
