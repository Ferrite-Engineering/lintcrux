# Pin constraints

From LintCrux 1.2, the `constraints` engine checks FPGA pin-constraint files against the top module's ports, so a mistyped port name, a missing pin or a pin given to two ports is a finding in LintCrux instead of a place-and-route error, or a board that does nothing. The findings are ordinary violations: they land in the same table as your Verilator and Verible findings, sit on the constraint file's own line and column so they open in the source view, and filter, waive, baseline and export to SARIF the same way. The engine is Open core.

## The formats {#formats}

| Format | Family | Read by | Line forms LintCrux reads |
|---|---|---|---|
| `.pcf` | Lattice iCE40 | nextpnr-ice40 | `set_io [-nowarn] [-pullup yes] <port> <pin>` |
| `.lpf` | Lattice ECP5 | nextpnr-ecp5 | `LOCATE COMP "<port>" SITE "<pin>";`, `IOBUF PORT "<port>" ...;` |
| `.cst` | Gowin | nextpnr-himbaechel | `IO_LOC "<port>" <pin>;`, `IO_PORT "<port>" ...;` |

The readers accept what nextpnr's own readers accept: its commands, flags, quoting and comment rules, and bus bits written `led[3]`. A statement that names no port (`set_frequency`, `BLOCK`, `FREQUENCY`, `CLOCK_LOC`) is read and skipped. The format of a file is its extension, and an extension that is none of the three is refused rather than guessed.

## Giving a project its constraint files {#inputs}

- **A `.lintcrux` project** lists them under `constraintFiles`, beside `sourceFiles`, with paths relative to the project file. See [Project file format](reference/project-file.md#constraint-files). A project that has none loads and saves exactly as before.
- **The Sources panel** lists them under **Constraint files**, beneath the sources, with the same remove button as a source. The panel has no add action: put the file in the project file, import it from FuseSoC, or pass it on the command line.
- **A FuseSoC import** takes every file whose `file_type` is `PCF`, `LPF` or `CST` in the EDAM file. See [Lint a FuseSoC core](cookbook-fusesoc.md).
- **The command line** takes `--constraints <file>`, repeatable, added to the project's own list. See [Command line](cli/invocation.md).

The engine runs when `enabledEngineIds` is empty or lists `constraints`, and `--engine constraints` selects it. With no constraint files it reports nothing and does not start Yosys. It needs a top module (set `topModule`, or pass `--top`) and `yosys`, found the same way the [CDC engine](cdc.md#running) finds it: on `PATH`, or wherever the **Yosys check** entry in `Settings → Engines` or `--yosys-path` points.

## The rules {#rules}

| Rule | Severity | Reported at |
|---|---|---|
| [`constraints/unknown-port`](#unknown-port) | Error | The constraint line that names a port the top module does not have |
| [`constraints/unconstrained-port`](#unconstrained-port) | Warning | The port's declaration in the RTL, one finding per port |
| [`constraints/bit-out-of-range`](#bit-out-of-range) | Error | The constraint line that names a bit the port does not have |
| [`constraints/pin-reused`](#pin-reused) | Error | Each constraint line after the first that puts a second port on one pin |
| [`constraints/port-reassigned`](#port-reassigned) | Warning | A constraint line that places a port, or a bus bit, on a second pin |
| [`constraints/unparsed-line`](#unparsed-line) | Note | A line no reader recognised, so nothing is silently ignored |

### constraints/unknown-port {#unknown-port}

The line names a port the top module does not have, most often a typo or a renamed port. When exactly one port of the top module is within two edits of the name, ignoring case, the message ends with a suggestion. A bus named with no bit (`led` for a 4-bit `led`) is also reported here, because nextpnr names each bit of a bus separately (`led[0]` to `led[3]`) and matches no cell for the bare name.

### constraints/unconstrained-port {#unconstrained-port}

A port of the top module has no pin. A bus is one finding that lists the bits without a pin. The finding sits on the port's declaration, taken from Yosys's source position; when Yosys recorded none, it sits on the first line of the first constraint file and the message names the port. A file is judged against its own format: a project with a `.pcf` and a `.cst` is checked once against each.

### constraints/bit-out-of-range {#bit-out-of-range}

The line names `led[8]` on an 8-bit `led`. The range comes from the declaration, so `[7:0]`, `[0:7]` and `[8:1]` each accept their own indexes. A one-bit port accepts `x` and `x[0]`, as nextpnr does, and nothing else.

### constraints/pin-reused {#pin-reused}

Two different ports, or two bits of a bus, are put on one package pin. The first line keeps the pin; every later line that gives it to another port is reported, and the message names the first owner and its line. Pins are compared within one format.

### constraints/port-reassigned {#port-reassigned}

One port, or one bus bit, is placed on two different pins. Placing it again on the same pin is not reported. What nextpnr does with the second line differs by family: see [the table below](#nextpnr).

### constraints/unparsed-line {#unparsed-line}

A line that none of the three readers recognises. It is reported as a note so a misspelt command is visible rather than quietly ignored. The line may be fine for a tool or a version LintCrux does not read.

### Runs that did not happen {#did-not-run}

Four more ids report that the check did not run. Each carries the analysis-failed marker, so the headless binary exits `3` on it: a project that cannot be checked is never a clean one.

#### constraints/no-top-module {#no-top-module}

Constraint files are listed and no top module is set, so there are no ports to check against. Set `topModule` in the project, or pass `--top`.

#### constraints/unsupported-sources {#unsupported-sources}

The design includes VHDL. The engine reads Verilog and SystemVerilog only, as the CDC engine does, and refuses to check against a design it has only part of.

#### constraints/elaboration-failed {#elaboration-failed}

Yosys could not elaborate the design, or the elaborated design has no module with the top module's name. A Yosys that cannot be started, or that times out, is reported as an engine failure instead, also exit `3`.

#### constraints/constraint-file-unreadable {#constraint-file-unreadable}

A listed constraint file does not exist, is not a regular file, is larger than 4 MiB, or has an extension that is not `.pcf`, `.lpf` or `.cst`. Constraint files are read a line at a time, like source files.

## What nextpnr already rejects {#nextpnr}

Each case below was run through the nextpnr of the same family, one mistake per file, against a design with four ports. "Rejects" means nextpnr stops with an error; "warns" means it prints a warning and carries on; "accepts" means it prints nothing and carries on. The measurements are from nextpnr 0.11.1-77-g6b438a1c (OSS CAD Suite 2026-10-21).

| Mistake | iCE40 (`.pcf`) | ECP5 (`.lpf`) | Gowin (`.cst`) |
|---|---|---|---|
| Unknown port | Warns, then rejects the port it left unplaced | Accepts, then rejects the port it left unplaced | Accepts, then rejects the port it left unplaced |
| Port with no pin | Rejects | Rejects | Rejects |
| Bit out of range | Warns | Accepts | Accepts |
| Pin used by two ports | Rejects, at placement | Rejects, at placement | Rejects, at placement |
| Port on two pins | Rejects | Accepts, the later line wins | Accepts, the later line wins |
| Unrecognised line | Rejects | Accepts | Warns |

Three things follow. A typo in a port name is only a warning on iCE40 and is invisible on the other two; what stops the run is the missing pin on the port the typo should have named, and the message names that port, not the typo or its line. A bit that does not exist is accepted by ECP5 and Gowin, so a constraint for `led[4]` on a 4-bit `led` does nothing and the board is still built. A port placed twice is accepted by ECP5 and Gowin, with the later line quietly replacing the earlier. Where nextpnr does reject, the message for a shared pin names a cell and a location in the chip, not the pin or the line.

## Limits {#limits}

- Pin names are not checked against the package. Whether `35` is a pin of the device needs a per-device pin database; nextpnr checks that when it places the design.
- Electrical standards, timing constraints (`.sdc`, `FREQUENCY`, `set_frequency`) and clock placement are not checked, and LintCrux does not edit the files.
- The elaboration limits the [CDC engine documents](cdc.md#running) apply here too: Yosys reads SystemVerilog with `read_verilog -sv`, so a design that stock Yosys cannot elaborate returns `constraints/elaboration-failed`.
- A differential pair's second pin in a `.cst` `IO_LOC` line is not read.
- A port whose name is a Verilog escaped identifier is matched by its name as Yosys writes it.
- This is a different feature from the Pro CDC constraints file, `cdc.yaml`, which declares clocks and reviewed crossings for the CDC engine.

## Running it {#running}

```sh
lintcrux top.v --top top --constraints pins.pcf
```

The command line accepts `--constraints` more than once, and adds the files to the project's own. A path that does not exist is a usage error (exit `64`). A run with no top module, a design with VHDL, or a design Yosys rejects exits `3`, never `0`. Findings follow the same gates as any other engine: `--exit-code` fails on any that survive, and a baseline freezes the ones you accept.
