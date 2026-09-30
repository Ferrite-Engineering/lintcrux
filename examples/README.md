# LintCrux examples

Ready-to-open projects. Launch LintCrux, then **File → Open Project…**
(`Cmd/Ctrl+O`), pick the `project.lintcrux` in one of the directories
below, and run it with **Tools → Run All Engines** (`F5`).

Each example points only at a source file committed beside it, using paths
relative to its own `project.lintcrux`, so it works from any checkout with
no editing.

| Example | What it demonstrates | Needs |
|---|---|---|
| [`getting-started/`](getting-started/project.lintcrux) | The core loop on SystemVerilog: two engines running in parallel, 7 findings over 6 rules, click-to-source, the inspector's rule metadata. | `verilator` **and/or** `verible-verilog-lint` on `PATH` |
| [`vhdl-getting-started/`](vhdl-getting-started/project.lintcrux) | The VHDL path: GHDL's `--warn-*` set driven from the project's `perEngineOptions`, and why `--warn-hide` and `--warn-unused` are worth reading together. | `ghdl` on `PATH` |
| [`getting-started/report.sarif`](getting-started/report.sarif) | **No engine at all.** A real captured report of the example above — open it with **File → Import SARIF report…** to see the violation table, filters and inspector with nothing installed. | nothing |

An engine that is not installed is simply skipped; the run-status panel
says which ones ran. `getting-started` is therefore useful with only one of
its two engines present.

## Installing an engine

```bash
# macOS
brew install verilator verible ghdl
# Debian / Ubuntu
sudo apt install verilator ghdl      # verible ships its own release tarball
```

Only `verilator` is needed to get something out of `getting-started`, and
it is the least friction of the three.

## Neither example is clean, on purpose

A report with nothing in it demonstrates nothing. Both designs compile and
would simulate; every finding is the kind of defect a linter exists to
catch and a test bench can easily miss.

### `getting-started/alu.sv` — 7 findings

| Engine | Rule | What it caught |
|---|---|---|
| verilator | `LATCH` | `always_comb` with an incomplete `case` and no `default` infers a latch. The single most consequential finding in the file. |
| verilator | `CASEINCOMPLETE` | the same defect named from the other direction — 3 of 8 `op` encodings unhandled |
| verilator | `UNUSEDSIGNAL` | `carry_scratch` is driven every cycle and read by nobody |
| verilator | `UNDRIVEN` | `overflow_flag` is read by `zero` and driven by nobody |
| verilator | `WIDTHTRUNC` | 8 bits assigned to a 4-bit output, silently dropping the top half |
| verible | `case-missing-default` | the style rule for the same gap, from an independent tool |
| verible | `explicit-parameter-storage-type` | `parameter WIDTH = 8` with no type |

Four of the five Verilator findings only exist because LintCrux passes
`-Wall`; `WIDTHTRUNC` is on by default. That difference is worth knowing
when comparing LintCrux's output against a bare `verilator --lint-only`.
`perEngineOptions.verilator.warnFlags` in the project file controls it.

### `vhdl-getting-started/counter.vhd` — 3 findings

| Rule | What it caught |
|---|---|
| `hide` | a process variable named `value` shadows the architecture signal `value` |
| `unused` | `spare_flag` — declared, never read |
| `unused` | `value`, the *signal* — which looks used, because the process is full of `value`. Every one of those references is the shadowing variable. The two warnings are one bug. |

## Regenerating `report.sarif`

```bash
./tool/regen_example_report.sh
```

It runs the real engines through the real CLI and then rebases
`originalUriBaseIds` off the capture host — `--sarif` writes it as an
absolute `file://` URI, which would otherwise commit somebody's home
directory into the repo. Do not hand-edit the report.

## The guard

[`test/examples/examples_test.dart`](../test/examples/examples_test.dart)
opens every example through the real `ProjectFileCodec` +
`resolveProjectPaths` and asserts each declared source resolves to a file
that exists, that the engines it names are registered, and that
`report.sarif` parses through the real `SarifReader` and carries no
absolute host path. Existence is not loadability, so nothing here checks
`existsSync` on the `.lintcrux` and calls it a day.
