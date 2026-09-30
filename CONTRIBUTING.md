# Contributing to LintCrux

Thanks for your interest in contributing to LintCrux. This document describes
how to file issues, submit pull requests, run the project's quality gates,
and certify the origin of your contributions.

LintCrux open core is licensed under the [Apache License 2.0](LICENSE). All
contributions you submit to this repository are accepted under that same
licence, and require a signed Contributor License Agreement — see
[Contributor License Agreement](#contributor-license-agreement-cla) below.

## Filing issues

Open issues at <https://github.com/Ferrite-Engineering/lintcrux/issues>. A
useful issue includes:

- A short, descriptive title.
- The version of LintCrux you are using (or a Git commit SHA).
- The platform (Linux/macOS/Windows/Web) and version.
- **The engine and its exact version** (`verilator --version`,
  `verible-verilog-lint --version`, `slang --version`, `svlint --version`,
  `ghdl --version`, `yosys -V`). LintCrux drives these as external
  subprocesses and parses their diagnostic output; a version-specific parse
  failure or a renamed rule ID is a common bug class.
- Steps to reproduce, ideally with a minimal HDL source file and the
  `.lintcrux` project / config that triggers the problem.
- The expected behavior and the actual behavior you observed.
- The raw engine stdout/stderr LintCrux captured, and the SARIF output if
  the bug is in the report rather than the run.

For security issues, please do **not** file a public issue. Contact the
maintainers privately via the email address listed in the Ferrite
Engineering GitHub organization profile.

## Submitting pull requests

1. **Fork** the repository and create a topic branch off `main`. Branch
   names follow `feature/short-description` or `fix/short-description` per
   the project's git conventions.
2. **Make your changes** following the conventions documented in
   [`CLAUDE.md`](CLAUDE.md) (the engineering manual for AI-assisted
   contributors and human reviewers alike) and
   [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). The most load-bearing
   rules:
   - **No hardcoded user-facing strings** — every string goes through the
     localization system. The five ARB files in `lib/l10n/` (`en`, `zh_CN`,
     `zh`, `ja`, `ko`) must stay in sync, and `app_zh.arb` mirrors
     `app_zh_CN.arb` byte-for-byte. `test/static/l10n_house_style_guard_test.dart`
     enforces this.
   - **Tests are mandatory** — every new or modified file in `lib/` has a
     corresponding test in `test/` mirroring the directory layout. Widget
     tests include a locale sweep across `en`, `zh_CN`, `ja`, `ko`.
   - **Engines run as subprocesses** — every `LintEngine` shells out
     through the `ProcessRunner` seam
     (`lib/services/engines/process_runner.dart`). Do not link an engine
     into the app process, and do not copy engine source into this repo.
   - **Per-tab / per-project provider scoping** — state that belongs to a
     project or tab lives in a scoped provider, never a root-scoped one.
     The static guards under `test/static/` scan for regressions.
   - **Open-core extension point first** — Pro features that need a hook in
     this repo land the extension-point interface here first; never fork
     code from this repo into the closed-source overlay.
3. **Run the quality gates locally** before pushing (see
   [Quality gates](#quality-gates) below).
4. **Sign the CLA** if you have not already — one time per
   contributor, not per pull request (see
   [Contributor License Agreement](#contributor-license-agreement-cla)
   below). It gates the merge, not the review, so open the pull
   request whenever you are ready.
5. **Open a pull request** against `main`. Use the [Conventional Commits](https://www.conventionalcommits.org/)
   prefix in both the commit subject and the PR title (`feat:`, `fix:`,
   `refactor:`, `docs:`, `test:`, `chore:`).

PRs should be focused — one logical change per PR. Reviewers will ask you
to split mixed PRs.

## Quality gates

Every PR must pass these locally before review:

```bash
# Dependencies (the crux-shared submodule must be checked out first:
# git submodule update --init --recursive)
flutter pub get

# Localization codegen (also runs automatically during build/run)
flutter gen-l10n

# Linting — zero warnings policy. Treat any warning as a blocker.
flutter analyze

# Full test suite. Must be green.
flutter test
```

CI runs the same gates on every PR; failures block merge.

## External lint engines

LintCrux does not link any lint engine into its own process. Verilator,
Verible, Slang, Svlint, GHDL, and Yosys are separate programs, resolved from
your `PATH` (or from `LINTCRUX_BUNDLED_BIN_DIR`, or from an explicit path
configured in Settings → Engines) and spawned as child processes; LintCrux
parses their stdout/stderr.

Per-engine integration tests under `test/services/engines/*/integration/`
skip with an explicit "which binary is missing" message when the engine is
not installed, so `flutter test` is green on a machine with no engines. To
run them, install the engine or download the pinned versions from
[`tool/bundled_engines.yaml`](tool/bundled_engines.yaml) and point
`LINTCRUX_BUNDLED_BIN_DIR` at the resulting directory. See the README's
"Bundled lint-engine binaries" section for the full layout.

**Version bumps in `tool/bundled_engines.yaml` are review-visible on
purpose.** A version bump can add, remove, or rename engine rules, which
changes user-visible results; call out the behavioral delta in the PR
description and update `lib/data/rules/<engine>.json` in the same change if
rule IDs moved.

This process boundary is a licensing boundary as well as an engineering
one: Verilator is LGPL/Artistic and GHDL is GPL, and invoking them as
separate programs is what keeps LintCrux's own Apache-2.0 code cleanly
separated from their terms. See [`NOTICES`](NOTICES) §1.

## Coding conventions

The complete style and architecture guide lives in two places:

- [`CLAUDE.md`](CLAUDE.md) — the day-to-day engineering manual, optimized
  for both human contributors and AI-assisted authoring. Covers Dart style,
  widget architecture, Riverpod conventions, testing requirements,
  localization rules, and the project's git workflow.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the deeper architectural
  reference: layer responsibilities, the engine-adapter and rule-database
  design, the violation/waiver model, SARIF export, and the open-core
  extension points that the closed-source overlay plugs into.

Read both before submitting non-trivial changes.

## Contributor License Agreement (CLA)

LintCrux requires a signed **Contributor License Agreement** before your
first contribution can be merged. It is a one-time step per contributor, not
per pull request.

The CLA does two things. It confirms you have the right to submit what you
are submitting — that you wrote it, or are permitted to contribute it — and
it grants Ferrite Engineering the licence to distribute your contribution.
**That includes distributing it under commercial licences**, in the paid
editions built on this open core, not only under the Apache 2.0 terms this
repository ships under. That is the difference between this and a Developer
Certificate of Origin, and it is the reason we ask for a signature rather
than a sign-off line. You keep the copyright in your contribution and may
use it however else you like.

It is modelled on the Apache Software Foundation's CLAs, so if you have
signed one of those the shape will be familiar. It is a single form covering
both individual and entity contributors — there is no separate corporate
version. Read it at [`CLA.md`](CLA.md).

### How to sign

Read [`CLA.md`](CLA.md), then write to
[support@ferriteengineering.com](mailto:support@ferriteengineering.com)
with `CLA` in the subject line and we will send you the signing
instructions. If you are contributing as part of your employment, say so
and name the employer: work done on company time usually belongs to the
company, and the CLA's employer clause asks you to confirm you have their
permission to contribute it.

We intend to move this into the pull request itself, so that accepting is a
click rather than an email. Until that is in place, it is email.

Open the pull request whenever you like — the CLA only gates the merge, and
nobody wants you to do the work twice. We will tell you if it is outstanding.

The name you sign under must be your real legal name. A pull request author
and a signatory who cannot be matched to each other is one we cannot merge.

### Licence of submitted code

Your contribution is distributed under the **Apache License 2.0**, the same
licence as the rest of this repository. You retain copyright; the CLA grants
the rights needed to use, modify and redistribute the work.


**Do not paste GPL- or LGPL-licensed code into this repository.** LintCrux
drives copyleft engines across a process boundary; it never incorporates
their source. Copying code out of Verilator, GHDL, or any other copyleft
project — including rule descriptions and help text lifted verbatim from
their documentation — cannot be accepted, because you do not
have the right to submit it under Apache 2.0. Bare rule identifiers that
LintCrux must match against an engine's own output are fine; prose is not.

## Questions

If anything about contributing is unclear, open an issue with the
`question` label or start a discussion on the repository's GitHub
Discussions page.
