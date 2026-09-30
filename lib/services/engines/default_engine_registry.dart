// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart' show YosysDiagnostic;
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_engine.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:lintcrux/services/engines/svlint/svlint_engine.dart';
import 'package:lintcrux/services/engines/verible/verible_engine.dart';
import 'package:lintcrux/services/engines/verilator/verilator_engine.dart';
import 'package:lintcrux/services/engines/yosys/yosys_check_engine.dart';

/// Builds the open-core [EngineRegistry] without touching Flutter.
///
/// `engineRegistryProvider` used to construct this list inline, which
/// made the *only* definition of "which engines does LintCrux ship"
/// reachable only through a Riverpod provider — and therefore only from
/// a Flutter host. The headless CI binary needs the same list and must
/// not import `flutter_riverpod`, so the list moved here and the
/// provider became a one-line wrapper.
///
/// Keeping one definition matters for the same reason
/// [EngineRunPlanner] does: if the CLI shipped a different engine set
/// from the desktop app, a project's `enabledEngineIds` would resolve
/// differently in CI than on the engineer's machine.
///
/// [onYosysDiagnostics], when supplied, receives the Yosys adapter's
/// parsed stderr diagnostics. The GUI forwards them to the Tab
/// Diagnostics drawer; the CLI passes `null` because it has no drawer
/// (the violations themselves still flow through the normal path).
/// [cdcEngine] replaces the CDC engine. This is the seam the Pro overlay uses
/// to install clock-tree tracing, `cdc.yaml` constraints and the advanced
/// synchronizer idioms — the tier split lives in *which engine is supplied*,
/// not in a licence check inside the analysis. Open core passes nothing and
/// gets the pessimistic default: every distinct clock net is its own
/// asynchronous domain, and only a two-flop chain counts as protection.
///
/// It is a whole-engine override rather than an analysis override because the
/// Pro engine's behaviour depends on the *request* — it reads `cdc.yaml` from
/// the directory holding the sources — so there is nothing to inject at
/// construction time.
EngineRegistry defaultEngineRegistry({
  void Function(List<YosysDiagnostic> diagnostics)? onYosysDiagnostics,
  LintEngine? cdcEngine,
}) {
  return EngineRegistry(<LintEngine>[
    VerilatorEngine(),
    VeribleEngine(),
    SlangEngine(),
    YosysCheckEngine(onDiagnostics: onYosysDiagnostics),
    GhdlEngine(),
    SvlintEngine(),
    // Structural CDC lint. One more engine in the pipeline —
    // its findings are ordinary Violations, so waivers, trends, SARIF and
    // cross-probe need no CDC-specific code.
    cdcEngine ?? CdcEngine(),
  ]);
}
