// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Generator for the engine-output parser corpus.
//
// Declares the case table in Dart, runs the **real** engine parser over
// each case's canned `output.txt`, and writes three files per case into
// both the `test/` tree (unit-test backbone) and the `verification/`
// mirror (release sign-off corpus) in one pass so they cannot drift:
//
//   <case>/cmdline.txt          the exact engine invocation (documentation)
//   <case>/output.txt           the canned engine output (parser input)
//   <case>/expected.sarif.json  the golden unified SARIF (parser output)
//
// Run from the lintcrux package root:
//
//   dart run tool/generate_engine_corpus.dart
//
// The golden test (`engine_golden_test.dart`) re-derives the SARIF from the
// committed `output.txt` and compares; a drift fails the test with a "run
// the generator" hint. Editing a case here + re-running is the supported
// way to refresh the goldens.
// The two adjacent-string lints assume prose. This file is a corpus of
// *captured engine output* — JSON one-liners and compiler diagnostics — split
// across source lines purely to stay inside the line limit. Joining them would
// mean unreadable 200-column literals; inserting the whitespace the second
// lint asks for would corrupt the JSON fixtures it fires on. The comma-omission
// bug `no_adjacent_strings_in_list` exists to catch is real, so this stays a
// file-level exemption rather than a rule disabled for all of tool/.
// ignore_for_file: no_adjacent_strings_in_list, missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:io';

import '../test/services/engines/engine_corpus_support.dart';

/// One generated corpus case: a canned engine invocation + output, from
/// which the golden SARIF is derived by running the real parser.
class _Case {
  const _Case({
    required this.engineId,
    required this.name,
    required this.cmdline,
    required this.output,
  });

  final String engineId;
  final String name;
  final String cmdline;
  final List<String> output;
}

/// The case table. Each case isolates one parser concern (a basic
/// diagnostic, multi-line continuation, path-with-spaces, Unicode
/// filename, residual ANSI, an unrecognized line surfaced as a
/// notification). Output strings are realistic, hand-trimmed engine
/// emissions.
const List<_Case> _cases = <_Case>[
  // ── Verilator (stderr text) ──────────────────────────────────────────
  _Case(
    engineId: 'verilator',
    name: 'unused_signal',
    cmdline: 'verilator --lint-only -Wall top.sv',
    output: <String>[
      "%Warning-UNUSEDSIGNAL: top.sv:42:13: Signal is not used: 'unused_sig'",
    ],
  ),
  _Case(
    engineId: 'verilator',
    name: 'multiline_continuation',
    cmdline: 'verilator --lint-only top.sv',
    output: <String>[
      '%Warning-WIDTH: alu.sv:88:7: Operator ASSIGNW expects 32 bits but got 16',
      '                              : ... In instance top.alu',
      '   88 |   assign y = a + b;',
      '      |            ^',
    ],
  ),
  _Case(
    engineId: 'verilator',
    name: 'path_with_spaces',
    cmdline: 'verilator --lint-only "a dir/sub mod.sv"',
    output: <String>[
      "%Warning-UNUSED: a dir/sub mod.sv:12:3: Bits of signal are not used: 'q'[7:4]",
    ],
  ),
  _Case(
    engineId: 'verilator',
    name: 'unicode_filename',
    cmdline: 'verilator --lint-only 日本語.sv',
    output: <String>[
      "%Warning-UNUSEDSIGNAL: 日本語.sv:5:1: Signal is not used: 'クロック'",
    ],
  ),
  _Case(
    engineId: 'verilator',
    name: 'ansi_color_tty',
    cmdline: 'verilator --lint-only top.sv',
    output: <String>[
      // Residual ANSI inside the message (the spawn layer sets NO_COLOR so
      // the `%Warning` prefix is never wrapped; the parser must still
      // tolerate escapes embedded in the captured message text).
      '%Warning-UNUSEDSIGNAL: top.sv:7:3: Signal is not used: '
          "\x1B[33m'tmp'\x1B[0m",
    ],
  ),
  _Case(
    engineId: 'verilator',
    name: 'unrecognized_line',
    cmdline: 'verilator --lint-only top.sv',
    output: <String>[
      '~~~ stray line matching no diagnostic pattern ~~~',
      "%Warning-UNUSEDSIGNAL: top.sv:9:3: Signal is not used: 'spare'",
    ],
  ),
  // Version-drift pair: the same violation reported under the
  // current rule name (`UNUSEDSIGNAL`) and the N-1 name (`UNUSED`). The
  // rule-alias table reconciles the two; `version_drift_test.dart` reads
  // these two outputs.
  _Case(
    engineId: 'verilator',
    name: 'drift_current',
    cmdline: 'verilator-5.x --lint-only cpu.sv',
    output: <String>[
      "%Warning-UNUSEDSIGNAL: cpu.sv:30:5: Signal is not used: 'tmp'",
    ],
  ),
  _Case(
    engineId: 'verilator',
    name: 'drift_nminus1',
    cmdline: 'verilator-4.x --lint-only cpu.sv',
    output: <String>[
      "%Warning-UNUSED: cpu.sv:30:5: Signal is not used: 'tmp'",
    ],
  ),

  // ── GHDL (stderr text) ───────────────────────────────────────────────
  //
  // GHDL puts NO space between the location and the severity word, and
  // echoes the offending source line verbatim (no `NN |` gutter). The
  // cases below use that real spelling — verified against GHDL 6.0.0 and
  // 5.1.1. The spaced, GCC-gutter form these cases used to carry has
  // never been emitted by any GHDL release we can run; the parser had
  // been written against it and therefore matched nothing at all.
  // `captured/ghdl_6_0_0_analyse/` holds the unedited real transcript.
  _Case(
    engineId: 'ghdl',
    name: 'unused_variable',
    cmdline: 'ghdl -a --std=08 --warn-unused design.vhd',
    output: <String>[
      'design.vhd:42:13:warning: variable "x" is never referenced [-Wunused]',
    ],
  ),
  _Case(
    engineId: 'ghdl',
    name: 'multiline_continuation',
    cmdline: 'ghdl -a --warn-hide adder.vhd',
    output: <String>[
      'adder.vhd:17:14:warning: declaration of "carry" hides signal "carry" '
          '[-Whide]',
      '    variable carry : std_logic;',
      '             ^',
    ],
  ),
  _Case(
    engineId: 'ghdl',
    name: 'path_with_spaces',
    cmdline: 'ghdl -a "my designs/top entity.vhd"',
    output: <String>[
      'my designs/top entity.vhd:3:1:error: entity "foo" not found',
    ],
  ),
  _Case(
    engineId: 'ghdl',
    name: 'unicode_filename',
    cmdline: 'ghdl -a --warn-unused café.vhd',
    output: <String>[
      'café.vhd:2:1:warning: signal "señal" is never referenced [-Wunused]',
    ],
  ),
  _Case(
    engineId: 'ghdl',
    name: 'unrecognized_line',
    cmdline: 'ghdl -a --warn-unused top.vhd',
    output: <String>[
      // GHDL's own failure summary carries no line number, so it is not a
      // diagnostic — it must surface as a notification, not be dropped.
      'top.vhd:9:3:warning: signal "spare" is never referenced [-Wunused]',
      'ghdl:error: compilation error',
    ],
  ),
  // Tolerance case: a build that *does* insert a space before the
  // severity (the separator is matched as `\s*`). No GHDL release we can
  // run emits this, so it is asserted as a parser capability only — see
  // `captured/ghdl_6_0_0_analyse/` for what real GHDL prints.
  _Case(
    engineId: 'ghdl',
    name: 'spaced_severity_tolerance',
    cmdline: 'ghdl -a --warn-unused legacy.vhd  # hypothetical spaced build',
    output: <String>[
      'legacy.vhd:7:2: warning: signal "q" is never referenced [-Wunused]',
    ],
  ),

  // ── Verible (JSON-line) ──────────────────────────────────────────────
  _Case(
    engineId: 'verible',
    name: 'basic_warning',
    cmdline: 'verible-verilog-lint --lint-output=jsonline top.sv',
    output: <String>[
      '{"path":"top.sv","line":12,"column":3,"rule":"no-tabs",'
          '"severity":"warning","message":"Use spaces, not tabs."}',
    ],
  ),
  _Case(
    engineId: 'verible',
    name: 'path_with_spaces',
    cmdline: 'verible-verilog-lint --lint-output=jsonline "a dir/mod x.sv"',
    output: <String>[
      '{"path":"a dir/mod x.sv","line":5,"column":1,"rule":"line-length",'
          '"severity":"warning","message":"Line too long"}',
    ],
  ),
  _Case(
    engineId: 'verible',
    name: 'unicode_filename',
    cmdline: 'verible-verilog-lint --lint-output=jsonline 日本語.sv',
    output: <String>[
      '{"path":"日本語.sv","line":2,"column":1,'
          '"rule":"explicit-parameter-storage-type",'
          '"severity":"warning","message":"パラメータ"}',
    ],
  ),
  _Case(
    engineId: 'verible',
    name: 'unrecognized_line',
    cmdline: 'verible-verilog-lint --lint-output=jsonline top.sv',
    output: <String>[
      '{"path":"top.sv","line":7,"column":2,"rule":"no-tabs",'
          '"severity":"warning","message":"tab found"}',
      'I am not JSON and not a text diagnostic either',
    ],
  ),
  // Upstream text mode — what a stock `verible-verilog-lint` release
  // actually prints (there is no `--lint_output` flag upstream). Column
  // RANGES and the `[Style: …] [rule]` double bracket are the norm; the
  // pre-2026-07-21 parser matched none of these lines and the engine
  // reported a clean run.
  _Case(
    engineId: 'verible',
    name: 'upstream_text_column_range',
    cmdline: 'verible-verilog-lint --ruleset all top.sv',
    output: <String>[
      'top.sv:8:24-42: Line length exceeds max: 100; is: 118 [line-length]',
      'top.sv:12:1-8: Use spaces, not tabs. [Style: tabs] [no-tabs]',
      'top.sv:31:3: Explicit parameter storage type recommended '
          '[explicit-parameter-storage-type]',
    ],
  ),

  // ── Slang (`--diag-json -`) ──────────────────────────────────────────
  //
  // The real payload is one pretty-printed JSON ARRAY, `location` is a
  // "file:line:column" STRING, and the rule id is `optionName` (slang's
  // `-W` name). These cases used to assert one-object-per-line with a
  // `location` object and a `slang::diag::` `code`, produced by a
  // `--json-diagnostics` flag that has never existed in slang — so JSON
  // mode parsed nothing. `captured/slang_11_0_0_*/` holds the unedited
  // real transcripts.
  _Case(
    engineId: 'slang',
    name: 'implicit_convert',
    cmdline: 'slang -q --diag-json - top.sv',
    output: <String>[
      '[',
      '  {',
      '    "severity": "warning",',
      '    "message": "implicit conversion from \'logic[7:0]\' to '
          '\'logic[3:0]\' changes value",',
      '    "optionName": "implicit-conv",',
      '    "location": "top.sv:20:9",',
      '    "symbolPath": "top"',
      '  }',
      ']',
    ],
  ),
  _Case(
    engineId: 'slang',
    name: 'path_with_spaces',
    cmdline: 'slang -q --diag-json - "a dir/m.sv"',
    output: <String>[
      // An error carries no `optionName` — it must still parse, as
      // slang/UNCLASSIFIED.
      '[',
      '  {',
      '    "severity": "error",',
      '    "message": "use of undeclared identifier \'foo\'",',
      '    "location": "a dir/m.sv:4:2",',
      '    "symbolPath": "m"',
      '  }',
      ']',
    ],
  ),
  _Case(
    engineId: 'slang',
    name: 'unicode_filename',
    cmdline: 'slang -q --diag-json - 設計.sv',
    output: <String>[
      '[',
      '  {',
      '    "severity": "warning",',
      '    "message": "幅切り捨て",',
      '    "optionName": "width-trunc",',
      '    "location": "設計.sv:3:1",',
      '    "symbolPath": "設計"',
      '  }',
      ']',
    ],
  ),
  _Case(
    engineId: 'slang',
    name: 'unrecognized_line',
    cmdline: 'slang --diag-json - top.sv',
    output: <String>[
      // Without `-q` slang wraps the array in its banner; the prose must
      // surface as notifications while the diagnostics still parse.
      'Top level design units:',
      '    top',
      '',
      '[',
      '  {',
      '    "severity": "warning",',
      '    "message": "unused variable \'spare\'",',
      '    "optionName": "unused-variable",',
      '    "location": "top.sv:6:1",',
      '    "symbolPath": "top.spare"',
      '  }',
      ']',
      'Build succeeded: 0 errors, 1 warning',
    ],
  ),
  _Case(
    engineId: 'slang',
    name: 'upstream_text_mode',
    cmdline: 'slang -q top.sv  # textModeFallback / slang < 8.0',
    output: <String>[
      "top.sv:15:23: error: use of undeclared identifier 'undeclared_thing'",
      '  assign narrow_out = undeclared_thing;',
      '                      ^~~~~~~~~~~~~~~~',
      "top.sv:8:15: warning: unused variable 'never_used' "
          '[-Wunused-variable]',
      '  logic       never_used;',
      '              ^',
    ],
  ),

  // ── Svlint (JSON) ────────────────────────────────────────────────────
  _Case(
    engineId: 'svlint',
    name: 'basic',
    cmdline: 'svlint --output-format=json top.sv',
    output: <String>[
      '{"path":"top.sv","line":15,"column":5,'
          '"rule":"non_blocking_assignment_in_always_comb",'
          '"message":"non-blocking in always_comb"}',
    ],
  ),
  _Case(
    engineId: 'svlint',
    name: 'path_with_spaces',
    cmdline: 'svlint --output-format=json "a dir/x.sv"',
    output: <String>[
      '{"path":"a dir/x.sv","line":3,"column":1,'
          '"rule":"tab_character","message":"tab found"}',
    ],
  ),
  _Case(
    engineId: 'svlint',
    name: 'unicode_filename',
    cmdline: 'svlint --output-format=json 回路.sv',
    output: <String>[
      '{"path":"回路.sv","line":2,"column":1,'
          '"rule":"keyword_forbidden_wire_reg","message":"禁止"}',
    ],
  ),
  _Case(
    engineId: 'svlint',
    name: 'unrecognized_line',
    cmdline: 'svlint --output-format=json top.sv',
    output: <String>[
      '{"path":"top.sv","line":8,"column":1,'
          '"rule":"no_generate_keyword","message":"avoid generate"}',
      'svlint 0.9 banner -- not a diagnostic',
    ],
  ),

  // ── Yosys (check -assert stderr, parsed by crux_yosys) ───────────────
  _Case(
    engineId: 'yosys',
    name: 'check_assert',
    cmdline:
        'yosys -q -p "read_verilog cpu.sv; hierarchy -top cpu; '
        'check -assert"',
    output: <String>[
      '/proj/cpu.sv:42:5: Warning: synthesis: unused signal foo',
      '/proj/cpu.sv:7: ERROR: multiply driven net conflict',
    ],
  ),
  _Case(
    engineId: 'yosys',
    name: 'module_fallback',
    cmdline: 'yosys -q -p "check -assert"',
    output: <String>[
      r'Warning: Found multiply driven net \q in module \regfile',
    ],
  ),
];

void main() {
  const encoder = JsonEncoder.withIndent('  ');
  final roots = <String>[
    'test/fixtures/engines',
    'verification/fixtures/engines',
  ];
  var written = 0;
  for (final c in _cases) {
    final sarif = buildCorpusSarifMap(c.engineId, c.name, c.output);
    final goldenJson = '${encoder.convert(sarif)}\n';
    final outputText = '${c.output.join('\n')}\n';
    final cmdlineText = '${c.cmdline}\n';
    for (final root in roots) {
      final dir = Directory('$root/${c.engineId}/generated/${c.name}')
        ..createSync(recursive: true);
      File('${dir.path}/cmdline.txt').writeAsStringSync(cmdlineText);
      File('${dir.path}/output.txt').writeAsStringSync(outputText);
      File('${dir.path}/expected.sarif.json').writeAsStringSync(goldenJson);
    }
    written++;
  }
  stdout.writeln(
    'generate_engine_corpus: wrote $written cases × ${roots.length} trees '
    '(${written * roots.length * 3} files).',
  );
}
