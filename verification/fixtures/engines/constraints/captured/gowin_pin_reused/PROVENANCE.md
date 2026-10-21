# gowin pin reused

`pins.cst` and `top.v`, for Gowin GW1NR-9 (GW1NR-LV9QN88PC6/I5). `led[2]` is put on the pin `led[1]` already has.

LintCrux expects: `constraints/pin-reused` on the `led[2]` line. `expected.sarif.json` was written by hand from the
constraint file, not from LintCrux's output or nextpnr's.

## What nextpnr does with it

nextpnr-himbaechel **errors** on this file. It fails at placement: `Can't place led_OBUF_O_1 at X0Y15/IOBB because it's already taken by led_OBUF_O_2`. The message names neither the pin nor the line.

`output.txt` is the captured run. Its reader is `himbaechel/uarch/gowin/cst.cc` at the nextpnr
revision below.

## Tools

Captured with OSS CAD Suite tag `2026-10-21`, darwin-arm64:

```text
Yosys 0.70+186 (git sha1 3718f7f13)
nextpnr 0.11.1-77-g6b438a1c (commit 6b438a1c9ab83cfb872fea21d9545d7d0bb8573f)
```

```sh
yosys -q -p "read_verilog top.v; synth_gowin -top top -json netlist.json"
```

then the command on the first line of `output.txt`, run from a directory
holding `top.v` and `pins.cst`. `tool/capture_constraint_fixtures.py` does both
and writes `output.txt` only. Captured on 2026-10-21 with the home and work
directories scrubbed.

LintCrux has no engine canary, and its `ci.yml` test job installs only
`verilator` and `yosys`: nextpnr is not available there, so nothing in CI
re-runs the nextpnr command. The live assertion in
`test/services/engines/constraints/constraints_fixture_test.dart` runs the
`constraints` engine, over real Yosys, against `expected.sarif.json`. The
nextpnr outcome is recorded here and in `output.txt`, and is re-captured by
the tool above when the suite moves.

## Source RTL

`top.v` and `pins.cst` were written for this fixture. They are not derived from
any third-party project.

SPDX: `CC0-1.0`
