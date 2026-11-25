# LintCrux for coding agents

LintCrux lints Verilog, SystemVerilog and VHDL with the engines a project
configures (Verilator, Verible, Slang, Yosys, GHDL, svlint, and LintCrux's own
structural CDC and pin-constraint checks) and answers from the command line or
over the Model Context Protocol. This file is for an agent, and for the person
who configures one: when to call LintCrux, how to read what it returns, and how
to cite it so a person can check the answer.

## Starting the server

```
lintcrux mcp --root <project directory>
```

The server speaks MCP over stdin and stdout. Every path a tool receives must be
inside `--root` (the working directory when omitted), and so must every
source, include directory and Verilator configuration file a `.lintcrux`
project names. A path outside it, a symbolic link that leads outside it, or a
network path is refused, and nothing is run. A project that hands an engine
raw flags (`extraOptions`) is refused too: run it from the command line. The
server writes nothing into the project and makes no network call of its own.

The engines are the ones on `PATH`. The server offers no way to name another
engine binary, to write an export or a baseline, or to tolerate a missing
engine: a person does those from the command line.

LintCrux Pro's command line, `lintcrux_pro`, serves the same three tools, with
the same inputs:

```
lintcrux_pro mcp --root <project directory> [--license-file <path>]
```

Under a Pro licence its `lint` applies the project's managed waivers and the
Pro CDC analysis (clock-tree tracing and `cdc.yaml`), and its `waivers` lists
the managed waivers too. It reads the licence again on every call: the
`--license-file` given, then the `LINTCRUX_LICENSE_FILE` variable, then the
organisation's policy file. Below Pro it answers the free part and says what
it left out (see the warnings below).

Each tool is also a command, with the same inputs as flags and the same output
with `--json`:

```
lintcrux design.lintcrux --json
lintcrux top.sv fifo.sv --top top --json
lintcrux rule verilator/WIDTH --json
lintcrux waivers design.lintcrux --json
```

A tool's text is byte for byte what the command writes, so a script and an
agent read the same document.

## When to call it

- **Before you say that lint is clean.** Lint the project, and report the
  outcome and the counts the document gives.
- **After you change RTL.** Lint again and compare: a finding whose `baseline`
  is `new` is one the project's baseline does not already accept.
- **When a finding names a rule you do not know.** `rule` gives its default
  severity and the engine's page for it.
- **Before you argue that a finding does not matter.** `waivers` lists the
  waivers already in force and who set them.

## The three tools

| Tool | Returns | Limits |
|---|---|---|
| `lint` | Every engine's run, the counts by severity, and the findings: rule, severity, message, `file:line`, whether a waiver suppressed it, its baseline state | `limit`: default 100, at most 1000; `offset` for the next page |
| `rule` | A rule's default severity and the engine's help link, by the `engineId/ruleId` a finding gives | |
| `waivers` | The waivers in force: inline `lint_off` pragmas, the Verilator configuration files' `lint_off` lines, the baseline's frozen findings, and, from LintCrux Pro under a Pro licence, the project's managed waivers with their reason, author and expiry | |

`lint` takes a `.lintcrux` `project`, or `files` (Verilog, SystemVerilog or
VHDL sources) with an optional `top`. `engines` runs only the engines named;
`params` sets top-level parameters as `NAME=VALUE`. `new_only` turns on the
baseline gate: findings that are not in the project's baseline make the
outcome `failed_gate`. The findings themselves are the same either way.

## Reading a document

Every answer is one JSON object with eight members, always present, in this
order:

| Member | Meaning |
|---|---|
| `schema_version` | `1` |
| `tool` | `{"name": "lintcrux", "version": ...}` |
| `command` | `lint`, `rule` or `waivers` |
| `outcome` | `completed` or `failed_gate` when there is an answer; otherwise `usage_error`, `input_error`, `engine_error` or (LintCrux Pro) `licence_error` |
| `engines` | Each engine that ran, with the version its binary reports |
| `design` | For a lint run: a fingerprint of the source files (`lintcrux-sources-sha256/1`), so two answers about the same sources can be told apart from answers about different ones |
| `body` | The answer, or `null` when there is none |
| `diagnostics` | Errors that say why there is no answer, and warnings that qualify one |

**The `outcome` is the authority.** The tool result's `isError` is true
exactly when there is no answer.

| Outcome | Exit code (`lint`) | Exit code (`rule`, `waivers`) | Means |
|---|---|---|---|
| `completed` | 0 | 0 | The engines ran and no gate fired |
| `failed_gate` | 1, 2 or 4 | | A gate fired: `--exit-code`, `new_only` (`--fail-on-new-violations`), or the organisation's threshold |
| `usage_error` | 64 | 64 | A bad input or a path outside the root; nothing ran |
| `input_error` | 3, or 65 for an import | 65 | A project that cannot be read, or a source it lists is missing |
| `engine_error` | 3 | | An engine failed, timed out, was missing, or could not analyse the design |
| `licence_error` | 64 | 64 | LintCrux Pro only: the licence file it was told to read cannot be read (`licence.unreadable`); nothing ran |

**An `engine_error` is never a clean result.** Its body still lists the
findings the other engines returned, and `engine_runs` says which engine did
not finish (`phase` `failed` or `unavailable`; `timed_out` when the watchdog
stopped it). Say that the run is incomplete, and name the engine; do not say
the design is lint clean.

**Warnings qualify an answer.** A `licence.withheld` warning means part of
the analysis needs LintCrux Pro and was left out of this answer, for example a
project's managed waivers or the Pro CDC analysis; the rest of the answer
stands. From LintCrux Pro, `licence.source` notes beside it say why the
licence found did not admit it (expired, another product's, no licence). A
`rule.not_catalogued` warning means the rule is not in LintCrux's rule
database, so its help link has not been checked.

**Findings.** `counts` and `total` cover every finding; `findings` is one page
of them, ordered by file, line and column. When `truncated` is true, ask again
with `offset` set to `offset + returned`; the next page comes from the same
run, without running the engines again, as long as no file changed. A finding
with `suppressed: true` is waived and is not counted by severity. `raw`
carries an engine's own facts, such as a CDC crossing's clock domains and
registers. `signature` is the finding's identity across runs (the baseline's
fingerprint: rule, file and message, never the line). `baseline` is `new` or
`existing` against the project's baseline, and `null` when there is none.

**Rules.** `rule` returns the rule's default severity and `help_uri`. For a
`cdc` or `constraints` rule its `description` is one sentence saying what the
rule checks; for any other engine it is empty, so read the engine's page at
`help_uri`.

**Waivers.** Each waiver gives its `kind`, the `rule`, its `scope` (where it is
written, as `file:line`) and a `pattern`: the lines an inline pragma covers,
the `lint_off` directive as written, or, for a baseline entry, the message of
the finding it accepts. A `managed` waiver's `scope` is the first line it
covers and its `pattern` the lines (`lines 12-14`), or `scope` is `null` and
`pattern` names the file when it covers the whole file; `expired: true` means
it no longer suppresses anything.

The schemas of every body are in this repository under `spec/mcp/schemas/`,
with a golden document for every outcome each tool can produce under
`spec/mcp/goldens/`.

## Citing

**Cite every finding as `file:line`,** from its `location`, which every agent
host, terminal and editor makes clickable. Give the rule as the finding names
it (`verilator/WIDTH`) and its severity. Report what the document says: every
finding is an engine's, or LintCrux's own CDC and pin-constraint check's, and
LintCrux adds no verdict of its own.

## Never

- Never edit a waiver, a `lint_off` pragma, a Verilator configuration file or
  the baseline to make a run clean. A waiver is a person's decision, and none
  of the tools writes one.
- Never report an `engine_error` as a clean run, or a page of findings as all
  of them.
