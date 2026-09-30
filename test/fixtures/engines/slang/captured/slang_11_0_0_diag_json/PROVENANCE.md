# Slang 11.0.0 — real `--diag-json` transcript

Captured output, not hand-written. Byte-for-byte stdout of a real slang
run in JSON-diagnostics mode.

## Engine

```text
slang version 11.0.0+7ddf4059f
```

macOS arm64, from the upstream release asset
`slang-macos-arm64.tar.gz` of `MikePopoloski/slang` tag `v11.0` — the
version pinned in `tool/bundled_engines.yaml`.

## Command

```sh
slang -q --diag-json - -Wunused top.sv
```

Exactly the argv `SlangEngine` builds in JSON mode.

## Why this case exists

Two things about this format are load-bearing and both were previously
wrong in LintCrux:

1. **The flag.** There is no `--json-diagnostics` option in slang and
   there never has been (zero hits across the upstream repository; the
   binary answers `error: unknown command line argument`). The real
   option is `--diag-json <file|->`, added in slang 8.0.
2. **The payload.** It is a single pretty-printed JSON **array**, not
   one object per line. `location` is a `"file:line:column"` *string*,
   not a `{"file","line","column"}` object, and the rule id lives in
   `optionName` (slang's `-W` name) rather than a `code` field.
   Diagnostics with no warning flag — errors — omit `optionName`
   entirely and land as `slang/UNCLASSIFIED`.

Upstream's `JsonDiagnosticClient.cpp` is unchanged from tag v8.0 through
v11.0, so this shape covers every slang release that has a JSON mode.

## Source RTL

`top.sv` was written for this fixture (an unused variable and a
reference to an undeclared identifier). It is not derived from any
third-party project.

SPDX: `CC0-1.0`
