// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How long LintCrux lets an engine that elaborates the design with Yosys
/// (the `yosys`, `cdc` and `constraints` engines) run before stopping it.
///
/// The automatic budget scales with the size of the design's source files
/// (see `YosysEngineBudget`); this setting scales it further or removes it.
/// Settings, Engines, Yosys time limit offers all three. The other engines
/// keep the fixed engine watchdog whatever is chosen here.
enum ElaborationTimeLimit {
  /// The budget the size of the sources gives.
  automatic(1),

  /// Four times that budget, for a slow or heavily loaded machine.
  extended(4),

  /// No limit: the engine runs until it finishes or the user cancels.
  none(0);

  const ElaborationTimeLimit(this.factor);

  /// How many times the automatic budget this choice allows; `0` means the
  /// engine is not stopped by a timer.
  final int factor;
}
