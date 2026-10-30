# Project file format (`.lintcrux`)

```json
{
  "version": 1,
  "name": "my-soc",
  "rootPath": ".",
  "language": "systemverilog",
  "sourceFiles": ["rtl/top.sv", "rtl/decode.sv"],
  "includePaths": ["rtl/include"],
  "defines": {"SYNTHESIS": "1"},
  "topModule": "top",
  "enabledEngineIds": ["verilator", "verible", "slang"],
  "severityOverrides": {
    "verilator/UNUSEDSIGNAL": "note"
  },
  "perEngineOptions": {
    "verilator": {"warnFlags": ["all", "no-DECLFILENAME"]},
    "verible": {"ruleProfile": "lowrisc"}
  }
}
```

| Key | Type | Meaning |
|---|---|---|
| `version` | int | **Required.** Must be `1`; any other value is rejected on load. |
| `name` | string | **Required.** Display name. |
| `rootPath` | string | **Required.** A relative value (e.g. `"."`) is replaced by the directory holding the `.lintcrux` file; an absolute value is used as written. |
| `language` | string | `verilog`, `systemverilog` (default), `vhdl`, or `mixed`. |
| `sourceFiles` | string list | Relative paths resolve against the project file's directory. |
| `sourceFileLanguages` | map | Per-file language override: path → `auto`, `verilog`, `systemverilog`, or `vhdl`. |
| `includePaths` | string list | Relative paths resolve like `sourceFiles`. |
| `defines` | map | Macro name → value; an empty value defines the bare name. |
| `parameters` | map | From 1.2: top-level parameter overrides, name → value. See [below](#parameters). |
| `topModule` | string | Top module / entity. |
| `enabledEngineIds` | string list | Engines to run. **Empty or omitted means every registered engine.** |
| `severityOverrides` | map | Engine-namespaced rule id → `fatal`, `error`, `warning`, `note`, or `none`. |
| `perEngineOptions` | map | Engine id → options object (below). |

Unknown keys are silently ignored (forward-compatible); a present key
with the wrong type is an error. Files saved by the app also carry
`filterPresets` — the presets saved from the violation table's
**Filter preset** dropdown — and `customRegexRules` (used by LintCrux
Pro); both may be omitted.

Projects created by `--import-edam` also carry a
`sourceFileProvenance` map — source path → the FuseSoC core
(`vendor:library:name:version`) that contributed the file. It is
informational; missing keys simply mean "origin unknown / this
project".

## `projectId` {#project-id}

From LintCrux 1.2, a project can declare an identity that is the same on every machine:

```json
"projectId": "soc-top"
```

| Key | Type | Meaning |
|---|---|---|
| `projectId` | string | 1 to 64 letters, digits, `.`, `_` or `-`. Commit it with the project file. Anything that keys a project across machines uses it, because an absolute checkout path differs on every machine and in CI. A value outside that set is rejected on load with a message that names the rule. Omitted when the project declares none, so a project file from an earlier release loads and saves unchanged. |

LintCrux never adds the key for you. Pick a short name once and keep it: changing it later starts a new history. The Enterprise [team database](../team-database.md) pools runs under it.

## `parameters` {#parameters}

From LintCrux 1.2, a project can set top-level parameters of the design, so every engine that elaborates it sees the same configuration:

```json
"topModule": "edubos5",
"parameters": {"EN_WAIT4REGS": 1}
```

| Key | Type | Meaning |
|---|---|---|
| `parameters` | map | Parameter name → value. A value is a number (`1`, `-4`, `8'hff`) or an identifier, written as a JSON string or a whole JSON number. String values, spaces and quotes are not accepted. A name that is not a Verilog identifier, or a value outside that set, is rejected on load with a message naming it. Omitted when empty, so a project file from an earlier release loads and saves unchanged. |

Each engine that elaborates the design receives them:

| Engine | How it is passed |
|---|---|
| `verilator` | `-G<name>=<value>`, before `perEngineOptions.verilator.extraOptions`, so a `-G` written there still wins |
| `slang` | `-G <name>=<value>` |
| `yosys`, `cdc`, `constraints` | `hierarchy -chparam <name> <value>` on the top module, or `-G <name>=<value>` when Yosys reads SystemVerilog with yosys-slang |

`verible`, `svlint` and `ghdl` read files without elaborating a top module, so the parameters do not apply to them. The Yosys-based engines apply a parameter to the module `topModule` names, so a project that sets `parameters` for them needs a `topModule` (or `--top`); without one their run fails rather than linting the default configuration.

On the command line, `--param NAME=VALUE` (repeatable) sets a parameter for one run, on top of the project's own. See [Lint every configuration of a parameterised core](../cookbook-parameterised-core.md).

## `constraintFiles` {#constraint-files}

From LintCrux 1.2, a project can list FPGA pin-constraint files:

```json
"constraintFiles": ["constraints/board.pcf"]
```

| Key | Type | Meaning |
|---|---|---|
| `constraintFiles` | string list | `.pcf`, `.lpf` or `.cst` files for the `constraints` engine to check against the top module's ports. Relative paths resolve against the project file's directory, like `sourceFiles`. The extension picks the format. Omitted when empty, so a project without constraint files is saved exactly as before; a project file from an earlier release loads unchanged. |

The files are not sources: no other engine reads them. A project whose
`enabledEngineIds` is not empty runs the check only when that list
includes `constraints`. See [Pin constraints](../pin-constraints.md).

## `perEngineOptions.verilator`

| Key | Type | Meaning |
|---|---|---|
| `warnFlags` | string list | Verilator `-W*` selectors without the leading `-W` (e.g. `["all", "no-DECLFILENAME"]`). Omit for the default `["all"]`; an explicit empty list means "no opt-in warnings". |
| `extraOptions` | string list | Raw flags appended to the Verilator command line (e.g. `-G` parameter overrides from an EDAM import). Verilator is the only engine with a raw-flags option. From 1.2, set parameters every engine should see in [`parameters`](#parameters) instead. |
| `waiverFiles` | string list | Verilator `.vlt` waiver/config files, passed after the flags and before the sources. Populated by `--import-edam` from `file_type: vlt` entries; only Verilator sees them. |

## `perEngineOptions.verible`

| Key | Type | Meaning |
|---|---|---|
| `ruleProfile` | string | Name of a curated Verible rule profile (see below). Omit to run Verible's own defaults. |
| `rulesConfigSearch` | bool | Pass `--rules_config_search` so Verible discovers a `.rules.verible_lint` walking up from each file. Implied when the project root holds a `.rules.verible_lint`. |
| `textModeFallback` | bool | Skip the structured-output attempt and parse text directly. |

## `perEngineOptions.slang`

| Key | Type | Meaning |
|---|---|---|
| `textModeFallback` | bool | Skip `--diag-json` and parse slang's text diagnostics. |

## `perEngineOptions.svlint`

| Key | Type | Meaning |
|---|---|---|
| `configPath` | string | Passed as `--config <path>`. Relative paths resolve against the directory of the first source file, which svlint runs from. |

Svlint has no structured output mode; LintCrux parses its default report, which is the only svlint output that names the rule. A non-zero exit that reports no finding (an option svlint does not know, a source it cannot open) is an engine failure, not a clean run.

## `perEngineOptions.yosys`

| Key | Type | Meaning |
|---|---|---|
| `workingDirectory` | string | The directory Yosys runs from, relative to the project root or absolute. Defaults to the project root. A relative path in `$readmemh` or `$readmemb` resolves against it, so a design that loads a memory image gives the same answer wherever LintCrux was started from. |

## `perEngineOptions.cdc`

| Key | Type | Meaning |
|---|---|---|
| `workingDirectory` | string | As for `yosys`: CDC drives Yosys and resolves memory images the same way. |
| `blackboxedModules` | list of strings | From LintCrux 1.2. Modules yosys-slang reads as black boxes (ports kept, contents not elaborated), for a behavioural model it cannot lower, such as an analog macro's. Each entry is a bare module name; anything else fails the run before Yosys starts. Applies only when CDC reads SystemVerilog with yosys-slang (see [CDC](../cdc.md#systemverilog)). |

Both Yosys-backed engines read each source under the language the project resolved for it (a declared language, else the extension), and pass the project's `includePaths` and `defines`.

## `perEngineOptions.rohd`

Not an engine: the place a project says where ROHD's source-trace files are, so
findings on ROHD-generated SystemVerilog can show their Dart source (ROHD 0.7 or
later; see [SystemVerilog generated by ROHD](../rohd.md)).

| Key | Type | Effect |
|---|---|---|
| `sidecar` | string, or list of strings | Source-trace files (`*.flc.json`), or folders holding them. Relative paths are against the project root. Used in addition to the `*.flc.json` files beside each `.sv` file. |

## `perEngineOptions.ghdl`

| Key | Type | Meaning |
|---|---|---|
| `warnFlags` | string list | GHDL warnings to enable, without the `--warn-` prefix. Omit for the default set (`binding`, `reserved`, `default-binding`, `library`, `shared`, `hide`, `unused`, `others`, `pure`); an explicit empty list enables none. |

### Rule profiles

A rule profile is a named, curated selection of `verible-verilog-lint`
rules. It changes **which checks the engine runs** — unlike a *filter
preset*, which filters the violation table after a run.

| `ruleProfile` | What it is |
|---|---|
| `lowrisc` | The lowRISC / OpenTitan Verilog style guide, as enforced by OpenTitan's own `lowrisc-styleguide.rules.verible_lint`: 41 rules including `line-length` at 100 columns, `localparam` names as CamelCase **or** ALL_CAPS, string parameters exempt from explicit storage types, and nested struct typedefs permitted. This is the guide Ibex and OpenTitan follow. |

The profile is emitted as `--ruleset=none --rules=<...>`, so it is a
closed, reproducible set rather than a delta on whatever Verible's
default selection happens to be in the installed release. With
`rulesConfigSearch` on, your own `.rules.verible_lint` is still
discovered and applied alongside it.

A `ruleProfile` value no profile claims **fails the run** with a
diagnostics entry rather than silently linting against the defaults.
