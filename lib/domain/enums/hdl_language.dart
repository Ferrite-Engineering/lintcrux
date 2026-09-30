// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Source languages a [LintEngine] may declare it can lint.
///
/// Used by `LintRunRequest.language` and `EngineCapabilities
/// .supportedLanguages` to route source files to the right engines. A
/// project containing both Verilog and VHDL sources is `mixed` —
/// engine plugins must opt in to mixed-language designs explicitly
/// (most don't; `verilator` accepts Verilog/SystemVerilog only, `ghdl`
/// accepts VHDL only).
enum HdlLanguage {
  /// IEEE 1364 Verilog (any of the -1995/-2001/-2005 revisions).
  verilog,

  /// IEEE 1800 SystemVerilog. A superset of Verilog for most parser
  /// purposes — engines that accept SystemVerilog typically accept
  /// Verilog too.
  systemVerilog,

  /// IEEE 1076 VHDL.
  vhdl,

  /// A project whose source files span more than one of the above. The
  /// engine routing layer picks per-engine subsets at run time.
  mixed,
}
