# Slang 11.0.0 — `--diag-json` without `-q` (banner interleaved)

Captured output, not hand-written. Same run as
`slang_11_0_0_diag_json/`, minus the `-q` flag, so slang's
human-readable banner surrounds the JSON array on the same stream.

## Engine

```text
slang version 11.0.0+7ddf4059f
```

macOS arm64, upstream release asset `slang-macos-arm64.tar.gz` of tag
`v11.0`.

## Command

```sh
slang --diag-json - -Wunused top.sv
```

## Why this case exists

`SlangEngine` passes `-q`, but a user-supplied `extraArgs`, a wrapper
script, or an older build can put the banner back. The parser must find
the JSON block inside surrounding prose rather than assuming the whole
stream is JSON — so the three banner lines here are expected to surface
as SARIF `toolExecutionNotifications` while both diagnostics still
parse. A parser that gives up on the first non-JSON line would report a
clean run on a design with a real error.

## Source RTL

`top.sv` was written for this fixture. It is not derived from any
third-party project.

SPDX: `CC0-1.0`
