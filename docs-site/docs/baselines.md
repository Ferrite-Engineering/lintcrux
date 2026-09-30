# Baselines & deltas <span class="tier tier-pro">Pro</span>

A baseline freezes today's violations as the accepted state of the design. Every later run is then classified against it — what is new, what persists, what was fixed — so you can make progress on a large legacy codebase without rewriting it first, and gate CI on new findings only.

## Setting a baseline {#set}

1. **Run the lint you want to accept.**

    Run all engines (++f5++) on the commit you want to treat as the accepted state — typically your main branch.

2. **Capture the baseline.**

    Choose `Tools → Set Baseline from Current Run…`, or click the set-baseline button in the table's action row. A confirmation says how many violations will be frozen. LintCrux writes `.lintcrux-baseline.json` in the project root. Each violation is recorded by a fingerprint of its rule, file and message that **excludes the line number**, so inserting a line above a finding does not make it look new. The file is taken relative to the project root, so the baseline matches wherever the project is checked out — a teammate's clone, a CI runner, a Windows machine.

    The baseline holds every violation of the run that no waiver or pragma suppresses, whatever the table's filters, filter preset or view mode are showing — a filter left on does not leave the hidden violations out. From a script, `lintcrux-pro baseline set project.lintcrux` runs the engines and freezes the same set.

3. **Commit the baseline.**

    Check `.lintcrux-baseline.json` into git so the whole team and your CI share the same reference. Baseline changes are also recorded in `.lintcrux-baseline.audit.jsonl`.

A baseline file written by an earlier LintCrux (schema version 1, whose fingerprints used absolute paths) is upgraded when it is read — every entry recorded the file, rule and message the new fingerprint needs — and is saved in the new format the next time the baseline is written. An older LintCrux refuses a new-format file with an error rather than treating every finding as new.

## Delta classification {#delta}

With a baseline set, every run classifies each violation into one of three buckets:

- **New** — present now, absent from the baseline. This is what you act on.
- **Persisting** — present in both; accepted legacy noise.
- **Resolved** — in the baseline, gone now; progress.

## The baseline diff {#diff}

Open `Tools → View Baseline Diff…`, or click the baseline chip (*Baseline: date · N frozen*) in the table's action row, to see the three buckets on one screen — **New**, **Persisting** and **Resolved**, each with its count. **Export as JSON…** copies the whole delta to the clipboard as JSON — handy for dropping the new findings into a review comment or the resolved list into a status update.

## The table view-mode toggle {#viewmode}

The table's action row has a view-mode toggle so you can stay in your normal workflow: **All violations**, **Only new** or **Only resolved**. The last two need an active baseline. Combined with the built-in *New Violations* filter preset, this makes "show me only what I introduced" a one-click view.

## Clearing a baseline {#clear}

When the baseline no longer reflects reality — after a big cleanup, or a new release line — choose `Tools → Clear Baseline` or the clear button in the action row. The clear is recorded in the baseline audit trail, and the table reverts to showing all violations unclassified until you set a new one. From a script, `lintcrux-pro baseline clear project.lintcrux` does the same.

## Gating CI on new violations {#ci}

The whole point of a baseline is the CI gate. In headless mode, pass `--fail-on-new-violations`:

```bash
lintcrux project.lintcrux --fail-on-new-violations
```

The run exits `2` only if it introduces a violation that is not in the baseline. Persisting legacy findings do not block the build, so your team can land work while still being held to account for anything new. `--baseline <path>` points at a baseline somewhere other than `.lintcrux-baseline.json` in the project root. The full CI setup is on [Exports & CI](exports-and-ci.md).

Writing a baseline is a Pro feature; **reading one is not**. The free `lintcrux` binary runs the gate. With no baseline file present it still runs — it treats every violation as new and exits `2`, with a note saying where it looked. Strict, not broken. A baseline that exists but cannot be parsed exits `3`: a gate that cannot read its baseline must not wave the build through.

Before you push, `Tools → View Baseline Diff…` shows which findings the gate will flag.

!!! note "Next steps"
    Put it together end to end in the [Gate CI on new violations](cookbook-baseline-ci.md) recipe, and watch the count move over time with [Trends & regressions](trends.md) <span class="tier tier-pro">Pro</span>.
