# GHDL 6.0.0 — real `ghdl -a` transcript

Captured output, not hand-written. This is the byte-for-byte stderr of a
real GHDL run, committed so the parser is pinned against what the engine
actually prints rather than against an idealized format.

## Engine

```text
GHDL 6.0.0 (6.0.0.r0.ge589c698c) [Dunoon edition]
 Compiled with GNAT Version: 14.2.0
 llvm 22.1.0 code generator
```

macOS arm64, Homebrew build. The pinned version in
`tool/bundled_engines.yaml`.

## Command

```sh
ghdl -a --warn-binding --warn-reserved --warn-default-binding \
        --warn-library --warn-shared --warn-hide --warn-unused \
        --warn-others --warn-pure demo.vhd
```

That is `GhdlEngine.defaultWarnFlags` verbatim, with each flag prefixed
`--warn-`, exactly as the engine builds its argv. All nine flags are
accepted by GHDL 6.0.0 (`--warn-reserved` resolves to the
`-Wreserved-word` warning by unique-prefix match).

## Why this case exists

GHDL prints **no space** between the location and the severity word:

```text
demo.vhd:17:14:warning: declaration of "rst" hides port "rst" [-Whide]
```

`GhdlParser` previously required `:\s+` there, so it matched nothing on
stock GHDL output and every run reported zero violations. Verified
identical on GHDL 5.1.1 (`ghdl-llvm-5.1.1-macos15-aarch64`), so the
spaced form this corpus used to assert never came from a real release.

The continuation lines are the raw source echo plus a caret column —
there is no `NN |` line-number gutter.

## Source RTL

`demo.vhd` was written for this fixture (a VHDL entity with a
port-shadowing variable, two never-referenced objects, and one
undeclared identifier). It is not derived from any third-party project.

SPDX: `CC0-1.0`
