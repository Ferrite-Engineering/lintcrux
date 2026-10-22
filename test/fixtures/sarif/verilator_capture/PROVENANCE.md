# Verilator SARIF fixture

Design and captures: SPDX: Apache-2.0

One design, `sarif_design.sv`, linted by three real Verilator builds. For
each build there are three files:

| File | What it is |
|---|---|
| `<tag>.stderr.txt` | Verilator's stderr, byte for byte |
| `<tag>.sarif` | The file Verilator wrote for `--diagnostics-sarif-output`, with one substitution (below) |
| `<tag>.version.txt` | `verilator --version` |

Captured 2026-10-22 on darwin-arm64 from the OSS CAD Suite builds under test
(`<tag>` is the suite's date):

| Tag | `verilator --version` |
|---|---|
| `oss-cad-2026-08-21` | `Verilator 5.051 devel rev v5.050-226-gf7c087468 (mod)` |
| `oss-cad-2026-09-21` | `Verilator 5.053 devel rev v5.052-119-g014c9820d (mod)` |
| `oss-cad-2026-10-21` | `Verilator 5.053 devel rev v5.052-521-g6388139f7 (mod)` |

The command, run from the directory holding the design:

```text
verilator --lint-only -Wall --diagnostics-sarif-output out/<tag>.sarif sarif_design.sv
```

## The one edit

Verilator writes absolute, `realpath`-ed URIs (`file://<capture directory>/sarif_design.sv`).
The capture directory's absolute path was replaced by the token `@ROOT@` so
the committed files carry no machine's path. The tests put it back
(`/work/sarif_design`) when they read a file. Nothing else in either file was
touched.

## The expected answer, from the RTL

`sarif_design.sv` raises these under `-Wall`, by construction (its header
comment lists them):

- `WIDTHTRUNC` at line 21 (`assign y = a`, 4 bits into 2)
- `UNUSEDSIGNAL` for `unread_sig` (line 18) and for the upper bits of `a` (its
  declaration, line 13)
- `UNDRIVEN` for `undriven_sig` (line 19)
- `MULTIDRIVEN` twice for `md`: once at the second `always_ff` (line 24), once
  at the declaration (line 15)

Six findings. The tests check the SARIF reader against what the same run's
stderr says, parsed by the text parser, not against the SARIF reader's own
output. `Exiting due to 6 warning(s)` is a seventh SARIF result with no
location and is not a finding.

## What is not here

- No captured SARIF carries `fixes`: no Verilator release writes the field
  yet. The reader keeps it verbatim when present; its test uses a hand-built
  `fix` in the SARIF 2.1.0 shape and says so.
- No capture of a document with the missing comma between `tool` and
  `invocations` (reported as verilator/verilator#8469 against 5.052; fixed
  upstream afterwards). All three builds above wrote valid JSON for this
  design. The reader's test for that shape deletes the comma from a real
  document.

## Tests

- `test/services/engines/verilator/verilator_sarif_parser_test.dart`: the
  reader against each capture, offline.
- `test/services/engines/verilator/verilator_engine_sarif_test.dart`: the
  engine's output modes against scripted processes.
- `test/services/engines/verilator/verilator_sarif_live_test.dart` (tagged
  `oss-cad-live`; set `OSS_CAD_SUITE`): the real engine over a real Verilator,
  stderr channel against SARIF channel, against the answer above.
