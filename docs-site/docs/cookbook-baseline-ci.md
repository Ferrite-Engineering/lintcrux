# Gate CI on new violations

A legacy codebase has thousands of findings nobody is going to fix today — but you still want to stop *new* ones from sneaking in. This recipe sets a baseline of the accepted state and wires a CI gate that fails only on findings you introduce, then surfaces them right in the pull request.

- **Goal:** A CI job that passes on legacy violations but fails the moment a change adds a new one, with findings annotated in the pull-request diff.
- **Time:** About 10 minutes.
- **Tier:** <span class="tier tier-pro">Pro</span> to set the baseline; the `--fail-on-new-violations` gate that reads it is free.
- **You will use:** [Baselines & deltas](baselines.md) and [Exports & CI](exports-and-ci.md).

## Steps {#steps}

1. **Lint the accepted state.**

    Check out the commit you want to accept (typically main), open the project, and let the engines run.

2. **Set the baseline.**

    Choose `Tools → Set Baseline from Current Run…` and confirm. LintCrux writes `.lintcrux-baseline.json` in the project root, fingerprinting each finding by rule, project-relative file and message — not line number, and not where the checkout lives — so unrelated edits do not look new and the baseline matches in CI. Every finding no waiver or pragma suppresses is frozen, whatever the table's filters show. From a script, `lintcrux-pro baseline set project.lintcrux` runs the engines and freezes the same set.

3. **Commit the project and baseline.**

    Add `project.lintcrux` and `.lintcrux-baseline.json` to the repository so CI lints exactly what you do and shares the same reference.

4. **Add the headless gate to CI.**

    In your pipeline, run `lintcrux project.lintcrux --fail-on-new-violations --export sarif --out lint.sarif`. The job exits `2` only when the change introduces a violation that is not in the baseline. Add `--engine verilator` (repeatable) to pin the gate to the engines your runner image actually installs.

5. **Branch on the exit code.**

    Do not just test for non-zero: `3` means LintCrux itself failed — an engine missing or crashed — and reporting that to your team as an RTL defect wastes an afternoon. The [CI integration cookbook](cookbook/ci-integration.md) has a copy-pasteable job that handles each code.

6. **Upload SARIF to GitHub.**

    Pass `lint.sarif` to the GitHub code scanning upload step. Findings appear as annotations directly on the pull-request diff. You can also link `https://app.lintcrux.app/?sarif=<url>` from the job summary for a sortable table with no install.

7. **Check the gate locally.**

    Before relying on it, open `Tools → View Baseline Diff…` on a feature branch and confirm the **New** section matches what the CI gate would flag.

## Where to go next {#next}

Re-baseline after a big cleanup with `Tools → Clear Baseline`, then set a fresh one (`lintcrux-pro baseline clear` and `baseline set` do the same from a script). To see counts move release over release, add `lintcrux-pro push-trends project.lintcrux` to the same job and follow [Track regressions over time](cookbook-track-regressions.md).
