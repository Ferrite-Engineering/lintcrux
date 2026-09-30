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
| `cdc/elaboration-failed` | Error | Open core | Yosys could not elaborate the design, so nothing was analysed. |
| `cdc/unsupported-sources` | Error | Open core | The design includes VHDL; CDC refuses to analyse a partial design. |
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
| `cdc.yaml` constraints: declared clocks, synchronous groups, reviewed crossings | — | ✓ |
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

A `waive` entry without `net` covers the whole domain pair.

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

It is a *note*, so it stays out of an error-and-warning filter, and it means a clean run is self-evidently a clean run. Anything the analysis could not do — a register whose clock it could not resolve, a design that elaborated to a single domain — arrives alongside it as `cdc/analysis-note` rather than being silently dropped.

## Running it {#running}

CDC is registered like any other engine: it runs when `enabledEngineIds` is empty or lists `cdc`, and `--engine cdc` selects it on the command line. It drives Yosys to elaborate the whole design (`flatten`, deliberately without `opt`), so it needs `yosys` — on `PATH`, or wherever the **Yosys check** entry in `Settings → Engines` or `--yosys-path` points — and you should set `topModule` so the design elaborates from the right root. Findings carry the **destination** register's source position — that is where the unsafe sample happens and where a fix goes — with the driving register attached as a related location, so you can see both ends of the crossing.

Without a runnable `yosys`, CDC is reported like any other missing engine — **Binary not available** on the desktop, and exit `3` from the headless binary unless you pass `--allow-missing-engines`. A Yosys run that times out, that could not be started with your source list (a path containing a double quote, for instance), or that exits without writing its netlist marks the engine **Failed** instead — also exit `3`, and not something `--allow-missing-engines` tolerates. `cdc/elaboration-failed` is reserved for a design Yosys ran on and rejected with a non-zero exit.

!!! note "Whole-design analysis"
    A crossing is a relationship between two places, so CDC has no incremental mode: re-analysing one changed file in isolation would answer a different question. It runs over the whole design every time, and is never served from the Pro lint cache — the cache keys on the engine binary's version, which for CDC is Yosys', so a cached result could not be invalidated by a LintCrux update *or* by you editing `cdc.yaml`. One extra Yosys invocation is the right price for constraint edits that actually take effect.
