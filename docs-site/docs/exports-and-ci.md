# Exports & CI

LintCrux is built to live in your pipeline. It exports to the formats your tools already read, runs headless with meaningful exit codes, and on Pro applies your managed waivers in CI, caches runs in the desktop app, and applies Verible's automatic fixes. This page covers the export formats and a complete CI setup; the [command-line reference](cli/invocation.md) and the [CI integration cookbook](cookbook/ci-integration.md) go deeper.

## Export formats {#exports}

| Format | What it is for |
|---|---|
| SARIF 2.1.0 | The interchange format code-scanning tools ingest: one SARIF run per engine. Upload it to GitHub code scanning and findings annotate the pull-request diff. |
| JSON | The structured run for your own tooling: an array with one object per violation — `engineId`, `ruleId`, `severity`, `message`, `location`, `relatedLocations`, `suppressed`, and the engine's `raw` payload when present. |
| CSV | A flat table for spreadsheets and quick pivots, with the columns `severity,engine,rule,file,line,column,message,suppressed`. |
| HTML | A self-contained report with sortable column headers, severity filter chips and severity-colored cells. No external scripts, so the file works offline — attach it to a build or email it to a reviewer. |

**On desktop**, the four commands are `File → Export Violations as SARIF…`, `… as JSON…`, `… as CSV…` and `… as HTML…`, also grouped under the toolbar's **Export Report** button. They write **the rows currently visible in the active tab** — your severity, engine and text filters apply, and suppressed violations (hidden from the table) are left out.

**The headless binary** exports with `--export <format> --out <path>`, or `--sarif <path>` for short. It writes **every** violation from the run — there are no filters there — and shapes SARIF for code-scanning upload: paths relative to the project root with a declared `%SRCROOT%` base, and a stable `automationDetails.id` per project and engine. See [SARIF output](cli/invocation.md#sarif-output).

In both SARIF exports a suppressed violation carries a SARIF `suppressions` entry: kind `inSource` for an inline pragma, `external` for a managed waiver <span class="tier tier-pro">Pro</span>, status `accepted`, and the waiver's reason as the justification. Suppressed findings do not affect the exit code; the marker is what lets a consumer tell a waived finding from an open one. Whether a code-scanning service hides suppressed results is up to that service.

## Headless CI runs {#headless}

The `lintcrux` binary runs without a window. It loads a project, runs the configured engines, applies severity overrides, inline-pragma waivers and the baseline, writes an export if asked, and exits with a code your pipeline can branch on. A typical step is one of:

- `lintcrux project.lintcrux` — run all configured engines and print the findings and a summary. Exits `0`: a bare run is a report, not a gate.
- `lintcrux project.lintcrux --exit-code` — exit `1` on any unwaived finding.
- `lintcrux project.lintcrux --fail-on-new-violations` — exit `2` only on findings not in the [baseline](baselines.md).
- `lintcrux project.lintcrux --export sarif --out lint.sarif` — emit SARIF for upload.

The exit codes are disjoint on purpose. Most lint binaries exit non-zero *because* they found violations — `verible-verilog-lint` does exactly that — so "non-zero" alone tells you nothing about whether the tool worked. LintCrux keeps the two apart:

| Code | Meaning |
|---|---|
| `0` | Clean — or findings present with no gate requested. |
| `1` | `--exit-code` was passed and findings remain. |
| `2` | `--fail-on-new-violations` was passed and a finding is absent from the baseline. |
| `3` | **The run itself failed** — an engine died, timed out, or was not installed; the project file could not be loaded (unparseable, no sources, or a listed source missing); the `--config` overlay was malformed; the baseline was corrupt; or the export could not be written. Whatever count was printed is a partial result. |
| `4` | Returned only by `lintcrux-pro`, when an organization's signed `ciGateThreshold` is exceeded <span class="tier tier-enterprise">Enterprise</span> — see [Administration](administration.md#ci-gate). |
| `5`, `6` | Returned only by `lintcrux-pro push-trends` after a clean lint, when the shared team database was unreachable (`5`, retry) or refused the schema (`6`, do not retry) <span class="tier tier-enterprise">Enterprise</span> — see [Team database](team-database.md#ci). |
| `64` | Bad command line — including a positional argument LintCrux cannot use, or a path that does not exist. |
| `65` | `--import-filelist` / `--import-edam` could not convert the input file. |

A run where one engine died and another found violations reports `3`, not `1`. The count cannot be trusted, and reporting a clean bill of health from a broken run is the failure mode the whole design exists to prevent — which is also why a missing engine binary fails the run by default rather than quietly running fewer engines.

!!! note "Getting the binary"
    Per-platform archives ship alongside each desktop release at `https://updates.lintcrux.app/<version>/lintcrux-cli-<version>-<platform>.<ext>`, or build the binary from an open-core checkout with `tool/build_cli.sh`. Pin the version — there is deliberately no `latest` alias, so a runner image cannot silently change linter versions between builds. See [Getting the binary](cookbook/ci-integration.md#getting-the-binary).

## Managed waivers in CI <span class="tier tier-pro">Pro</span> {#waivers-in-ci}

`lintcrux-pro`, the Pro build of the same binary, takes the same flags and returns the same exit codes, and also applies the project's committed `.lintcrux-waivers.json` — the [managed waivers](waivers.md) your team records in the app — so a waived finding does not fail the gate:

```bash
lintcrux-pro project.lintcrux --fail-on-new-violations
```

It applies the file when the licence the run resolved is Pro, EDU or Enterprise; a build agent supplies one with `--license-file` or `LINTCRUX_LICENSE_FILE` (see [the licence a CI agent runs as](team-database.md#ci-license)). Without one the file is not applied: the findings it waives are reported and count toward `--exit-code` and `--fail-on-new-violations`, and one line on stderr says why:

```
lintcrux-pro: rtl/.lintcrux-waivers.json was not applied: managed waivers require a LintCrux Pro license, so this run reports the violations it waives (inline pragma waivers still apply). See https://lintcrux.app/pricing
```

Inline pragma waivers apply at every tier, in both binaries.

## Setting up a CI gate {#ci-setup}

1. **Commit your project and baseline.**

    Check `project.lintcrux` and `.lintcrux-baseline.json` into the repository so CI lints exactly what your team lints.

2. **Pin the engines the job actually has.**

    A runner image usually installs one or two engines while the committed project enables everything the team uses locally. Say which ones gate the build with `--engine verilator` (repeatable), or keep the project file untouched and put the narrowing in a `--config` overlay — a partial `.lintcrux` document whose present keys replace the project's. A malformed overlay fails the run rather than being ignored.

3. **Run LintCrux headless in the job.**

    Invoke `lintcrux project.lintcrux --fail-on-new-violations --export sarif --out lint.sarif`. The job fails if the change introduces a new violation; legacy findings do not block it.

4. **Branch on the exit code, do not just test for non-zero.**

    Otherwise a missing Verilator install is reported to your team as an RTL defect. The [CI integration cookbook](cookbook/ci-integration.md) has a copy-pasteable GitHub Actions and GitLab CI job that does this correctly.

5. **Upload the SARIF.**

    Hand `lint.sarif` to GitHub code scanning. Findings annotate the pull-request diff inline. Paths are emitted relative to the project root with a declared `%SRCROOT%` base, which is what makes the annotations land — absolute paths upload successfully and then annotate nothing. GitLab's security widgets expect GitLab's own report schema rather than SARIF, so keep the file as a job artifact there.

6. **Push trends from CI <span class="tier tier-pro">Pro</span>.**

    Add `lintcrux-pro push-trends project.lintcrux` to record the run in the [trend history](trends.md), so the charts reflect CI runs, not just local ones. `--db <path>` names the SQLite trend database to write; with `LINTCRUX_TEAM_DB_URL` set, the run is also pushed to the Enterprise [team database](team-database.md#ci). A failed run pushes nothing — a partial run recorded as a data point would read as a fake improvement.

!!! tip "Sharing a report with a human"
    For a reviewer who does not want to install anything, link `https://app.lintcrux.app/?sarif=<url-encoded-url>` from the job summary and the SARIF renders as a sortable table in the browser. The host serving the file must allow the viewer's origin via CORS. See [the web viewer](user-guide/web-mode.md).

## Import a SARIF report on the desktop {#import-sarif}

A CI job produces a SARIF file; the desktop app can read it back. **Import SARIF report…** — on the `File` menu, on the toolbar, and on the welcome screen — opens a file picker for a `.sarif` or `.json` document and renders its violations in the **Imported SARIF report** viewer. Results that carry an accepted SARIF suppression are treated as waived, as they are in a live run. It is the same virtualized violation table you use for live runs, so a report with thousands of findings scrolls smoothly, but nothing re-runs: you are reviewing exactly what CI recorded, offline, with no engines installed. **Back to workspace** returns to your projects, and **Import another…** swaps in a different report.

## Lint run caching <span class="tier tier-pro">Pro</span> {#cache}

Pro adds a lint result cache at `.lintcrux/cache.db` in the project root. When the inputs to an engine run — the files, the project and engine configuration (including a project-root `.rules.verible_lint` or `.svlint.toml`), and the engine binary's version — are unchanged since the last run, LintCrux serves the cached result instead of re-running the engine. (CDC is never cached; see [Clock-domain crossings](cdc.md#running).)

The cache is part of Pro. Without a Pro licence every run executes every engine and nothing is written to `.lintcrux/`; a project that already has a cache from a licensed session says so in the banner above the violation table. The cache is the desktop app's: the command-line binaries never cache, because a CI job starts from a fresh checkout where a cache would never hit.

`Settings → Lint Cache` has **Enable lint result cache**, a **Maximum cache size** in MB, **Cache statistics** (cached entries, disk usage, hits, misses, hit rate and estimated time saved), **Show invalidations log**, and **Clear cache now**. From the `Tools` menu, **Clear Lint Cache…** and **Show Lint Cache Stats…** do the same, and **Run Lint (Bypass Cache)** runs once with the cache ignored in both directions when you want to be certain.

## Verible auto-fix <span class="tier tier-pro">Pro</span> {#autofix}

Many Verible findings come with a machine-applicable fix. Pro surfaces them through a review-then-apply flow:

1. **Run a dry-run.**

    Choose `Tools → Run Verible Auto-Fix Dry-Run…`, click **Run Verible dry-run** in the table's action row, or right-click a Verible violation and choose **Suggest fix with Verible** to scope the dry-run to that file and rule. LintCrux runs Verible's fixer without writing anything and opens the **Verible auto-fix review** dialog with the proposed changes.

2. **Choose and apply fixes.**

    Filter the proposals by confidence, rule or file, select them individually or with **Select all**, **Select all high-confidence** or **Select none**, and press **Apply N selected**. Nothing is written until you do; an apply summary reports what changed.

The Verible binary used for fixes and the auto-fix options — running a dry-run automatically after every lint, pre-selecting only high-confidence proposals, and preserving the original file as `.verible-backup` — are in `Settings → Verible`. When no Verible binary is found, the dry-run button is disabled and points you there.

!!! note "Next steps"
    Share trend history across the team with the [team trend database](team-database.md) <span class="tier tier-enterprise">Enterprise</span>, or follow the [Gate CI on new violations](cookbook-baseline-ci.md) recipe end to end.
