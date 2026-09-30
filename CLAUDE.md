# lintcrux

Open-core EDA tool, part of Ferrite Engineering's EDACrux suite.

Architecture & engineering manual (read sections explicitly when needed; no auto-load): `docs/ARCHITECTURE.md`. It is not auto-loaded into context (no `@` prefix); locate the right anchor with `grep` first, then read the specific section.

User documentation: `docs-site/docs/`, published at `https://docs.lintcrux.app`.

## Reference implementation: WaveCrux

WaveCrux is the canonical implementation of this open-core + Pro/Enterprise overlay pattern. When a convention, file layout, naming choice, or architectural seam is unclear in this project, consult WaveCrux first:

- Open-core repo: `wavecrux` (`https://github.com/Ferrite-Engineering/wavecrux`)
- Open-core conventions: `wavecrux/CLAUDE.md`
- Engineering manual: `wavecrux/docs/ARCHITECTURE.md`

Match WaveCrux's pattern unless this project has a documented reason to diverge. When you find yourself solving a problem that WaveCrux likely already solved, read its implementation before writing a new one.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod, hand-written providers exclusively (no `riverpod_generator`, no `build_runner` — see the Riverpod section below)
- **Domain Models:** Plain immutable Dart classes with `copyWith`/equality (no freezed)
- **Lints:** `very_good_analysis` (zero-warnings policy)

The detailed engineering stack (panel layout package, native libraries, animation runtimes, etc.) is to be selected as the architecture evolves. Default to WaveCrux's choices when the domain overlaps.

## Platform Targets

Desktop-first (Linux/macOS/Windows), plus a **read-only web viewer**. **Mobile is out of scope; web is not** — a static, read-only SARIF viewer ships and is built from this open-core package.

| Platform | Notes |
|----------|-------|
| **Linux** | Primary target; x86_64 |
| **macOS** | Universal binary (Intel + Apple Silicon) |
| **Windows** | x86_64 |
| **Web** | Read-only SARIF viewer only. Renders a SARIF 2.1.0 report from `?sarif=<url>` or file upload; hosted at `app.lintcrux.app` (Cloudflare Workers Static Assets, `wrangler.jsonc`). Browsers can't spawn subprocesses, so running engines, file watching, `.lintcrux` project files, and disk persistence are desktop-only. The web build is Open-Core-only (no paid tiers on web — client-side gating is bypassable). |

There is no `Device Class` system in lintcrux — the equivalent rules in WaveCrux exist because WaveCrux runs on phone/tablet/desktop. The web viewer targets desktop-class browser viewports (the `panes` `IdeLayout` is the only layout, browser included), so read those rules in `wavecrux/CLAUDE.md` as background but do not import the breakpoint or `MobileMetrics` infrastructure unless and until lintcrux gains a phone/tablet target.

## Build & Run Commands

```bash
# No code-generation step: LintCrux declares every provider by hand.

# Run app (desktop only)
flutter run -d macos    # or -d linux, -d windows

# Run all tests
flutter test

# Run single test file
flutter test test/path/to/test_file.dart

# Browser-only tests (@TestOn('browser')), headless Chrome
tool/run_web_tests.sh

# Lint (zero warnings policy — treat warnings as errors)
flutter analyze

# Generate localization files (flutter gen-l10n)
# Runs automatically during build/run when `generate: true` is set in pubspec
flutter gen-l10n
```

## Coding Conventions

### IMPORTANT: Project config filename is `project.lintcrux` (NOT a dotfile)

LintCrux already follows the cross-suite naming convention: the canonical
per-project config is a user-named file with the `.lintcrux` extension
(e.g. `project.lintcrux`). Do NOT introduce dotfile names like
`.lintcrux.yaml`, `.lintcrux-config`, etc. for user-visible files. See
[crux-shared/docs/adr/0001-project-config-filename-convention.md](crux-shared/docs/adr/0001-project-config-filename-convention.md)
for the cross-suite rationale (SimCrux once carried a dotfile filename and
renamed away from it; the ADR locks the convention in for every
product). Pure tooling caches (e.g. a hypothetical `.lintcrux-cache/`) may
still use a dotfile name; consult the ADR before adding one.

### IMPORTANT: No Hardcoded Strings

Every user-facing string MUST come from the localization system (ARB files). No string literals displayed to users anywhere in widget, screen, or service code. The only exception is test code.

Every string has been migrated to ARB; `lib/app.dart` carries no `TODO(setup)` placeholders. Do not reintroduce the placeholder pattern for new UI.

### IMPORTANT: Tests Required for All New Code

Every new or modified Dart file in `lib/` MUST have a corresponding test file in `test/` mirroring the same directory structure. When generating production code, YOU MUST also generate the tests in the same response. Do not wait to be asked — tests are not optional.

- Domain models: Unit tests for equality, copyWith, and any computed properties.
- Services: Unit tests covering happy path, edge cases, and error handling.
- Providers: Unit tests using `ProviderContainer`. Verify state transitions and async behavior.
- Widgets: Widget tests for key interactions and layout. Locale sweep (`en`, `zh_CN`, `ja`, `ko`) once localization is set up. Use `expect(tester.takeException(), isNull)` after pumping.
- Use `mocktail` (not `mockito`).
- Test file naming: mirror the `lib/` path under `test/`, suffixing `_test.dart` (a file at `lib/<path>/<name>.dart` is tested by `test/<path>/<name>_test.dart`).

### IMPORTANT: Widget Architecture

- **One widget per file.** Each public widget class lives in its own `.dart` file in `snake_case`.
- **Keep widgets small.** If `build()` exceeds ~50 lines or has 3+ nesting levels, extract child sections into their own files.
- **Build for reuse.** Leaf widgets accept data and callbacks via constructor.
- **Stateless over stateful.** Prefer `ConsumerWidget` with Riverpod. Only use `StatefulWidget` for local mutable state (animations, focus, gesture handlers).
- **Composition over configuration.** Distinct widget variants over boolean flags.

### IMPORTANT: Comment Hygiene — comments describe the code, not the work

A comment is read by someone who has no access to the process that produced it. Write clinically: state what the code does and why it is shaped that way. Four classes of prose fail that standard and are rejected by `test/static/comment_hygiene_test.dart` (identical copy in the Pro overlay):

1. **Planning and tracking identifiers as anchors.** A work-stream, prompt, audit-item or backlog-row id, a plan phase, or a section mark in a planning document points into material a reader of this repository cannot open, and it goes stale when the plan moves on. Citing a section of a document in this repository or of a published specification (SARIF 2.1.0, CXP at `https://edacrux.app/cxp`) is fine; anchoring on a planning document, a backlog row, or another repo's issue number is not — state the reason inline instead.
2. **Dates as process notes.** A stamp narrating when work happened duplicates `git log` and tells a reader nothing about the code. Dates that are *data* — licence headers, fixture payloads, format examples — are unaffected.
3. **Session / process voice.** `this round`, `for now`, `as discussed`, `we decided`, person-addressed `TODO(...)`. If a limitation is real, state the limitation and its condition, not the schedule.
4. **Reviewer voice.** `as you can see`, `we renamed`, `before this change`, `in this commit`. Change narration belongs in the commit message.

The guard scans comment text only (string literals are skipped) and covers all four classes over `lib/`, plus class 1 over `test/` and `integration_test/`. Its allowlist is empty by design: a violation is rewritten, not listed.

### IMPORTANT: Documentation Claims Are Checked

`CLAUDE.md`, `docs/ARCHITECTURE.md`, and both verification documents make claims a reader is entitled to trust, and `test/static/doc_truth_test.dart` holds them to it:

1. **Paths must resolve.** Every repo-relative path written in backticks or as a Markdown link target must exist.
2. **Stated quantities must be derived.** A number computable from the tree (the ARB file count) must equal the computed value. Prefer prose with no figure when the quantity churns.
3. **Inventories are generated-in-place.** A document that enumerates an override list's membership does so inside an `<!-- inventory: <listName> -->` block, which must equal the parsed list exactly in both directions.

When a path points at something illustrative, write it as a template (`test/<mirror of the lib path>/<file>_test.dart`) or put it in a fenced block. Cross-repo references carry their repo prefix (`crux-shared/…`, `wavecrux/…`) so they read as prose rather than as a broken local path. Do not add allowlist entries; correct the document. The `docs-site/` pages are not covered by the guard — verify them against the code by hand.

### IMPORTANT: No references to private repositories or plans

This repository is public; the Pro overlay, the product websites and the suite's planning documents are not. Nothing tracked here — code, comments, tests, ARB descriptions, workflows, docs — names a private repository or a path inside one, cites a private planning document (a plan, plan phase or plan section, a consistency charter or ruling, a campaign), or anchors on a work-stream, prompt, audit or beta-bug tracking id. Refer to the Pro overlay's code as "the Pro overlay" and describe the seam; state a decision's reasoning inline; link a suite-level policy by its public page (`https://edacrux.app/telemetry`, `https://edacrux.app/cxp`, `https://edacrux.app/policy-reference`, …). `test/static/no_private_references_test.dart` enforces this over every tracked text file; its small allowlist covers only the user-docs pages that name the shipped Pro command-line executable, whose name matches the Pro overlay repository's.

### IMPORTANT: Screen-reader and keyboard accessibility

An external NVDA pass (2026-09-14, on WaveCrux) found the suite unusable by ear in ways every automated guard passed: silence at launch, bare "check box" Tab stops, one control under two names, a failed load announced as nothing. The same walk run over LintCrux found nameless violation-row check boxes and a rule browser that put well over a thousand Tab stops between the filters and the violations table. These are the rules for any UI change here.

- **A new or changed surface gets a focus walk.** Follow `test/accessibility/screen_reader_test.dart`: `expectFocusAnnounced` where focus must land, `walkFocus` + `expectCleanFocusWalk`, and for a primary surface a transcript golden under `test/accessibility/goldens/` that you read before committing (`flutter test --update-goldens test/accessibility`). A golden diff is a change in what a blind user hears — review it like a UI diff.
- **Focus always lands somewhere named.** The workspace screen (`lib/features/workspace/widgets/viewer_scaffold.dart`), the imported-report viewer and the web viewer are each under a `CruxFocusRegionScope`: top-level chrome goes in a `CruxFocusRegion`, the start screen is the primary region, and the panes of `LintcruxIdeLayout` are regions of their own, so never wrap a region around it. Never add an unnamed autofocus `Focus` holder around a large subtree — it absorbs every label below it.
- **One name per control, one node per row.** A label or a tooltip, not both. A violation row is one named check box: its `semanticLabel` carries the row sentence, and the cells and the row gesture are excluded from semantics. A long list is one Tab stop with arrow keys, as in `lib/features/rules/widgets/rules_panel.dart` and the violation table's `lib/features/violations/widgets/violation_row_focus.dart`; a row reachable by the pointer is reachable by the keyboard too (focus selects, Enter opens, Shift+F10 is the context menu). Never change a `FocusNode` property such as `skipTraversal` synchronously inside a focus listener — defer it to a microtask — and act only on the arrival of focus, because a node also notifies when its own properties change.
- **Errors and completions are announced** with `announceCrux`, or through `showCruxErrorSnack` / `showCruxInfoSnack`, which announce — a snackbar built by hand or a red pane is silent on desktop.
- **Space and Enter belong to the focused control.** No bare-key binding may consume them while the focused widget accepts `ActivateIntent`; bindings are dispatched by `lib/core/shortcuts/shortcut_manager_widget.dart`.
- **No arrows or box glyphs in ARB strings** — `test/static/speakable_strings_test.dart` enforces it. Write menu paths as `Settings > Engines`.

### Dart Style

- Effective Dart guidelines.
- Files: `snake_case.dart`. Classes: `PascalCase`. Variables/functions: `camelCase`. Constants: `camelCase` (Dart convention). Providers: `camelCase` ending in `Provider`. Private members: `_prefixed`.
- No `!` operator unless the non-null contract is provably guaranteed and documented with a comment.

### Riverpod

- **Every provider is declared by hand, at both tiers.** Hand-written
  providers are *required* for the open-core → Pro extension-point seams —
  an overridable `final FooProvider fooProvider = Provider(...)` whose type
  the Pro overlay targets with `overrideWith` — and are the natural choice
  for simple state holders and cross-suite-shared providers.
- **There is no code-generation toolchain.** `build_runner`,
  `riverpod_generator` and `riverpod_annotation` are not dependencies and
  no CI job runs a codegen step. Do **not** reintroduce them for a single
  provider; declare it manually in the style of its neighbours.
- Providers live in `providers/` within a feature module, or in the
  relevant `services/` / `domain/` folder when the state is a
  services-layer or shared-app-state concern (see ARCHITECTURE.md §6.2 —
  e.g. `currentProjectProvider` lives in `services/project/`, not
  `features/`).
- Providers should be thin — delegate logic to services.
- Never use `ref.read` in a widget's `build` method — use `ref.watch`.

### Localization

- 4 locales ship: English (`en`), Simplified Chinese (`zh_CN`), Japanese (`ja`), Korean (`ko`). Same as WaveCrux.
- ARB files live in `lib/l10n/` — five files (`app_en.arb`, `app_zh_CN.arb`, `app_zh.arb`, `app_ja.arb`, `app_ko.arb`). `app_en.arb` is the primary source of truth.
- `app_zh.arb` mirrors `app_zh_CN.arb` (identical translations, `@@locale` set to `zh`) so users on a bare `zh` locale get Simplified Chinese.
- Every message must have a corresponding `@<key>` metadata entry with a `description` field (in English).
- **Translation house style and glossary:** [`.claude/instructions.md`](.claude/instructions.md) is the canonical house style for CJK translations (core principles, mandatory LintCrux glossary, suite-wide term rulings, ICU plural rules including the `=1` case requirement, punctuation-width rules, button-label length targets, per-language rules). [`assets/l10n/glossary.json`](assets/l10n/glossary.json) is the machine-readable version of the glossary + acronym/brand never-translate lists + pluralization templates. Read both before adding or modifying any CJK string, and when DeepSeek/Claude/another translator audits the ARB files, point them at these two files first. The suite-wide canonical source is `wavecrux/.claude/instructions.md` — the Suite-Wide Terms table there is binding and this repo's copy must not contradict it.
- **Static house-style guard:** [`test/static/l10n_house_style_guard_test.dart`](test/static/l10n_house_style_guard_test.dart) enforces key parity across locales, the `app_zh.arb` ↔ `app_zh_CN.arb` mirror, ICU `=1` plural cases, U+2026 ellipsis, and CJK punctuation width. It must pass in every commit that touches `lib/l10n/`.

Localization is fully scaffolded (`l10n.yaml` → generated `L10N`); every widget test carries the five-file locale sweep. Mirror `wavecrux/lib/l10n/` conventions when adding strings.

## Project Structure

The directory layout mirrors WaveCrux's open-core structure:

```
lib/
├── app.dart            # runLintcrux + bootstrap functions, root widget
├── main.dart           # calls runLintcrux(args: args)
├── core/               # Shared utilities, constants, extensions, theme, shortcuts, CLI, router
├── l10n/               # Localization: five ARB source files (en/zh_CN/zh/ja/ko)
├── data/               # Bundled data assets (rule databases per engine, rule_aliases.json)
├── domain/             # Pure Dart: models, enums, interfaces — ZERO Flutter imports
├── services/           # Non-UI services — engines, sarif, violations, projects, remote/cxp, transformers
├── features/           # Feature modules (each owns its providers, screens, widgets)
├── shared/             # Shared widgets
└── plugins/            # Open-core → Pro extension-point provider registry
```

See `wavecrux/lib/` for the reference the layout mirrors.

## Key Architecture Rules

- **Domain layer has zero Flutter imports.** Pure Dart only. Models, enums, and interfaces live here.
- **Features depend on domain interfaces**, not service implementations.
- **The Pro overlay consumes this repo as a Git submodule.** It registers Pro/Enterprise concrete implementations via Riverpod overrides spread into the `bootstrap()` `ProviderScope`. Do not fork open-core code in the Pro overlay; if a Pro feature needs a new hook, define the extension-point interface here first, push, bump the submodule pin, then add the Pro implementation. See `wavecrux/CLAUDE.md` for the binding rule.
- **Open-core conflict semantics:** open-core overrides come first; Pro overrides spread last; later overrides win. Mirrors WaveCrux.

### IMPORTANT: Verification Documentation Required

The `verification/` folder is the binding pre-release manual-verification reference for every Open Core LintCrux feature. Verification entries are written as features land — not retrofitted later.

- [`verification/VERIFICATION_GUIDE.md`](verification/VERIFICATION_GUIDE.md) — detailed pre-release verification reference for every Open Core feature.
- [`verification/VERIFICATION_CHECKLIST.md`](verification/VERIFICATION_CHECKLIST.md) — quick sign-off bullet list per release.
- [`verification/fixtures/`](verification/fixtures/) — committed fixtures (per-engine log captures with `.expected.sarif` golden files, synthetic Verilog/VHDL sources reproducing violation classes, CXP receive scenarios) and regenerator scripts under `tool/`. Layout documented in `verification/fixtures/README.md`.

When you implement a new Open Core feature, add a lint-engine adapter, add an extension-point seam, or make any change visible to a user of the open-core build, the same change set MUST:

1. **Add or update the feature's section** in `verification/VERIFICATION_GUIDE.md`. Populate: what it does (plain language), setup, step-by-step expected behavior, edge cases. The Automation Assessment / Coverage tag is mandatory on every bullet.
2. Add or update the corresponding bullet group in `verification/VERIFICATION_CHECKLIST.md`, including any new fixture references.
3. Commit any new fixtures under `verification/fixtures/<engine>/` alongside their `.expected.sarif` (or `.expected.*.json`) companions, with the regenerator script under `tool/` documented in `verification/fixtures/README.md`.
4. **Pro features go in the Pro overlay verification, not here.** If your work is a Pro/Enterprise feature (managed waivers, Pro trend dashboard, enterprise policy push, audit logging), the verification entry belongs in the Pro overlay's own verification guide. This open-core guide covers only what every open-core user can see.
5. **Don't ship implementation without its verification entry.** A feature shipping in code without a populated verification entry in the same commit set is a code-review-blocking defect — same rule as WaveCrux.

## User documentation lives in `docs-site/`

`docs-site/docs/` (MkDocs Material) is the source of truth for user
documentation, published at `https://docs.lintcrux.app`. A change to
user-visible behaviour — a label, shortcut, flag, config key, file
format, tier or platform availability — updates the affected page in the
same change. Build with `mkdocs build --strict` from `docs-site/` (pinned
versions in `.github/workflows/docs.yml`); CI fails a broken link or
anchor. Keep page file names stable: in-app help links point at them.

## Git Conventions

- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- Branch naming: `feature/xxx`, `fix/xxx`. `main` is always deployable.

## Changes land through pull requests

Until the 1.0 code freeze, maintainers commit directly to `main`. From the
code freeze on, every change — by anyone — lands through a pull request
whose description documents the issue or feature, the fix or
implementation, how it was verified (tests added, CI gates passed), and
the user documentation updated in the same PR. Contributors sign a CLA
before a first merge, as described in `CONTRIBUTING.md`.

## Licensing

Open core is licensed under the Apache License 2.0 — see [`LICENSE`](LICENSE) and [`NOTICES`](NOTICES). Every hand-written Dart file (everything except the generated `lib/l10n/generated/` output) carries the `SPDX-License-Identifier: Apache-2.0` header. The LintCrux name and logo are covered by [`TRADEMARK.md`](TRADEMARK.md), not by the code licence.

## Suite UI consistency (MANDATORY for any UI change)

The four Crux apps (WaveCrux, NetCrux, LintCrux, SimCrux) are built as if they
were ONE app. The rules for any UI surface:

1. **Mirror-check:** a change to a shared surface (menus, toolbar, status bar,
   docks/panels, welcome screen, window chrome, Settings, dialogs, shortcuts,
   shared l10n keys) must be applied to the OTHER THREE apps in the same
   session — or explicitly flagged as pending in your final report. Never
   diverge silently. The sibling apps live at
   sibling checkouts of `wavecrux`, `netcrux`, `lintcrux` and `simcrux`.
2. **New surface:** adding a dialog / panel / dock tab / settings category /
   banner here requires answering "do the other three apps need this?" — and
   generic chrome starts life in crux-shared (`crux_dock`, `crux_workspace`,
   `crux_settings_ui`, `crux_cxp_ui`, ...), never as an app-local copy.
3. **Canon details:** WaveCrux is canonical unless the suite has decided
   otherwise. Workflow dialogs are `barrierDismissible: false`; settings
   categories use the shared `CruxSettingsCategoryId` order and icons; l10n
   keys for shared strings use WaveCrux-style names in all four apps; the
   Language picker requires `MaterialApp.locale` wiring.
4. **Verify like CI:** `flutter analyze --fatal-infos --fatal-warnings` (the
   crux-shared Consumer CI fails on infos; plain `dart analyze` won't) + the
   full test suite for every repo you touched.
5. **User docs:** if you changed a user-visible usage model (panel
   behavior, shortcut, settings layout, menu location, dialog flow), update
   the affected `docs-site/` page in the same change — grep `docs-site/docs/`
   for the OLD wording — and check the other three products' user docs when
   the change was suite-wide.
