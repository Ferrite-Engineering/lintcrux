# Slang 11.0.0 — real text-mode transcript

Captured output, not hand-written. Byte-for-byte stderr of a real slang
run with no JSON flag — the surface `textModeFallback: true` selects,
and the only surface slang < 8.0 has at all.

## Engine

```text
slang version 11.0.0+7ddf4059f
```

macOS arm64, upstream release asset `slang-macos-arm64.tar.gz` of tag
`v11.0`.

## Command

```sh
slang -q -Wunused top.sv
```

## Why this case exists

Text mode carries the rule id as a trailing `[-Wunused-variable]`
bracket. Stripping the `-W` yields `unused-variable` — the *same*
identifier the JSON mode reports in `optionName`, so both modes produce
`slang/unused-variable` and both resolve against
`lib/data/rules/slang.json`. This case pins that equivalence: the
violations parsed here must match `slang_11_0_0_diag_json/` rule-for-rule.

## Source RTL

`top.sv` was written for this fixture. It is not derived from any
third-party project.

SPDX: `CC0-1.0`
