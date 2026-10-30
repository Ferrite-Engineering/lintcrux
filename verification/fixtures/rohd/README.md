# ROHD fixtures (ROHD 0.7 or later, source tracing)

Real output of a small ROHD design with source tracing on:

| File | What it is |
|---|---|
| `top.sv` | Generated SystemVerilog, one file, with inline `// ROHD:` source comments |
| `Top.flc.json` | The source-trace sidecar (version 6) for `top.sv`; it names the file `Top.sv` |
| `per_module/*.sv`, `per_module/Top.flc.json` | The same design written one module per file, with its sidecar |

The design has three modules, a struct, a flop, an `always_comb` block and an
adder, so a finding can land on a declaration, a driver, an instance and a read.
The keyword-named module `reg` is renamed `reg_` in the SystemVerilog.

## Provenance

| Input | Pinned to |
|---|---|
| `intel/rohd` (BSD-3-Clause) | `2d84f73abfb1ba95c64d218e9b13a12e8416249c`, `main` on 2026-10-27, which is ROHD 0.6.11 plus source tracing (the work released as 0.7) |
| `intel/rohd-vf` (BSD-3-Clause) | `dd830d3b83438dfa5a06b0f0d8841eca16e97046` |
| Dart SDK | 3.13.5 |

The design (`generator/design.dart.txt`) is ours; only the output of running it
against ROHD is kept here. Absolute paths from the machine that generated the
files are rewritten to `/work/rohd_fixture`, a folder that does not exist, so
the tests copy the files into a temporary Dart package before resolving paths.

## Regenerate

```bash
verification/fixtures/rohd/generator/generate.sh <empty work dir> verification/fixtures/rohd \
  top.sv Top.flc.json \
  per_module/Top.sv per_module/Adder.sv per_module/Reg.sv per_module/Top.flc.json
```

Needs network access the first time, for the two git dependencies. The `.txt`
suffix on the generator's Dart sources keeps the analyzer and the formatter from
treating them as part of this package.
