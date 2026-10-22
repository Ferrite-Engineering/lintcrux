# Flow SARIF fixtures: provenance

SARIF 2.1.0 written by the suite's flow writer (`FlowSarifWriter` in the
`crux_flow` package of `crux-shared`) from real place-and-route reports, kept
here to prove LintCrux reads it with no flow-specific code. LintCrux holds no
code for this format; the fixtures only pin what its existing SARIF import does
with it.

Licence: Apache-2.0 (the suite's own output; `path_adder.v` is the suite's own
design).

## Inputs

- `crux-shared` at `9c69a70`, the pin this repository carries.
- The package's own test fixtures at that commit, under
  `packages/crux_flow/test/fixtures/`: `nextpnr/<case>/report.json` (nextpnr
  `--report --detailed-timing-report`, OSS CAD Suite tag `2026-10-21`, nextpnr
  0.11.1-77-g6b438a1c, run at 1000 MHz so timing is violated) and
  `elaboration/path_adder.json` (Yosys 0.70+186 elaboration of `path_adder.v`).
  Their own provenance is that directory's `PROVENANCE.md`.
- `path_adder.v` here is `nextpnr/rtl/path_adder.v` from the same fixtures,
  unedited. The SARIF locations are relative to it.

## Command

A throwaway Dart program outside this repository (not committed) read each
report with `NextpnrReportReader`, a `RtlRegisterResolver` over the
elaboration, and wrote `FlowSarifWriter(toolVersion: '1.2.0').nextpnr(...)`
encoded with `FlowSarifWriter.encode`:

| File | From |
|---|---|
| `path_ice40_violated.sarif.json` | `nextpnr/path_ice40_violated/report.json` |
| `path_ecp5_violated.sarif.json` | `nextpnr/path_ecp5_violated/report.json` |
| `path_gowin_violated.sarif.json` | `nextpnr/path_gowin_violated/report.json` |
| `path_gatemate_violated.sarif.json` | `nextpnr/path_gatemate_violated/report.json` (GateMate cell names are opaque, so the finding anchors on the statement, not the declaration) |
| `path_ice40_met.sarif.json` | `nextpnr/path_ice40_met/report.json` (12 MHz: meets timing, no results) |
| `clock_no_path.sarif.json` | a hand-built report with one failing clock and no path, for the `flow/clock-constraint` rule |

Captured 2026-10-21. No machine paths: every URI is relative to `SRCROOT`
(`test/static/fixture_host_path_test.dart` guards this).

## Where the expectations come from

`expected.json` is written by hand and never from LintCrux's importer output:

- Lines and columns: from the text of `path_adder.v` (`sum_q` is declared on
  line 12 at column 14; for GateMate the statement `sum_q <= src_a + src_b` on
  line 16, expression at column 14; the path starts are the `src_a` and
  `src_b` declarations on lines 10 and 11). The test finds them by matching
  the RTL text, not by number.
- Rule ids, levels, messages, fingerprints: read from each SARIF file with
  `jq` (`.runs[0].results[]`), checked against SARIF 2.1.0: `ruleId` (3.27.5),
  `level` (3.27.10, `warning`), `message.text` (3.11), `locations` and
  `relatedLocations` (3.27.12, 3.27.22), `partialFingerprints` (3.27.17).
- Severity and engine id: LintCrux maps SARIF `warning` to its warning
  severity and takes the lowercased `tool.driver.name` as the engine id, as its
  SARIF import documents.

## What this pins

- Findings land on the right file and line; rule ids and levels map as
  LintCrux maps SARIF.
- LintCrux reads no `partialFingerprints`: they survive in `Violation.raw`
  only. Its baseline matches on rule id, project-relative path and message, so
  the messages carry registers and clocks and no numbers; a rerun whose
  numbers differ still matches its baseline.
- Nothing in any file claims signoff: results are findings, at warning level.
