# CLI invocation

LintCrux ships **two** command-line front doors, and the distinction
matters:

- **`lintcrux` (the headless binary)** — built from `bin/lintcrux.dart`.
  Runs the engines, writes an export, exits with a meaningful code. No
  window, no display server. This is what you put in a pipeline.
- **The desktop app's command line** — every invocation other than
  `--help`, `--version`, a malformed command line (exit `64`) and a
  failed `--import-filelist` / `--import-edam` (exit `65`) opens the GUI.
  Those four print their output and end the process with that code
  (`0` for `--help` and `--version`).

Both share one argument parser, so they accept the same flags and
reject the same typos. The desktop app acts only on `.lintcrux` and
`<design>.crux-project` positionals, `--top`, the `--<engine>-path` overrides, the two import
flags, `--workspace` and `--session`, plus two launch-recovery flags of
its own: `--no-restore` (skip reopening the previous tabs this once)
and `--reset` (clear saved workspace and session state). The run,
export and gate flags below are headless-only. This page documents the
headless binary; see the
[CI integration cookbook](../cookbook/ci-integration.md) for a worked
pipeline.

```
lintcrux [options] [path...]
```

## Building the headless binary

Prebuilt archives ship with each desktop release — see
[Getting the binary](../cookbook/ci-integration.md#getting-the-binary).
To build from source, use the `dart` that comes with the Flutter SDK
(the package's dependency graph includes Flutter, so a standalone Dart
SDK cannot resolve it) and initialise the `crux-shared` submodule first:

```bash
git submodule update --init --recursive
flutter pub get
dart build cli -t bin/lintcrux.dart -o build/cli
# or, equivalently, with the smoke test attached:
tool/build_cli.sh
```

The executable lands at `build/cli/bundle/bin/lintcrux` and runs
standalone — nothing else from the bundle is needed. Copy it onto your
`PATH`.

!!! note "Why `dart build cli` and not `dart compile exe`"
    `dart compile` refuses to run when any package in the resolution
    declares a native build hook, and `objective_c` does — pulled in
    transitively by `path_provider_foundation`, a Flutter plugin the
    *desktop app* needs and the CLI never touches. `dart build cli` is
    the supported replacement.

## Positional arguments

Two input shapes, and they do not mix:

- **A `.lintcrux` project file.** Exactly one per invocation. Relative
  `sourceFiles` and `includePaths` resolve against the *project file's
  own directory*, so `lintcrux rtl/design.lintcrux` works from any
  working directory. A relative `rootPath` in the file is ignored in
  favor of that directory.
- **One or more HDL source files** (`.v`, `.vh`, `.sv`, `.svh`, `.vhd`,
  `.vhdl`). An ad-hoc project is built around them, rooted at their
  common ancestor, with the language inferred from the extensions and
  the top module taken from `--top`.

A positional that is neither is **reported as an error**, never
silently ignored. `lintcrux typo.sv` exits `64` rather than reporting a
clean run over zero files.

## Options

| Flag | Description |
| --- | --- |
| `--top <module>` | Top module / entity. Sets it for an ad-hoc source-file run; overrides the project file's `topModule` when a project is loaded. |
| `--engine <id>` | Run only this engine. Repeatable. One of `verilator`, `verible`, `slang`, `yosys`, `ghdl`, `svlint`, `cdc`. Overrides the project's `enabledEngineIds` for this invocation — the usual shape for a CI image that installs one engine. |
| `--config <path>`, `-c` | Overlay a partial `.lintcrux` document (JSON) on the loaded project. Only the keys present are replaced. See [Config overlay](#config-overlay). |
| `--export <format>` | Write the violations in this format to `--out`. One of `sarif`, `json`, `csv`, `html`. Requires `--out`. |
| `--out <path>`, `-o` | Destination for `--export`. Parent directories are created. |
| `--sarif <out.sarif>` | Shorthand for `--export sarif --out <path>`. |
| `--baseline <path>` | Baseline file for `--fail-on-new-violations`. Defaults to `.lintcrux-baseline.json` in the project root. |
| `--exit-code` | Exit `1` when any non-suppressed violation remains. |
| `--fail-on-new-violations` | Exit `2` when a violation is absent from the baseline. Pre-existing findings do not fail the build. Composes with `--exit-code`. |
| `--allow-missing-engines` | Treat an engine whose binary cannot be found as skipped rather than as a run failure. Off by default — see [Missing engines](#missing-engines). |
| `--quiet`, `-q` | Suppress the per-violation listing; print only the summary. Exit codes are unaffected. |
| `--import-filelist <rtl.f>` | Convert a Vivado-style `.f` filelist into a `.lintcrux` project, print the emitted path, then lint it. Recursive `-f` includes, `+incdir+`, `+define+` and env-var expansion are honored. |
| `--import-edam <design.eda.yml>` | Convert a FuseSoC/Edalize EDAM file into a `.lintcrux` project, print the emitted path, then lint it. Generate the EDAM with `fusesoc run --target=lint --setup <core>`; the file lands in FuseSoC's `build/<name>/<flow>/` directory. Sources, include dirs, defines, toplevel, per-file language, Verilator options and `.vlt` waivers are honored; per-file core provenance is recorded. Non-fatal reader warnings go to stderr. |
| `--verilator-path <path>` | Override the Verilator binary for this run. Same for `--verible-path`, `--slang-path`, `--yosys-path`, `--ghdl-path`, `--svlint-path`. `--yosys-path` sets the binary for both the `yosys` and `cdc` engines; there is no `--cdc-path`. |
| `--workspace <file>` | *Desktop only.* Open a saved multi-tab workspace. |
| `--session <file>` | *Desktop only.* Apply UI state from a session file. |
| `--reset-telemetry-consent` | Testing aid: forget this installation's usage-statistics answer so the first-launch disclosure appears again. Acted on by the desktop app; the headless binary ignores it. |
| `--reset-eula` | Testing aid: forget this installation's acceptance of the End User License Agreement so the agreement is presented again on this launch. Acted on by the desktop app; the headless binary ignores it. |
| `--help`, `-h` | Print the usage block and exit `0`. |
| `--version` | Print the version string and exit `0`. |

## Exit codes

This is the part a pipeline depends on, so it is spelled out in full.

| Code | Label | Meaning |
| --- | --- | --- |
| `0` | `clean` | Nothing to report, **or** findings present with no gate requested. |
| `1` | `violations` | `--exit-code` was passed and at least one non-suppressed violation remains. |
| `2` | `new-violations` | `--fail-on-new-violations` was passed and at least one violation is absent from the baseline. |
| `3` | `run-failed` | An engine failed, timed out, was cancelled, or was unavailable; no engine had a compatible source file; the project file named on the command line could not be loaded (unparseable, no source files, or a listed source file missing); the `--config` overlay was malformed; the baseline was corrupt; or the export could not be written. |
| `4` | `over-threshold` | Never returned by the open-core binary. The Pro/Enterprise `lintcrux-pro` binary returns it when an organization's signed policy file sets a violation ceiling and the run exceeds it. |
| `64` | `usage-error` | Bad flag, `--export` without `--out`, an unknown `--engine` id, no positional argument, an unusable positional argument, or a project or source path that does not exist. |
| `65` | `data-error` | `--import-filelist` could not read or convert the filelist, or `--import-edam` could not read or convert the EDAM file. |
| `130` | — | **Cancelled.** `SIGINT`, reported as `128 + 2` the way a shell expects. Ctrl+C, and what a CI runner sends on a cancelled job. Any engine process still running is reaped first. |
| `143` | — | **Terminated.** `SIGTERM`, reported as `128 + 15`. A runner timeout or a scheduler kill. Same reaping. |

`130` and `143` carry no label on the summary line, because a signalled run is
stopped rather than finished — there is no result to summarise. A pipeline that
branches on the code must handle them explicitly: a catch-all that reads
"usage error" turns every cancelled job into a hunt for a typo. See the
[CI cookbook](../cookbook/ci-integration.md#the-exit-code-contract).

!!! note "A refused policy file is said out loud, and yields no threshold"

    `4` needs a threshold, and a threshold comes from the organization's signed
    `.crux-policy.json`. If that file is found and **refused** — a bad
    signature, an unsigned file reached through `CRUX_POLICY`, a signed file on
    a machine with no organization public key installed, or a world-writable
    well-known path — `lintcrux-pro` prints one line on stderr and applies no
    threshold:

    ```
    lintcrux: the organization policy file was refused (reason=noPublicKey key=none); no ciGateThreshold applies to this run.
    ```

    `reason` is the refusal (`badSignature`, `untrustedUnsigned`,
    `malformedSignature`, `noPublicKey`, `insecurePath`) and `key` is what the
    loader found when it looked for `crux-policy.pub` (`none`, `configured`,
    `malformed`, `unreadable`, `insecure`). Before this line existed, a signed
    file on a runner with no key installed produced no threshold and no output,
    which from the pipeline's side looked exactly like a threshold nobody had
    set. Full reference: [the policy file reference](https://edacrux.app/policy-reference#failures).

Three properties are deliberate:

**A bare run is a report, not a gate.** `lintcrux project.lintcrux` exits
`0` even with violations. You opt into failing with `--exit-code` or
`--fail-on-new-violations`.

**"Findings" and "broken" are different codes.** `verible-verilog-lint`
exits `1` *because* it found violations, which makes a non-zero exit
carry no information. LintCrux separates them: `1`/`2` mean your RTL has
findings, `3` means the linter did not work and whatever count it
printed is a partial result.

**Run failure outranks everything.** A run where one engine died and
another found violations reports `3`, not `1`. The count cannot be
trusted, and reporting `0 violations` from a broken run is the failure
mode this whole layer exists to prevent.

Every summary line ends with its code and label, so a CI log is
self-documenting:

```
lintcrux: my_project: 3 violations (1 error, 2 warning), 2 new, 1 pre-existing [exit 2: new-violations]
```

## Output format

One line per violation, in the shape every editor and log scraper
already knows how to click on:

```
rtl/top.sv:42:17: warning: [verilator/WIDTHTRUNC] Operator ASSIGNW expects 4 bits ...
```

Sorted by severity (fatal → none), then file, then line, then column —
so a diff between two CI runs shows real changes rather than engine
scheduling order. Paths are shortened against the working directory.
With a baseline active, violations absent from it are annotated `(new)`.

Diagnostics go to stderr with two distinct prefixes: `lintcrux: note:`
(non-fatal — a skipped engine, a missing baseline) and
`lintcrux: error:` (fatal). Only the latter implies a non-zero exit.
`--import-edam` additionally prints non-fatal importer advisories as
`lintcrux: warning:`. A run that never reached the engines (a usage
error, an unloadable project) prints nothing on stdout — not even a
summary line.

## Missing engines

By default, an engine whose binary cannot be found **fails the run**
(exit `3`):

```
lintcrux: error: engine "verible" is unavailable: could not start
"verible-verilog-lint": No such file or directory. Install it, point at
it with --verible-path, drop it with --engine, or pass
--allow-missing-engines to tolerate its absence.
```

That strictness is the point. A job that asked for Verilator and
silently ran zero engines is a green build that means nothing. If you
genuinely want a partial run, say so with `--allow-missing-engines` and
the message is demoted to a note.

This covers every engine. `cdc` runs `yosys`, so a missing `yosys`
makes both the `yosys` and `cdc` engines unavailable, and the message
for either names `--yosys-path`.

## Config overlay

`--config <path>` takes a **JSON** document using the same key names as
a `.lintcrux` project file, with every key optional. Present keys replace
the project's value wholesale; absent keys leave it alone.

```json
{
  "enabledEngineIds": ["verilator"],
  "defines": { "SYNTHESIS": "1" },
  "severityOverrides": { "verilator/UNUSEDSIGNAL": "note" }
}
```

Overlayable keys: `sourceFiles`, `includePaths`, `defines`, `topModule`,
`language`, `enabledEngineIds`, `severityOverrides`, `perEngineOptions`.
`name` and `rootPath` are deliberately not overlayable — they identify
the project.

An unknown key, a wrong-typed value, or an unparseable file **fails the
run** (exit `3`) rather than being ignored. A job whose severity
overrides silently did not apply reports the wrong answer.

Relative paths in the overlay resolve against the overlay file's own
directory.

## Baselines

`--fail-on-new-violations` compares the run against
`.lintcrux-baseline.json` in the project root (or `--baseline <path>`)
and fails only on violations the baseline does not contain. Matching is
by a fingerprint of `(rule, file, message)` — deliberately **not** line
number, so adding an import above a violation does not turn it into a
regression. The file component is relative to the project root (a
source outside the root keeps its absolute path), so a baseline matches
from any checkout location.

The baseline file is **written by LintCrux Pro**
(`lintcrux-pro baseline set`, or `Tools → Set Baseline from Current
Run…` in the desktop app); the open-core CLI reads it. With no baseline present, every
violation counts as new and the run exits `2`, with a note saying where
the file was looked for. That is strict, not broken: you get a
fail-on-anything gate until you have a baseline to relax it with.

A baseline file that exists but cannot be parsed exits `3`. A gate that
cannot read its baseline must not wave the build through.

## SARIF output

`--export sarif --out lint.sarif` (or `--sarif lint.sarif`) writes SARIF
2.1.0 shaped for GitHub code scanning specifically:

- one `runs[]` entry per engine, with `tool.driver.name` set to the
  engine id;
- `artifactLocation.uri` **relative to the project root**, with
  `uriBaseId: "%SRCROOT%"` and a matching `originalUriBaseIds` entry.
  (Uploading absolute developer-machine paths produces an
  accepted-but-useless SARIF: the alerts land with no line annotations,
  because nothing in the checkout matches
  `/home/runner/work/repo/repo/rtl/top.sv` as a relative path.)
- `automationDetails.id` = `<project-name>/<engine-id>`, stable across
  runs so a re-upload supersedes the previous one instead of creating a
  new category;
- severity mapped to SARIF `level` (`fatal` and `error` → `error`,
  `warning` → `warning`, `note` → `note`, `none` → `none`), with
  `fatal` additionally recorded as `properties.lintcrux.severity`;
- `ruleId` without the engine prefix (`UNUSEDSIGNAL`, not
  `verilator/UNUSEDSIGNAL`).

A violation reported outside the project root — a system header, say —
keeps its absolute path rather than becoming a `../..` escape, which
SARIF consumers reject.

The export contains **every** violation the run produced. A suppressed
violation keeps its result and gains a `suppressions` entry: `kind` is
`inSource` for an inline pragma and `external` for a managed waiver,
`status` is `accepted`, `justification` is the waiver's reason, and the
waiver id rides in `properties.lintcrux.waiverId`. Engine-specific
fields a result carries are written into its `properties` bag, never
onto the result itself, so the file validates against the SARIF 2.1.0
schema.

## Web builds

The web SARIF viewer ignores the command line entirely — it is driven by
the `?sarif=` query parameter instead. See
[The web viewer](../user-guide/web-mode.md).
