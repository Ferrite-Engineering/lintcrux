// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/interfaces/violation_transformer.dart';
import 'package:lintcrux/domain/interfaces/waiver_store.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Applies the managed waiver system's matching engine as a step in the
/// violation transformer pipeline.
///
/// Reads waivers from [store] (typically a `JsonFileWaiverStore` in the
/// Pro overlay, or a [NoopWaiverStore] in open-core) and marks
/// `Violation.suppression` with any matching waiver. Already-suppressed
/// violations (e.g. by an inline pragma earlier in the pipeline) pass
/// through unchanged so a source pragma always wins over a managed
/// waiver — the source is closer to the engineer's intent.
///
/// Expiration is enforced by `WaiverStore.match` per the interface
/// contract; this transformer does not duplicate that check.
class ManagedWaiverTransformer implements ViolationTransformer {
  /// Creates a [ManagedWaiverTransformer] reading waivers from [store].
  const ManagedWaiverTransformer(this.store);

  /// The waiver store this transformer consults on each `transform`.
  final WaiverStore store;

  @override
  Violation transform(Violation v) {
    // Source pragmas win: a violation that's already suppressed keeps
    // its existing suppression rather than being re-tagged.
    if (v.suppression != null) return v;
    final waiver = store.match(v);
    if (waiver == null) return v;
    return v.copyWith(suppression: waiver);
  }
}
