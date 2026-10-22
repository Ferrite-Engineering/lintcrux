# CDC package fixture

Hand-written for LintCrux on 2026-10-21. Two files, one design:

| File | Role |
|---|---|
| `cdc_types_pkg.sv` | A package: `byte_t`, the `mode_e` enum and a function, `next_byte`, whose body is a `?:` |
| `pkg_cdc_top.sv` | Top; imports the package, two clock domains `clk_a` and `clk_b` |

## Why it exists

Package-based SystemVerilog is what Yosys's built-in `read_verilog -sv` cannot
read and yosys-slang can. This is the smallest design that needs a package to
elaborate and still has both a hazard and a correct synchronizer, so a CDC run
that elaborates it can be checked for the right answer, not just for running.

## The expected answer, from the RTL

- Two clock domains, `clk_a` and `clk_b`.
- `data_b <= data_a` (`pkg_cdc_top.sv` line 28) samples the 8-bit `data_a`
  from `clk_a` in `clk_b` with nothing between: one `cdc/unsync-multi-bit`
  error anchored at line 28, the driving register (`data_a`, the `clk_a`
  `always_ff` at line 23) as the related location.
- `req_a` reaches `clk_b` through `req_meta` then `req_b` (lines 31 to 34), a
  two-flop chain: no finding.
- Nothing else crosses: one unsafe crossing in the summary.

These come from reading the RTL. They were not taken from the CDC engine's
output, which is what the live test checks against them.

## What each Yosys does with it

Measured 2026-10-21 on darwin-arm64 with the CDC engine's pass list (read,
`hierarchy -check -top pkg_cdc_top`, `proc`, `flatten`, `write_json`):

| Yosys | Reader | Result |
|---|---|---|
| OSS CAD Suite 2026-10-21, `Yosys 0.70+186 (git sha1 3718f7f13)`, yosys-slang built in | `read_slang -f <command file>` with `--single-unit --top pkg_cdc_top --ignore-initial --ignore-assertions` | Elaborates. Every `src` file is written relative to the directory Yosys ran in (`cdc_types_pkg.sv:17.30-17.38`), with or without `--diag-abs-paths` |
| Homebrew `Yosys 0.69+post (git sha1 143eb14f9)` | `read_verilog -sv` (it has no `read_slang`) | Fails: `cdc_types_pkg.sv:17: ERROR: syntax error, unexpected '?'` |

## Tests

- `test/services/engines/cdc/cdc_slang_live_test.dart` runs the real engine
  over both Yosys builds: with yosys-slang (tagged `oss-cad-live`; set
  `OSS_CAD_SUITE` to the suite directory) it checks the answer above at the
  project's own paths, with the sources in the run directory and two levels
  below it; without yosys-slang (the Yosys on `PATH`) it checks the run ends in
  one `cdc/needs-slang-frontend` finding at the package declaration.
