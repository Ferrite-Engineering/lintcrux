# Cookbook

The rest of these docs explain what each feature *is*. The Cookbook shows you how to put the features together to get something done. Each recipe is a complete task — start with a project, end with a result — written as numbered steps you can follow at the keyboard. They are short on purpose: a recipe is a worked example, not a manual.

!!! tip "No project handy?"
    Every recipe works against RTL you already have, but if you just want to follow along, take any open-source Verilog or VHDL repository: create a project with **New Project…** on the welcome screen, add the sources with ++cmd+shift+o++ / ++ctrl+shift+o++, and the engines run. Even a clean design produces style notes worth triaging.

## Recipes {#recipes}

- [Triage a run & waive false positives](cookbook-triage-and-waive.md) — run every engine, sort and filter the table, inspect a finding, and waive false positives with a reason. **~10 min · Free + Pro**
- [Lint a FuseSoC core](cookbook-fusesoc.md) — let FuseSoC resolve the dependency closure, import the EDAM it generates, and go from `.core` file to SARIF with nothing described by hand. **~10 min · Free**
- [Gate CI on new violations](cookbook-baseline-ci.md) — set a baseline, fail CI only on new findings, and export SARIF so violations annotate your pull requests. **~10 min · Pro to set the baseline, free to gate**
- [Track regressions over time](cookbook-track-regressions.md) — open a trend chart, catch a spike, find the rule that caused it, triage, and watch the count recover. **~8 min · Pro**
- [Configure which engines run](cookbook-configure-engines.md) — choose the engines, set their binaries and options, and re-run to see the difference. **~5 min · Free**
- [CI integration in depth](cookbook/ci-integration.md) — copy-pasteable GitHub Actions and GitLab CI jobs, the exit-code contract, overlays, baselines and SARIF upload. **Free**

## How each recipe is laid out {#how-recipes-work}

Every recipe opens with a short summary — the goal, a rough time, the tier you need, and the features it exercises — followed by numbered steps. Keyboard shortcuts are written macOS first (++cmd++), with the ++ctrl++ equivalent for Linux and Windows. Where a step leans on a feature covered in depth elsewhere, it links straight to that page so you can go deeper without leaving the workflow.

!!! note "More on the way"
    This is the opening set of recipes. If there is a workflow you keep repeating and would like written up — a migration from a commercial lint tool, a tape-out sign-off pass, a new-repo onboarding checklist — [tell us](mailto:support@ferriteengineering.com).
