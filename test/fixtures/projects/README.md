# Project-level fixture corpus

Whole-project fixtures: a `project.lintcrux`, its sources, and the unified
SARIF the real engines produce for it.

```
<fixture>/
├── project.lintcrux              the project definition
├── <sources>                     the design under lint
├── engine-output/<engineId>.json the recorded subprocess: argv, stdout,
│                                 stderr, exit code
├── capture.json                  which binary, which version, which day —
│                                 and any engine left unverified, with why
└── expected.sarif.json           the golden, DERIVED from the recordings
```

## Nothing here is written by hand

`expected.sarif.json` is generated. To refresh the whole corpus:

```bash
dart run tool/capture_project_fixtures.dart
# or one fixture:
dart run tool/capture_project_fixtures.dart --fixture vhdl/basic_warnings
```

The tool runs the real binaries through the real engine adapters, records
every subprocess, and derives the golden from what came back.

When only LintCrux's side moved (the SARIF writer or an engine parser) and
the engines' output did not, re-derive the goldens from the committed
recordings instead:

```bash
dart run tool/capture_project_fixtures.dart --replay
```

`--replay` runs no binary and leaves `engine-output/` and `capture.json`
alone; it is the same replay `project_fixture_golden_test.dart` performs.
A full re-capture on a host missing one of the binaries would turn that
engine's recording into an `unverified` entry just to pick up the new shape.

## Why the ceremony

Until 2026-08-03 these `expected.sarif.json` files were fiction. Nothing
ran an engine against them and nothing compared anything to them — the only
test that opened them checked that the JSON parsed and carried
`"version": "2.1.0"`. When they were finally checked against real binaries,
two of four were wrong:

- **`basic_warnings`** claimed `verilator/UNUSEDSIGNAL` and
  `verilator/UNDRIVEN`. Verilator produced *neither*. Three independent
  reasons, any one of which was sufficient:
  1. the fixture's own line-2 comment started with the word "Verilator",
     which the binary reads as a metacomment pragma — it aborted with
     `%Error-BADVLTPRAGMA` before linting anything;
  2. the adapter never passed `-Wall`, and both of those checks are
     opt-in;
  3. the signal was named `unused_sig`, and Verilator's default
     `--unused-regexp '*unused*'` suppresses UNUSEDSIGNAL for exactly
     that name.
- **`vhdl/basic_warnings`** claimed 2 GHDL results at lines 24 and 27.
  GHDL 6.0.0 produced 5, at different lines, with different text,
  including a hard `type of prefix is not an array` error the expected
  file never mentioned. That fixture was not even *discovered* by the old
  harness, which walked only the immediate children of `projects/`.

`test/fixtures/project_fixture_golden_test.dart` is what stops that
recurring. Three of its four layers need no engine binary installed:

| Layer | Needs a binary? | Catches |
|---|---|---|
| `argv` | no | the adapter silently changing what it asks the engine for |
| `replay` | no | parser drift against the recorded output |
| `attribution` | no | a golden nobody can attribute to a real binary |
| `live` | yes, skips otherwise | a golden that is simply wrong |

The `attribution` layer is the load-bearing one. An engine a fixture
enables must have either a recording or an explicit `unverified` reason in
`capture.json`. "We could not check this" is a thing the corpus is now
required to say out loud, rather than something that reads identically to
"we checked this."

As of 2026-08-03 **no fixture carries an `unverified` entry**: every engine
every fixture enables has a recording from a real binary. `multi_engine`
was the last gap — slang was not installed on the capture host — and it is
closed against `slang version 11.0.0+7ddf4059f` from the upstream release
asset `slang-macos-arm64.tar.gz` of tag `v11.0`, the version pinned in
`tool/bundled_engines.yaml`.

## Re-capture is reproducible, and that took a fix

Running the capture tool twice in a row used to produce two different
goldens. GHDL's `-a` writes a work library (`work-obj93.cf`) and an object
file next to the source and *reads them back* on the next run, so the
second capture of `vhdl/basic_warnings` gained a fourth diagnostic —

```text
design.vhd:18:1:warning: entity "design" was also defined in file "…" [-Wlibrary]
```

— that a first capture on a fresh clone cannot produce. Both artifacts are
gitignored, so nothing about the working tree hinted at the difference. The
committed golden was correct only because the person who cut it happened to
have a clean tree. `capture_project_fixtures.dart` now purges those
artifacts before each fixture, and two consecutive runs are byte-identical.

One byte of genuine non-determinism remains and is deliberately kept:
`clean_project`'s Verilator recording ends with Verilator's own
`Walltime … allocated … MB` report line, which differs every run. It is
real captured output, it feeds no SARIF result, and normalizing it would
mean committing bytes the binary did not emit — the exact habit this corpus
exists to break. Expect that one line to churn on re-capture.

## Fixture authoring traps

- **Never start a comment with an engine's name.** Verilator's metacomment
  scanner matches loosely — even `VerilatorEngine` at the head of a comment
  trips `BADVLTPRAGMA` and kills the whole run.
- **Never name a signal `*unused*`** if you want `UNUSEDSIGNAL`.
- **Match the module name to the file name** unless you want
  `DECLFILENAME`, which `-Wall` turns on.
- **A fixture meant to demonstrate warnings must analyse cleanly.** An
  error in the source is a fixture bug, not a finding.
- **Every engine a fixture enables must actually flag something in it.**
  `multi_engine` enabled slang and claimed "each engine flags a different
  issue", but nothing in the source was a slang diagnostic, so a slang run
  returned an empty array. That is the *same observable result* as a slang
  run with a bad flag — which is precisely how `--json-diagnostics`, an
  option slang has never had, survived unnoticed. A zero-finding
  expectation cannot distinguish a working adapter from a dead one. If an
  engine legitimately has nothing to say about a fixture, give it something
  to say or drop it from `enabledEngineIds`.
- **Check what the engine flags *by default*.** slang's `unused-variable`
  looks like the obvious fixture warning, but it is not in slang's
  `default` group and the adapter passes no `-W` flags, so it never fires.
  `multi_engine` uses `empty-body`, which is default-on, and which neither
  Verilator nor Verible reports — so it isolates the slang path cleanly.
