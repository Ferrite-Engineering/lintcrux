# Flow SARIF fixtures, physical findings: provenance

SARIF 2.1.0 written by the suite's flow writer (`FlowSarifWriter.librelane` in
the `crux_flow` package of `crux-shared`) from captured LibreLane runs. They
pin what LintCrux does with findings that have no source location: a layout
check (design rules, LVS, antenna) is about the layout, not about a line of the
design, so the writer gives it no `locations`.

Licence: Apache-2.0 (the suite's own output).

## Inputs

- `crux-shared` at `928fcf1`, the pin this repository carries.
- The LibreLane 3.0.16 run directories under `verification/fixtures/flow/librelane/3.0.16/<case>/run`
  of the `simcrux` repository (commit `115cbb9b`; its own `PROVENANCE.md`
  there has the tools, PDKs and the case configurations). Captured 2026-10-22,
  LibreLane tag commit `01ddb25e4424f6f5aaf6b951b14a2b6fdcf737c0`.

## Command

A throwaway Dart program outside this repository (not committed) read each run
with `LibreLaneReaders.standard().read(<run>)` and wrote
`FlowSarifWriter(toolVersion: '1.2.0').librelane(reading)` encoded with
`FlowSarifWriter.encode`:

| File | From | Class |
|---|---|---|
| `sky130A_drc.sarif.json` | `sky130A_drc` | routing DRC (44, a note: `ERROR_ON_TR_DRC` is false), Magic DRC (161), KLayout DRC (24), LVS (10) |
| `sky130A_antenna.sarif.json` | `sky130A_antenna` | one antenna violation (route count 1, violating nets 1), no checker enforces it |
| `gf180mcuD_met.sarif.json` | `gf180mcuD_met` | KLayout DRC did not run (`KLAYOUT_DRC_RUNSET` null): no `flow/drc` result; one waived max-capacitance note |
| `sky130A_met.sarif.json` | `sky130A_met` | every check clean: no results |

No machine paths and no locations at all.

## Where the expectations come from

`expected.json` is written by hand and never from LintCrux's importer output:

- Counts: each run's `final/metrics.json` (`route__drc_errors` 44,
  `magic__drc_error__count` 161, `klayout__drc_error__count` 24,
  `design__lvs_error__count` 10, `route__antenna_violation__count` 1,
  `antenna__violating__nets` 1, `design__max_cap_violation__count` 1 on
  gf180mcuD) and the `N ... errors found. - deferred` lines of the DRC run's
  `error.log` (161, 24, 10).
- Waived versus enforced: `resolved.json` `ERROR_ON_TR_DRC` (false in
  `sky130A_drc`); `klayout__drc_error__count` absent from the gf180mcuD
  metrics.
- Rule ids, levels, messages: read from each SARIF file with `jq`
  (`.runs[0].results[]`), checked against SARIF 2.1.0: `ruleId` (3.27.5),
  `level` (3.27.10, `warning` for an enforced or unchecked failure, `note` for
  one LibreLane is told only to warn about), `message.text` (3.11),
  `partialFingerprints` (3.27.17).
- Severity and engine id: LintCrux maps SARIF `warning` and `note` to its
  severities and takes the lowercased `tool.driver.name` (`edacrux flow`) as
  the engine id.

## What this pins

- A result with no `locations` is imported, with its rule id and the tool, and
  is not placed on any file: `location.file` is empty. The table, the
  screen-reader label and the Details pane say "No source location" for it
  (`test/features/violations/widgets/location_less_finding_test.dart`).
- A check that did not run is absent from the file, never a zero.
- Messages carry no numbers: a rerun with different counts matches its
  baseline.
- Nothing in any file claims signoff: results are findings.
