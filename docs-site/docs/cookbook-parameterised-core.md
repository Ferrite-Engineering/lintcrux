# Lint every configuration of a parameterised core

A core that selects its architecture with a module parameter is really several designs: a 2-stage and a 3-stage pipeline, a cache on or off, a 32-bit or a 64-bit datapath. Lint only the default and the other configurations are never checked. From LintCrux 1.2, one project file sets the parameters every engine sees, and the command line changes them per run, so CI can lint each configuration from the same sources.

- **Goal:** One `.lintcrux` project, and one CI job per configuration of the core.
- **Time:** About 10 minutes.
- **Tier:** Open Core. Parameters, `--param` and the exit-code gates are free.
- **You will use:** the [`parameters` key](reference/project-file.md#parameters), [`--param`](cli/invocation.md), and the [exit codes](cli/invocation.md).

## Steps {#steps}

1. **Name the top module and its default configuration in the project file.**

    Open the `.lintcrux` file and set `topModule` and `parameters`:

    ```json
    "topModule": "edubos5",
    "parameters": {"EN_WAIT4REGS": 0}
    ```

    Verilator and Slang receive each parameter as `-G`, and the Yosys check, CDC and pin-constraint engines as `hierarchy -chparam` on the top module (or `-G` when Yosys reads SystemVerilog with yosys-slang). The Yosys-based engines need the top module named: without one they fail the run rather than lint the default. A value is a number such as `1` or `8'hff`, or an identifier; string values are not accepted.

    If the project carries `-G` flags in `perEngineOptions.verilator.extraOptions` (an EDAM import writes them there), move them to `parameters`. Flags left in `extraOptions` reach Verilator only, and still win over `parameters` there.

2. **Run each configuration from the command line.**

    `--param NAME=VALUE` overrides one parameter for one run, on top of the project file, and can be repeated:

    ```bash
    lintcrux edubos5.lintcrux --exit-code
    lintcrux edubos5.lintcrux --param EN_WAIT4REGS=1 --exit-code
    ```

    A malformed `--param` is a usage error (exit `64`), never a run that quietly dropped it.

3. **Give CI one job per configuration.**

    A matrix keeps the configurations side by side and reports each one on its own:

    ```yaml
    jobs:
      lint:
        runs-on: ubuntu-latest
        timeout-minutes: 30
        strategy:
          fail-fast: false
          matrix:
            wait4regs: [0, 1]
        steps:
          - uses: actions/checkout@v4
          - name: Lint (EN_WAIT4REGS=${{ matrix.wait4regs }})
            run: >
              lintcrux edubos5.lintcrux
              --param EN_WAIT4REGS=${{ matrix.wait4regs }}
              --exit-code
              --sarif lint-${{ matrix.wait4regs }}.sarif
          - uses: github/codeql-action/upload-sarif@v3
            if: always()
            with:
              sarif_file: lint-${{ matrix.wait4regs }}.sarif
              category: lintcrux-wait4regs-${{ matrix.wait4regs }}
    ```

    Every SARIF file from one project carries the same run id, so give each configuration its own upload `category`; otherwise each upload replaces the last. A run that fails (exit `3`) writes no export, so the upload step reports a missing file for that job rather than uploading a partial result.

## Vendor primitives and black-box stubs {#stubs}

A design that instantiates an FPGA vendor's primitives or IP (a Gowin `Gowin_ALU54plus`, a Xilinx `DSP48E2`) has no source for them in the project, so Verilator reports `MODMISSING` and Yosys reports a module that is not part of the design. Neither is a defect in your RTL, and neither can be waived: the engine cannot elaborate past it.

Give the engines a stand-in. Write a stub file that declares each primitive with the ports your design connects and no body, and add it to `sourceFiles`:

```verilog
// Port-only stand-ins for vendor primitives, for linting only.
/* verilator lint_off UNDRIVEN */
/* verilator lint_off UNUSEDSIGNAL */
(* blackbox *)
module Gowin_ALU54plus (
  input  wire        clk,
  input  wire [53:0] a,
  input  wire [53:0] b,
  output wire [54:0] dout
);
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on UNDRIVEN */
```

The `(* blackbox *)` attribute tells Yosys the module is a black box, so the Yosys check and CDC engines keep its ports and do not look inside it. The `lint_off` pragmas stop Verilator from reporting the empty body. Keep the port names and widths the same as the vendor's: a mismatch shows up as a pin-connection finding, which is useful, because it means the stub has drifted from the real primitive.

For the CDC engine with yosys-slang there is also `perEngineOptions.cdc.blackboxedModules`, which reads a module you do have the source for as a black box (see [Clock-domain crossings](cdc.md)). It does not stand in for a module that is missing.

## Where to go next {#next}

Gate each configuration on new findings only with the [baseline recipe](cookbook-baseline-ci.md), or see [CI integration in depth](cookbook/ci-integration.md) for the rest of the workflow.
