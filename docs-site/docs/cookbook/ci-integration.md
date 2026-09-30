# CI integration cookbook

LintCrux runs headless. `bin/lintcrux.dart` builds to a standalone
binary that loads a project, runs the configured engines, applies
severity overrides, inline-pragma waivers and the baseline, writes
SARIF, and exits with a code your pipeline can branch on.

This page is a worked pipeline. For the full flag and exit-code
reference, see [CLI invocation](../cli/invocation.md).

## The 30-second version

```bash
# lint and fail on any finding
lintcrux project.lintcrux --exit-code

# lint, fail only on findings the baseline does not contain,
# and emit SARIF for GitHub code scanning
lintcrux project.lintcrux \
  --fail-on-new-violations \
  --export sarif --out lint.sarif
```

## Getting the binary

Per-platform archives ship alongside each desktop release, at
`https://updates.lintcrux.app/<version>/lintcrux-cli-<version>-<platform>.<ext>`
(`linux-x64.tar.gz`, `macos-arm64.zip`, `windows-x64.zip`); each holds
the `lintcrux` executable and the `LICENSE`. The current version is the
`latest.version` field of `https://updates.lintcrux.app/manifest.json`.
Pin the version — there is deliberately no `latest` alias, so a CI image
cannot silently change linter versions between runs.

Or build it from a checkout of the LintCrux open-core repository, using
the `dart` that ships with the Flutter SDK:

```bash
git submodule update --init --recursive
flutter pub get
tool/build_cli.sh          # -> build/cli/bundle/bin/lintcrux
```

The executable is self-contained; copy it onto your `PATH`.

## The exit-code contract

This is the part worth internalizing, because it is what makes the gate
usable:

| Code | Meaning |
| --- | --- |
| `0` | Clean — or findings present with no gate requested. |
| `1` | `--exit-code` was passed and findings remain. |
| `2` | `--fail-on-new-violations` was passed and a finding is absent from the baseline. |
| `3` | **The run itself failed.** An engine died, timed out, or was not installed, or the project file could not be loaded. |
| `4` | `over-threshold` — the organization's signed `ciGateThreshold` is set and the surviving count exceeds it. **Enterprise, and only from `lintcrux-pro`**: the open-core binary never populates a threshold. Outranks `1` and `2`. |
| `64` | Bad command line, or a path that does not exist. |
| `65` | `--import-filelist` / `--import-edam` could not convert the input file. |
| `130` | **Cancelled** — `SIGINT` (`128 + 2`). A developer pressing Ctrl+C, and what GitHub Actions and GitLab send when a job is cancelled. |
| `143` | **Terminated** — `SIGTERM` (`128 + 15`). A runner timeout, or a job killed by the scheduler. |

`lintcrux-pro push-trends` adds `5` (shared database unreachable — retry is reasonable) and `6` (the run cannot be recorded in the shared schema — never retry); see [Team trend database](../team-database.md#ci). They are clear of every code above on purpose.

**`130` and `143` are why the `case` below has no bare `*)` failure branch.** A cancelled job exits `130`; matched by a catch-all that says "usage error", a cancellation is reported to whoever reads the log as a broken command line, and they go looking for a typo that is not there. Match the codes you handle and say "unexpected" for the rest, with the number in the message.

`3` is the one people forget to handle, and it is the reason the others
are trustworthy. Most lint binaries exit non-zero *because they found
violations* — `verible-verilog-lint` does exactly that — so "non-zero"
alone tells you nothing about whether the tool worked. LintCrux keeps
them separate, and a run where any engine failed reports `3` **even if
other engines found violations**, because a count from a partial run is
not a count.

The practical consequence: a job that treats every non-zero exit as
"lint found something" will report a missing Verilator install as an RTL
defect. Branch on the code.

## Worked example — GitHub Actions

Copy this. It runs as written.

```yaml
name: lint
on: [pull_request]

permissions:
  contents: read
  security-events: write   # required for the SARIF upload

jobs:
  rtl-lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install the lint engines
        run: |
          sudo apt-get update
          sudo apt-get install -y verilator

      - name: Install LintCrux
        env:
          LINTCRUX_VERSION: '0.8.0'
        run: |
          curl -fsSL -o lintcrux-cli.tar.gz \
            "https://updates.lintcrux.app/${LINTCRUX_VERSION}/lintcrux-cli-${LINTCRUX_VERSION}-linux-x64.tar.gz"
          tar -xzf lintcrux-cli.tar.gz
          sudo install -m755 lintcrux /usr/local/bin/lintcrux

      - name: Lint
        id: lint
        run: |
          # GitHub runs `run:` under `bash -e`, so the non-zero exit we
          # care about would abort the step before we could read it.
          set +e
          lintcrux rtl/project.lintcrux \
            --engine verilator \
            --fail-on-new-violations \
            --export sarif --out lint.sarif
          code=$?
          set -e
          echo "code=$code" >> "$GITHUB_OUTPUT"

      - name: Upload SARIF to code scanning
        if: always() && hashFiles('lint.sarif') != ''
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: lint.sarif

      - name: Interpret the exit code
        if: always()
        run: |
          code="${{ steps.lint.outputs.code }}"
          case "$code" in
            0)      echo "::notice::Lint clean." ;;
            1)      echo "::error::Lint violations present."; exit 1 ;;
            2)      echo "::error::This change introduces new lint violations."; exit 1 ;;
            3)      echo "::error::LintCrux itself failed - check the engine setup."; exit 1 ;;
            4)      echo "::error::Over the organization's lint budget (ciGateThreshold)."; exit 1 ;;
            64|65)  echo "::error::LintCrux usage or input error."; exit 1 ;;
            130|143) echo "::warning::Lint was cancelled or terminated (exit $code)."; exit 1 ;;
            *)      echo "::error::LintCrux exited $code, which this job does not know."; exit 1 ;;
          esac
```

Four details that matter:

- **`set +e` around the invocation.** GitHub runs `run:` blocks under
  `bash -e`, so without it the step dies on the very exit code you were
  trying to inspect, and you can never tell `2` from `3`.
- **The failure decision lives in its own step.** That keeps the lint
  step green so the SARIF upload runs, and puts a readable message in
  the log instead of a bare non-zero exit.
- **`if: always()` on the upload.** You want the SARIF *especially* when
  the gate failed — that is the run whose findings a reviewer needs.
- **The catch-all names the number and does not guess.** `64`/`65` are the
  input errors; `130`/`143` are a cancellation. A `*)` that says "usage error"
  turns every cancelled job into a hunt for a typo.

### Without a baseline

Drop `--fail-on-new-violations` and use `--exit-code`; then `2` never
occurs and the `case` collapses to `0` / `1` / `3` plus the cancellation
and catch-all arms. Everything else is identical.

### GitLab CI

```yaml
rtl-lint:
  image: ubuntu:latest
  variables:
    LINTCRUX_VERSION: "0.8.0"
  before_script:
    - apt-get update && apt-get install -y verilator curl
    - curl -fsSL -o lintcrux-cli.tar.gz
        "https://updates.lintcrux.app/$LINTCRUX_VERSION/lintcrux-cli-$LINTCRUX_VERSION-linux-x64.tar.gz"
    - tar -xzf lintcrux-cli.tar.gz && install -m755 lintcrux /usr/local/bin/lintcrux
  script:
    - |
      set +e
      lintcrux rtl/project.lintcrux --engine verilator \
        --fail-on-new-violations --export sarif --out lint.sarif
      code=$?
      set -e
      case $code in
        0)       echo "clean" ;;
        1|2|4)   echo "lint findings"; exit 1 ;;
        3)       echo "LintCrux failed to run"; exit 1 ;;
        64|65)   echo "LintCrux usage or input error"; exit 1 ;;
        130|143) echo "cancelled or terminated (exit $code)"; exit 1 ;;
        *)       echo "LintCrux exited $code, which this job does not know"; exit 1 ;;
      esac
  artifacts:
    when: always
    paths:
      - lint.sarif
```

GitLab's `artifacts:reports:sast` expects GitLab's own security-report
JSON schema, not SARIF, so the job keeps `lint.sarif` as a plain
artifact; convert it first if you want findings in GitLab's security
widgets.

## Pinning the engine set

A CI image usually installs one or two engines, while the committed
`.lintcrux` enables everything the team uses locally. Two ways to
reconcile that, and the choice is a real one:

```bash
# (a) narrow to what is installed - the run is deliberately partial
lintcrux project.lintcrux --engine verilator --exit-code

# (b) tolerate whatever is missing - the run is partial by accident
lintcrux project.lintcrux --allow-missing-engines --exit-code
```

Prefer **(a)**. It states the intent in the command line, so a reviewer
reading the job sees which engines gate the build. **(b)** is for
transitional periods, and it is off by default precisely because a job
that asked for every engine and silently ran zero is a green build that
means nothing. The `cdc` engine runs `yosys`, so on an image without
Yosys both `yosys` and `cdc` are missing — see
[Missing engines](../cli/invocation.md#missing-engines).

You can also keep the project file untouched and put the CI-specific
narrowing in an overlay:

```bash
lintcrux project.lintcrux --config ci/lint-overrides.lintcrux --exit-code
```

```json
{
  "enabledEngineIds": ["verilator"],
  "defines": { "SYNTHESIS": "1" },
  "severityOverrides": { "verilator/UNUSEDSIGNAL": "note" }
}
```

A malformed overlay fails the run rather than being ignored — a job
whose severity overrides silently did not apply reports the wrong
answer.

## Applying your team's managed waivers

Waivers recorded in the desktop app live in `.lintcrux-waivers.json` in
the project root. Commit it, and run the **LintCrux Pro** binary in
place of `lintcrux` — same flags, same exit codes — and a waived
finding does not fail the gate:

```bash
lintcrux-pro rtl/project.lintcrux --fail-on-new-violations
```

Applying managed waivers in CI is part of Pro. Without a Pro licence
the file is not applied, the findings it waives count toward the exit
code, and one line on stderr names the file and the reason. See
[Managed waivers in CI](../exports-and-ci.md#waivers-in-ci), and
[the licence a CI agent runs as](../team-database.md#ci-license) for
how the job supplies one.

## Gating on new violations only

The realistic starting position on an existing codebase is thousands of
findings. Fixing them all before turning on a gate is not going to
happen, so gate on the *delta* instead:

1. Snapshot the current state with **LintCrux Pro**, from any checkout
   of the repository:

    ```bash
    lintcrux-pro baseline set rtl/project.lintcrux
    ```

2. Commit the emitted `rtl/.lintcrux-baseline.json`.

3. Gate with the free binary:

    ```bash
    lintcrux rtl/project.lintcrux --fail-on-new-violations
    ```

The job passes on pre-existing findings and fails (exit `2`) the moment
a change introduces one the baseline does not contain. Matching is by a
fingerprint of `(rule, file, message)` rather than line number, so
adding an import above a violation does not fake a regression. The file
is relative to the project root, so a baseline recorded in
`/Users/alice/src/soc` matches the same findings in
`/home/runner/work/soc/soc`.

Writing a baseline is a Pro feature; reading one is not. With no
baseline file present the gate still runs — it just treats every
violation as new and exits `2`, with a note saying where it looked.
Strict, not broken.

Re-baseline after a cleanup: `lintcrux-pro baseline clear` then
`baseline set` again.

## Recording trends from CI

Local runs alone give a lopsided picture of a codebase's direction.
**LintCrux Pro** can record each CI run into the trend database its
dashboard reads:

```bash
lintcrux-pro push-trends --db "$CI_TREND_DB" rtl/project.lintcrux
```

A run that failed pushes nothing — a partial run recorded as a data
point shows on the dashboard as a fake improvement, which is worse than
a gap.

## Uploading SARIF to GitHub code scanning

`--export sarif --out lint.sarif` produces SARIF 2.1.0 already shaped
for the upload:

- paths are **relative to the project root** with a declared
  `%SRCROOT%` base, so alerts annotate the PR diff. (Absolute paths are
  the classic failure here: GitHub accepts the file and then annotates
  nothing, because no path in the checkout matches
  `/home/runner/work/repo/repo/rtl/top.sv`.)
- `automationDetails.id` is stable across runs, so a re-upload
  supersedes the previous one instead of creating a duplicate category.
- one SARIF run per engine, so a finding's provenance survives.
- waived findings stay in the file, each with a SARIF `suppressions`
  entry (`inSource` for a pragma, `external` for a managed waiver), so
  the upload records what was waived instead of presenting it as open.

## Sharing a report with a human

For a reviewer who does not want to install anything, the read-only web
viewer renders a SARIF file from a URL:

```
https://app.lintcrux.app/?sarif=<url-encoded-https-url>
```

Emit the link into the job summary so a red build has a one-click path
to a sortable table:

```bash
echo "[Open in LintCrux](https://app.lintcrux.app/?sarif=$(
  python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' \
    "$SARIF_URL")" >> "$GITHUB_STEP_SUMMARY"
```

CORS applies: the host serving the SARIF must send
`Access-Control-Allow-Origin` for the viewer origin. See
[The web viewer](../user-guide/web-mode.md).

## Generating the project file from a filelist

If your build already produces a Vivado-style `.f`, you do not have to
hand-maintain a `.lintcrux`. `--import-filelist` resolves nested `-f`
includes, `+incdir+` and `+define+`, writes the project beside the
filelist, prints its absolute path, and then lints it:

```bash
lintcrux --import-filelist build/rtl.f --engine verilator --exit-code
# Imported filelist → /path/to/checkout/build/rtl.lintcrux
```

It exits `65` if the import fails, which doubles as a filelist-health
check. The generated project lists no `enabledEngineIds`, so without
`--engine` every registered engine runs.

## Linting a FuseSoC project (EDAM)

If your design is packaged as FuseSoC `.core` files, let FuseSoC do the
resolution — conditionals, dependency fetching, file staging — and hand
LintCrux the **EDAM** file it generates:

```bash
fusesoc run --target=lint --setup vendor:lib:core
lintcrux --import-edam build/<name>/<flow>/<name>.eda.yml \
  --engine verilator --sarif lint.sarif --exit-code
# Imported EDAM → /path/to/checkout/build/<name>/<flow>/<name>.lintcrux
```

The import carries the resolved source list with per-file languages,
include directories, defines, the toplevel, Verilator options, and any
`.vlt` waiver files (routed to Verilator only). Which FuseSoC core
contributed each file is recorded as `sourceFileProvenance` in the
generated project. Anything the importer skips is reported as a
`lintcrux: warning:` on stderr; a file that cannot be imported at all
exits `65`.

## Keeping CI and developer machines aligned

Rule ids move between engine releases. Pin the engine versions your CI
image installs and use the same versions locally. Check the local one
with the engine's own `--version`, or `Settings → Engines` → **Custom**
→ **Probe**, which shows the version the binary reports. The rule-alias
table absorbs some renames for Pro managed-waiver matching, but it is
not a substitute for pinning.

The CLI and the desktop app share one engine-routing planner, so for the
same project and the same engine versions they report the same
violations. If they disagree, that is a bug worth reporting, not a
configuration difference to work around.
