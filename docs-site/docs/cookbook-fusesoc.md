# Lint a FuseSoC core

If your design is packaged as FuseSoC `.core` files, you already have a tool that knows how to resolve it — dependencies, include paths, defines, the lot. This recipe hands that resolved description straight to LintCrux, so nothing is re-described by hand and nothing drifts out of step with the core files. **~10 min · Free**

!!! note "Why not just point LintCrux at the sources?"
    You can, and for a single-core design it is fine. But a real FuseSoC design pulls in a dependency closure — SERV's `servant` is three cores and 26 source files — and that closure is what FuseSoC exists to compute. A hand-written file list is a second source of truth that starts wrong the first time somebody adds a dependency.

## 1 · Let FuseSoC resolve the design {#resolve}

Use the `--setup` flag so FuseSoC stops after writing its build description instead of invoking a tool:

```bash
fusesoc run --target=lint --setup servant
```

That writes an **EDAM** file — `<design>.eda.yml` — into the FuseSoC build directory. EDAM is the fully resolved, tool-agnostic description Edalize consumes: every source file with its language, the include directories, the top module, the defines, and any tool-specific options. It is the same file Edalize would hand Verilator.

## 2 · Import it {#import}

From the command line:

```bash
lintcrux --import-edam build/servant_0/lint-verilator/servant_0.eda.yml
```

Or in the desktop app, `File → Import FuseSoC EDAM…` and pick the `.eda.yml`. Either way LintCrux writes a `.lintcrux` project beside the EDAM and carries across:

| From the EDAM | Into the project |
|---|---|
| `files[]` with `file_type` | Sources, each with its own language — Verilog, SystemVerilog or VHDL. |
| `is_include_file` | Include directories. |
| `toplevel` | The top module. |
| `vlogdefine` parameters with a default | Preprocessor defines. |
| `vlogparam` parameters with a default | Verilator `-G` overrides. |
| `tool_options.verilator` | `-W*` flags as warning options; the rest as extra options. |
| `file_type: vlt` | Verilator waiver files, placed ahead of the sources — Edalize's own ordering. |
| The core each file came from | `sourceFileProvenance` in the project: which FuseSoC core contributed each file. |

!!! tip "Nothing is dropped silently"
    An EDAM construct LintCrux does not support produces a warning on stderr and the import continues. A broken input exits `65`. The importer targets EDAM version `0.2.1`; a file with a different version still imports, but says loudly that it is doing its best.

## 3 · Lint it {#lint}

Open the generated `.lintcrux` project and run it, or stay on the command line and go straight to a report your CI can read:

```bash
lintcrux --import-edam build/servant_0/lint-verilator/servant_0.eda.yml \
  --sarif out.sarif
```

That is the whole pipeline: core file in, SARIF out, no hand-editing anywhere in the middle. SARIF is what GitHub code scanning annotates pull requests from — see [Gate CI on new violations](cookbook-baseline-ci.md) for wiring it into a build.

## 4 · Separate your code from your dependencies {#provenance}

A three-core closure will produce findings in cores you did not write. The importer records which FuseSoC core contributed each file in the project's `sourceFileProvenance` map, so you can see which files belong to a dependency. The violation table does not show provenance itself; to split "my RTL" from "a vendored dependency", filter the table with a **file glob** that matches the dependency's staged directory (or the inverse). Waive or baseline the dependency's findings once; see [Triage a run & waive false positives](cookbook-triage-and-waive.md).

!!! note "Checked against SERV"
    The importer is tested against real FuseSoC captures from [SERV](https://github.com/olofk/serv) 1.4.0: `serv` through the tool API, with its `-Wall` Verilator options and `file_type: vlt` waiver, and `servant` through the flow API, with the full three-core `serv → servile → servant` closure of 26 sources and per-file core provenance.

!!! note "Related"
    For the project format and how engines are configured, see [Projects & engines](projects-and-engines.md). For the rest of the command-line surface, see the [command-line reference](cli/invocation.md). SimCrux imports FuseSoC core files too, for regressions rather than lint — [see its CLI documentation](https://docs.simcrux.app/cli).
