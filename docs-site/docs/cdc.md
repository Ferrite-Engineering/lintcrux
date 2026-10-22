# Clock-domain crossings

A signal that crosses from one clock domain to another can be sampled while it is still changing. The receiving flop then settles to an unpredictable value — or, on a bus, to a mixture of old and new bits that never existed anywhere in the design. Simulation almost never shows you this. It is the classic bug that passes every regression and fails in the lab.

LintCrux analyses crossings **structurally**, from the elaborated netlist, and reports them as ordinary violations from the `cdc` engine. They land in the same table as your Verilator and Verible findings, and filter, waive, baseline and export to SARIF the same way.

!!! note "Structural CDC lint, not sign-off CDC"
    This is worth being blunt about, because the industry term is overloaded. LintCrux finds and classifies crossings from design structure. It is not a sign-off tool: there is no formal proof, no reconvergence analysis and no reset-domain analysis. Use it to find the crossings you did not know you had and to keep new ones from landing — not to sign a tapeout.

## The rules {#rules}

| Rule | Severity | Tier | What it means |
|---|---|---|---|
| `cdc/unsync-single-bit` | Warning | Open core | A single bit crosses with no synchronizer. The destination flop can go metastable. |
| `cdc/unsync-multi-bit` | Error | Open core | A bus crosses with no synchronizer. Worse than the single-bit case: the destination can latch a mix of old and new bits — a value that never existed in the source domain. |
| `cdc/combo-in-sync` | Error | Open core | Combinational logic sits between the two flops of a synchronizer. The chain no longer provides the settling time it exists for — and it still looks like a synchronizer to a reviewer. |
| `cdc/per-bit-sync-bus` | Error | <span class="tier tier-pro">Pro</span> | A bus "synchronized" with a separate two-flop chain per bit. See below — this one deserves its own section. |
| `cdc/reviewed-crossing` | Note | <span class="tier tier-pro">Pro</span> | An unprotected crossing that a `cdc.yaml` `waive:` rule covers. Reported as a note carrying the rule's `reason`, in place of the error or warning, so an accepted crossing stays visible rather than vanishing. See [below](#cdc-yaml). |
| `cdc/elaboration-failed` | Error | Open core | Yosys could not elaborate the design, so nothing was analysed. The headless binary exits `3` on it. |
| `cdc/unsupported-sources` | Error | Open core | The design includes VHDL; CDC refuses to analyse a partial design. The headless binary exits `3` on it. |
| `cdc/needs-slang-frontend` | Error | Open core | From LintCrux 1.2. The design uses SystemVerilog packages, the Yosys in use has no yosys-slang frontend, and its built-in reader refused the design, so nothing was analysed. Names the package and how to get yosys-slang. The headless binary exits `3` on it. See [below](#systemverilog). |
| `cdc/summary`, `cdc/analysis-note` | Note | Open core | What was analysed, and anything the analysis could not do — reported even on a clean design. See [below](#summary-note). |

## The fix that looks careful and is not {#per-bit}

Put an 8-bit bus through a two-flop synchronizer on every bit. Each bit is now individually protected against metastability. Every warning goes quiet. It looks like the diligent thing to do, and it is **more dangerous than leaving the bus alone**.

The eight chains resolve independently. Bits that changed together in the source domain can land in different destination cycles, so the receiver reads a value that was never present anywhere. That is the same incoherence as an unsynchronized bus — except now there is no warning left to notice it, and the code passes review.

LintCrux Pro recognises this shape in order to *reject* it. Use a handshake or an asynchronous FIFO instead.

## What open core does, and what Pro adds {#tiers}

Open core resolves each register's clock to the literal net driving it, and treats every distinct clock net as asynchronous to every other. That is the safe setting: it cannot miss a crossing. It also means a clock that passes through a buffer, an enable gate or a divider looks like a *different* clock on the far side, so every register behind it lands in a domain that does not really exist. On a design with one gated clock, a handful of real crossings can become hundreds of reported ones. In open core, only a two-flop chain counts as protection.

**Pro traces the clock tree**, and this needs nothing from you — no constraints file, no configuration. It follows buffers and inverters, picks the clock-like input of a gate or mux, and walks through a divider flop to the clock that drives it. One oscillator behind three different clock nets is recognised as one domain.

| Capability | Open core | Pro |
|---|---|---|
| Find every crossing; single/multi-bit classification | ✓ | ✓ |
| Two-flop synchronizer recognition; `combo-in-sync` | ✓ | ✓ |
| Findings in the unified table, with waivers, baselines, trends and SARIF | ✓ | ✓ |
| Clock-tree tracing through buffers, gates, muxes and dividers | — | ✓ |
| `cdc.yaml` constraints: declared clocks, synchronous groups, reviewed crossings, handshakes | — | ✓ |
| Handshake-qualified buses | — | ✓ |
| N-flop chains (three or more stages); gray-coded pointers recognised by name | — | ✓ |
| `cdc/per-bit-sync-bus` | — | ✓ |

## The `cdc.yaml` constraints file <span class="tier tier-pro">Pro</span> {#cdc-yaml}

Some things are simply not in the netlist. Two clocks fed from the same external PLL look unrelated to any structural analysis. So does the pairing between a request line and the bus it qualifies. Put `cdc.yaml` in the directory that holds the project's first source file — the desktop app and the `lintcrux-pro` command line read it identically, because a CDC gate that only works with a window open is not a gate.

```yaml
# Clocks, and how they relate.
clocks:
  - name: clk_sys
  - name: clk_div2
    derived_from: clk_sys     # a divided clock is synchronous to its source
  - name: clk_usb

# Clocks that share a source but whose relationship the netlist cannot show.
synchronous_groups:
  - [clk_sys, clk_pll_b]

# Crossings you have reviewed and accepted.
waive:
  - from: clk_sys
    to: clk_usb
    net: cfg_static
    reason: "written once at boot, before clk_usb leaves reset"

# A bus that crosses unsynchronized on purpose, qualified by a synchronized request.
handshakes:
  - request: req
    acknowledge: ack
    data: [payload]
```

A `waive` entry without `net` covers the whole domain pair, and `*` in `from` or `to` matches any clock. The names are the clock nets as the analysis names them, which is what the `cdc/summary` note lists and what the finding's message shows.

A crossing a `waive` rule covers is not dropped. It is reported as a `cdc/reviewed-crossing` **note** carrying the rule's `reason`, at the same position and with the same cross-probe fields as the error it replaces, and the summary note counts it separately (`2 unsafe, 1 reviewed`). An accepted crossing that disappeared from the table would be indistinguishable from one the analysis never found; a reviewer six months later should see both the crossing and why it was accepted. A rule covering a crossing the analysis already recognises as protected changes nothing: the structural answer is the more informative one.

!!! note "Two rules the parser enforces on purpose"
    **`reason:` is mandatory** on a waive rule, and a rule without one is dropped with an error. An unexplained waiver is indistinguishable from a mistake six months later, and a constraints file full of them is how a CDC process quietly stops meaning anything.

    **A declared handshake is not taken on trust.** LintCrux checks that the named request is *itself* synchronized before honouring the declaration. Otherwise one line of YAML could silence a genuine hazard — and would look like a legitimate constraint to everyone who read it afterwards.

Everything else is lenient: a malformed entry is reported and skipped, and the rest of the file still applies. A single typo must not take your next run from twelve findings to four hundred.

## Every run says what it analysed {#summary-note}

A clean design produces no findings — and an empty table is indistinguishable from "the engine did not run", "no top module resolved", or "the whole design collapsed to one clock domain". So every CDC run that elaborates emits a `cdc/summary` note:

```
CDC analysed 3 clock domain(s) (generated clock (clocking.v:24), clk, div2)
and found 0 crossing(s), 0 unsafe.
```

It is a *note*, so it stays out of an error-and-warning filter, and it means a clean run is self-evidently a clean run. When a `cdc.yaml` `waive:` rule accepted a crossing, the count says so (`… 3 crossing(s), 0 unsafe, 1 reviewed.`), so a run that is clean because of a review reads differently from one that is clean by construction. Anything the analysis could not do — a register whose clock it could not resolve, a design that elaborated to a single domain — arrives alongside it as `cdc/analysis-note` rather than being silently dropped.

## Running it {#running}

CDC is registered like any other engine: it runs when `enabledEngineIds` is empty or lists `cdc`, and `--engine cdc` selects it on the command line. It drives Yosys to elaborate the whole design (`flatten`, deliberately without `opt`), so it needs `yosys` — on `PATH`, or wherever the **Yosys check** entry in `Settings → Engines` or `--yosys-path` points — and you should set `topModule` so the design elaborates from the right root. Findings carry the **destination** register's source position — that is where the unsafe sample happens and where a fix goes — with the driving register attached as a related location, so you can see both ends of the crossing.

Each source is read under the language the project resolved for it (its declared language, else its extension), so a SystemVerilog file gets `read_verilog -sv` and a Verilog file does not, and the project's include paths and defines are passed, the same as for the Yosys check engine. Yosys runs from the project root, so a relative path in `$readmemh` or `$readmemb` resolves against it wherever LintCrux was started from. A design whose memory images live in another directory names it with `workingDirectory` under `perEngineOptions.cdc` (see the [project file reference](reference/project-file.md)).

!!! warning "SystemVerilog designs that use packages (LintCrux 1.1)"
    The CDC path reads SystemVerilog with Yosys's built-in `read_verilog -sv`, which covers the synthesizable subset but not the whole language. Package scoping (`pkg::Name`), `void` functions and some other constructs stop it with a syntax error, so a design built on packages, among them OpenTitan, Ibex and CVA6, does not elaborate under `cdc` today and returns `cdc/elaboration-failed` with no crossings. The Verilator, Verible and Slang engines are not affected. A SystemVerilog front end for the CDC path is planned; until it lands, CDC analysis is limited to designs that stock Yosys can read.

From LintCrux 1.2, SystemVerilog that uses packages elaborates when the Yosys in use includes yosys-slang: see [below](#systemverilog).

Without a runnable `yosys`, CDC is reported like any other missing engine — **Binary not available** on the desktop, and exit `3` from the headless binary unless you pass `--allow-missing-engines`. A Yosys run that times out, that could not be started with your source list (a path containing a double quote, for instance), or that exits without writing its netlist marks the engine **Failed** instead — also exit `3`, and not something `--allow-missing-engines` tolerates. `cdc/elaboration-failed` is reserved for a design Yosys ran on and rejected with a non-zero exit. It still means nothing was analysed, so the headless binary exits `3` for it as well: a CI job never reads an unelaborated design as clean.

!!! note "Whole-design analysis"
    A crossing is a relationship between two places, so CDC has no incremental mode: re-analysing one changed file in isolation would answer a different question. It runs over the whole design every time, and is never served from the Pro lint cache — the cache keys on the engine binary's version, which for CDC is Yosys', so a cached result could not be invalidated by a LintCrux update *or* by you editing `cdc.yaml`. One extra Yosys invocation is the right price for constraint edits that actually take effect.

## SystemVerilog through yosys-slang, from LintCrux 1.2 {#systemverilog}

From LintCrux 1.2, when the Yosys that CDC runs includes the yosys-slang frontend, CDC reads the design's SystemVerilog with `read_slang` instead of `read_verilog -sv`. yosys-slang reads the language, packages included. The [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)'s Yosys has it built in; Homebrew's Yosys does not. Point **Settings > Engines > Yosys check** (or `--yosys-path`) at the suite's `bin/yosys`. A design with no SystemVerilog file is read with the built-in reader, as before, and the `cdc/summary` note says when yosys-slang read the design.

CDC reads with `--single-unit` (macros cross files, as they do in one `read_verilog`), `--top` with the project's `topModule`, `--ignore-initial` (initial blocks and declaration initializers describe simulation start-up, not structure) and `--ignore-assertions` (CDC reads no assertion). Set `topModule`: without it, yosys-slang elaborates every module in the file list, including ones the top never instantiates. yosys-slang names each file relative to the directory Yosys ran in; CDC turns every position back into the project's own path, so waivers and baselines written against a finding keep matching it.

Measured with the OSS CAD Suite of 2026-10-21 on the three designs named in the LintCrux 1.1 note above:

| Design | Top | Result |
|---|---|---|
| CVA6 v5.3.0 core (`core/Flist.cva6`, `cv64a6_imafdc_sv39`) | `cva6` | Elaborates (about 69,000 cells) |
| Ibex | `ibex_core` | Elaborates (about 11,000 cells) |
| Ibex | `ibex_top` | Refused by yosys-slang: a declaration initializer that reads a net (`ibex_top.sv` lines 659 and 660, "reading net state during design initialization unsupported"). `--ignore-initial` does not remove it. Analyse from `ibex_core` |
| OpenTitan `earlgrey_1.0.0` | `chip_earlgrey_asic` | Elaborates with `rglts_pdm_3p3v`, an analog regulator's behavioural model, read as a black box (`blackboxedModules` under `perEngineOptions.cdc`, see the [project file reference](reference/project-file.md)). The flattened netlist is about 739,000 cells and 840 MB of JSON. See [design size](#design-size) for the memory and time the whole run took |

When the Yosys in use has no yosys-slang and its built-in reader refuses a design that declares or imports a package, CDC reports one `cdc/needs-slang-frontend` error, at the first package declaration or import, naming the package and how to get yosys-slang, in place of `cdc/elaboration-failed`. A design that yosys-slang itself refuses is `cdc/elaboration-failed`, and the message says yosys-slang read it.

## Design size, from LintCrux 1.2 {#design-size}

CDC flattens the whole design, so the netlist it reads grows with the chip. From LintCrux 1.2, Yosys writes that netlist to a temporary file and CDC reads it a piece at a time, keeping only the top module and the parts of it the analysis uses. LintCrux 1.1 held the whole JSON document in memory and decoded it in one go, which on OpenTitan earlgrey took 5 GB before the analysis started.

Measured from LintCrux 1.2 on a Mac mini with an Apple M4 Pro and 64 GB of memory, with the Yosys of the OSS CAD Suite of 2026-10-21 and the open-core analysis:

| Design | Cells after `flatten` | Netlist JSON | Yosys peak memory | CDC peak memory | Whole run |
|---|---|---|---|---|---|
| Ibex `ibex_core` | about 11,000 | 10 MB | 0.1 GB | 0.3 GB | under 1 second |
| CVA6 v5.3.0 core (`cva6`) | about 69,000 | 113 MB | 1.3 GB | 0.6 GB | 5 seconds |
| OpenTitan earlgrey (`chip_earlgrey_asic`) | about 739,000 | 840 MB | 5.4 GB | 2.3 GB | 85 seconds |

Yosys finishes and exits before CDC reads its output, so the two peaks do not add up: the larger one is what the machine needs. On earlgrey CDC found 57 clock domains and 975 crossings, 156 of them unsafe, with the open-core rule that every distinct clock net is its own domain (see [above](#tiers)).

These are the designs measured, not a limit. A larger design, or one with more or wider registers, needs more. The Pro analysis (clock-tree tracing, `cdc.yaml`, the further synchronizer idioms) has not been measured on a design of earlgrey's size.
