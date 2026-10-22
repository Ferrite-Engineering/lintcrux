# Opening Flow SARIF, from LintCrux 1.2

SimCrux's implementation-flow tooling can write a place-and-route run's timing
findings as SARIF. LintCrux opens that file like any other SARIF report, with no
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

## Re-imports and baselines {#baselines}

Importing the same file again replaces the findings the report holds, so the
count stays the same. A [baseline](baselines.md) taken from one run matches a
rerun whose delays and frequencies differ, because it matches on rule id,
project-relative path and message, and the message holds no numbers. A run of a
different design, with different register and clock names, is a different
finding. LintCrux reads no `partialFingerprints`; the flow writer's own endpoint
fingerprint stays in the finding's raw SARIF.
