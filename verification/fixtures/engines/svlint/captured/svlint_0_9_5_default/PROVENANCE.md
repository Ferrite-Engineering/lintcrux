# svlint 0.9.5 — real default-report transcript

Captured output, not hand-written. Byte-for-byte stdout of a real svlint
run with no output flag, which is the surface the engine invokes: svlint
has no structured mode, and `--oneline` and `--github-actions` both drop
the rule name.

## Engine

```text
svlint 0.9.5
```

macOS arm64, Homebrew `svlint`.

## Command

```sh
svlint broken.sv top.sv
```

run from the directory holding the two sources and this `.svlint.toml`:

```toml
[option]

[textrules]

[syntaxrules]
blocking_assignment_in_always_ff = true
non_blocking_assignment_in_always_comb = true
```

Exit code 1.

## Why this case exists

The engine used to pass `--output-format json`, an option no svlint
release has. svlint exited 2 on it and linted nothing, and because the
exit code was not consulted and the parser skipped every line it did not
recognise, every svlint run reported clean. This transcript pins the
three shapes the parser must read: a `Fail:` block whose rule is on the
header line and whose message is the `hint  :` text, the `Error: parse
error` block that points at a position and is reported as an error on
that file, and the absence of a blank line between an `Error:` block and
the `Fail:` block that follows it.

## Source RTL

`top.sv` and `broken.sv` were written for this fixture. They are not
derived from any third-party project.

SPDX: `CC0-1.0`
