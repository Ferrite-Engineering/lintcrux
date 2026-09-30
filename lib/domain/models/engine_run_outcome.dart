// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How one engine's run ended, coarsened to the four answers that matter
/// outside the UI.
///
/// [EngineRunPhase] is the *display* vocabulary: it distinguishes `idle` from
/// `running` because the run-status panel draws them differently, and it folds
/// a watchdog kill and a crashed subprocess into the same `failed` because the
/// panel shows both as an error chip with the diagnostic underneath. That fold
/// is the reason this enum exists — "the engine hung" and "the engine died" are
/// the same row to a user and completely different answers to "is this engine
/// healthy in the field", which is the question the `engine.run` counter
/// is for.
///
/// Deliberately *not* a superset of [EngineRunPhase]: a cancelled run has no
/// outcome here. The user pressing Stop says nothing about the engine, and a
/// fifth token for it would put a value in the counter that no roadmap question
/// reads. [ParallelEngineRunner] simply reports nothing for that case.
enum EngineRunOutcome {
  /// The engine ran to completion. Violations, or the absence of them, are in
  /// the store.
  ok,

  /// The watchdog's inactivity budget elapsed and the subprocess was killed.
  timeout,

  /// The engine started and then failed — a non-zero exit it could not
  /// explain, a parse failure, an exception mid-stream.
  crash,

  /// The engine binary could not be found or could not be invoked at all.
  missing,
}
