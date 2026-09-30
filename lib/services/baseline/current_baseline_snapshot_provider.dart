// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/lint_baseline.dart';

/// Synchronous snapshot of the active [LintBaseline], or `null` when
/// no baseline is set.
///
/// The open-core default returns `null` — open-core builds never set a baseline
/// (the baseline & delta workflow is a Pro feature). The Pro overlay overrides
/// this provider with one that mirrors the latest value emitted by
/// `baselineStoreProvider.watch()`.
///
/// The reason this provider is synchronous (`Provider<LintBaseline?>`)
/// rather than a `StreamProvider` is that the violation post-filter
/// in `visibleViolationsProvider` needs a value-typed read inside its
/// derive function. The Pro bridge that listens to the underlying
/// stream is responsible for pumping each emission into a state
/// notifier that overrides this provider.
final Provider<LintBaseline?> currentBaselineSnapshotProvider =
    Provider<LintBaseline?>((_) => null);
