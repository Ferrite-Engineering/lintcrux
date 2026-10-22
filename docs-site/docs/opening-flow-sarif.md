# Opening Flow SARIF, from LintCrux 1.2

SimCrux's implementation-flow tooling can write a place-and-route run's timing
findings, and (from LintCrux 1.2) a LibreLane run's [physical findings](#physical),
as SARIF. LintCrux opens that file like any other SARIF report, with no
setup: choose **Import SARIF report…** (on the `File` menu, the toolbar and the
welcome screen; see [Exports & CI](exports-and-ci.md)) and pick the file. The
findings appear in the same violations table, offline, with no engines installed.

Findings are from one run. They are not a statement that a design is ready for
anything.

## Making the file {#making}

In SimCrux 1.2, either of these writes it:

```bash
simcrux flow gate runs/blinky_ice40/simcrux-20261021T120000Z --sarif flow.sarif
simcrux flow export runs/blinky_ice40/simcrux-20261021T120000Z --format sarif --out flow.sarif
```

Give either command a LibreLane run directory (`runs/<tag>`) instead and the
file holds that run's checks.

See [SimCrux's CI gate for implementation runs](https://docs.simcrux.app/flow-ci).

## What you see {#what}

For a run that missed its timing constraint:

- One finding for the worst path, rule `flow/timing-path`, severity **warning**,
  engine `edacrux flow`. The message reads "The worst path from `src_a` to
  `sum_q` misses the constraint of clock `<clock>`." It carries no frequency or
  delay, so the same finding matches itself from one run to the next.
- A report that names a missed clock but no path gives `flow/clock-constraint`
  instead, with no file.
- The finding sits in your RTL file, on the declaration of the path's end
  register or, where the flow could name it, on the statement that assigns it.
  Its related location is the declaration of the path's start register. Open the
  project's sources first so the locations resolve.
- A run that met its constraints imports with no findings.

All four FPGA families SimCrux runs with nextpnr (iCE40, ECP5, Gowin and
GateMate) produce the same shape.

## Physical findings from LibreLane {#physical}

From LintCrux 1.2, the same import opens the physical findings of a LibreLane
run: design rule checks, layout-versus-schematic (LVS) and antenna. SimCrux
writes them with the same command as the timing findings, from a LibreLane
3.0 run directory on the open PDKs it reads (sky130A, gf180mcuD and
ihp-sg13g2).

These findings are about the layout, not about a line of your RTL, so they have
no file and no line. LintCrux shows each one with its rule id and the tool
(engine `edacrux flow`), and says **No source location** where the file would
be. The Line column is blank, Enter and double-click open nothing, and the
Details pane's Location section says the same. They are never placed on a line
of one of your source files.

| Rule | What it is | Severity |
|---|---|---|
| `flow/drc` | Design rule violations: LibreLane's routing check, Magic and KLayout | warning |
| `flow/lvs` | The layout does not match the circuit it was built from | warning |
| `flow/antenna` | Nets over their antenna ratio, or antenna violations the router reports | warning |
| `flow/timing-check` | A setup, hold, slew or capacitance check with no path to point at | warning |

- A check LibreLane is configured only to warn about (for example routing DRC
  with `ERROR_ON_TR_DRC` off) stays a **note**, not a warning.
- The message names the check ("LibreLane reports Magic design rule violations
  in this run.") and holds no count, so a baseline still matches a rerun. The
  count, the corners and whether LibreLane enforces the check are in the
  finding's raw SARIF.
- A check that did not run is absent. On gf180mcuD, KLayout DRC is skipped
  unless the run sets a DRC runset, and then there is no `flow/drc` finding
  from KLayout; an absent check is not a zero.
- Antenna violations are reported even though LibreLane itself exits 0 for them.
- To see where a violation is, open the run's layout in KLayout; the markers
  are in the run's DRC reports.

These are findings, not signoff. They report what one run's checks found; they
do not say the layout is clean or manufacturable, and a run with no findings
here has not been signed off by anything in the suite.

## Re-imports and baselines {#baselines}

Importing the same file again replaces the findings the report holds, so the
count stays the same. A [baseline](baselines.md) taken from one run matches a
rerun whose delays and frequencies differ, because it matches on rule id,
project-relative path and message, and the message holds no numbers. A run of a
different design, with different register and clock names, is a different
finding. LintCrux reads no `partialFingerprints`; the flow writer's own endpoint
fingerprint stays in the finding's raw SARIF.
