# LintCrux (Open Core) — Integration Test Status & Backlog

Flutter `integration_test/` suite exercising a fully running open-core LintCrux
build (started via `bootstrap` from `package:lintcrux/app.dart`). Harness:
`integration_test/helpers/app_driver.dart` (`bootLintcrux` + `pumpUntil` /
`rootContainer` / workspace round-trip primitives). Mirrors the WaveCrux /
NetCrux harness; never `pumpAndSettle(Duration)` (the live binding treats the
duration as a per-pump interval, not a timeout).

LintCrux boots into a `ProviderScope` (not `UncontrolledProviderScope`), so
`rootContainer` resolves the container via `ProviderScope.containerOf` off the
`LintcruxApp` element.

**Semantics hardening.** The macOS embedder can arrive with OS accessibility
enabled, and its `AccessibilityBridge` segfaults
(`CreateRemoveReparentedNodesUpdate`, SIGSEGV) under the semantics-node churn
of a seeded violation table. `bootLintcrux` therefore (a) pins the test
dispatcher's semantics value off (`disablePlatformSemantics` — must run inside
the test body; the harness wipes test values at `testWidgets` start) and
(b) mounts the app inside `ExcludeSemantics` via the `bootstrap(wrapApp:)`
seam, so the semantics tree stays trivially small for the whole run.

## Running

Desktop-only. Run each file in its own invocation; retry on the environmental
macOS app-relaunch error ("Unable to start the app on the device").

```bash
flutter test integration_test/workspace/restore_round_trip_test.dart -d macos
```

## Implemented (green on macOS)

- [x] Cold-boot empty-canvas state — `workspace/empty_canvas_boot_test.dart`
      (also the harness smoke test)
- [x] Workspace auto-save + restore round-trip —
      `workspace/restore_round_trip_test.dart`
- [x] Theme preset switch flips MaterialApp brightness —
      `theme/theme_switch_test.dart`
- [x] Core product loop: violation table seed → filter → select →
      inspector — `violations/violation_table_journey_test.dart`. Uses the
      seeded-lint-run harness (below); asserts table rendering, debounced
      rule-substring filtering, row selection, and the inspector detail
      pane against a fixture project.
- [x] Named workspace save / reset / open round-trip (`saveAs`/`loadFrom`) —
      `workspace/named_workspace_test.dart`.
- [x] Split-pane + move-tab-between-panes mutation contract —
      `workspace/split_pane_test.dart`.
- [x] CLI multi-file / project open → tab structure —
      `tabs/cli_multi_file_test.dart`. LintCrux's CLI positionals are
      `.lintcrux` project paths (not raw source files), so this uses
      `createFixtureProject` × 3 rather than a literal port of NetCrux's
      raw-source-file version.
- [x] CXP server lifecycle (LintCrux uses `CxpServerLifecycle` AsyncNotifier —
      different provider shape than NetCrux's `cxpServerHostProvider`) —
      `remote_control/cxp_server_lifecycle_test.dart`. Asserts on the
      `CxpServerLifecycleState.running`/`error`/`boundPort` fields instead
      of a nullable server handle.
- [x] Violation table sort-order contract (header taps) —
      `violations/violation_table_sort_order_test.dart`.
- [x] Source preview jump-to-source — extended
      `violations/violation_table_journey_test.dart`.
- [x] Engine aggregation result rendering —
      `violations/engine_aggregation_test.dart`.
- [x] `.lintcrux-session` open → replay — `workspace/session_open_replay_test.dart`.
      Drives the real "Open Session…" empty-canvas button through
      `OpenProjectInWorkspace.openSession`; asserts the referenced
      project loads AND the session's filter/sort/severity/engine
      state replays onto the new tab's `violationTableStateProvider`.
      Exposed and fixed two real production defects while landing:
      (1) `ViolationTableNotifier` retained its per-project filter
      state keyed off `crux_projects`' root-scoped, asynchronously
      converging `activeProjectIdProvider` — any mutation applied
      synchronously right after a project load (session replay,
      workspace-tab hydration) could be silently discarded once the
      registry sync caught up and rebuilt the notifier against the new
      id. Now keyed off the TAB's own `currentProjectProvider`, which
      updates synchronously and is intrinsically tab-scoped. (2)
      `openSession` (and `ProjectTabContent`'s workspace-tab hydration)
      called `setSortColumn`, which always resets to ascending —
      descending sorts were silently lost on replay/restore. Added
      `ViolationTableNotifier.setSort(column, {ascending})` and
      switched both call sites to it.
- [x] Workspace-open error paths — `workspace/workspace_open_error_path_test.dart`.
      Two real-app journeys through the empty-canvas buttons: (1)
      `Open Workspace…` on a named document whose second tab's project
      file has since been deleted skips only that tab
      (`OpenProjectInWorkspace.openWorkspace`'s per-tab try/catch)
      instead of aborting the whole load; (2) `Open Session…` on a
      missing `.lintcrux-session` path surfaces the real error message
      via a snackbar instead of failing silently.

## Pending — straight ports from the NetCrux suite

(none remaining — all four items above have landed)

## Seeded lint run — harness available

The prerequisite landed in `helpers/app_driver.dart`: `createFixtureProject`
(writes a `.lintcrux` + sources enabling only a nonexistent engine id, so no
real binary ever runs), `openFixtureProject` (opens through the real
`OpenProjectInWorkspace` seam, hydrates the NEW TAB's own per-tab
`currentProjectProvider` — the root container is never touched, matching the
production File → Open flow — and returns the per-tab container),
`parseVerilatorFixture` (real
`VerilatorParser` over fixture stderr lines), and `seedLintRun` (runs the
parsed violations through the runner's transformer pipeline — severity
overrides → pragmas → managed waivers — then replaces the engine slice in the
per-tab store). Re-seeding after a waiver / override edit models "the next
run" deterministically. The Pro driver re-exports the whole surface.

- [x] Violation table filter / select →
      `violations/violation_table_journey_test.dart`
- [x] Violation table sort-order contract (header taps) —
      `violations/violation_table_sort_order_test.dart`. Taps the rule
      column header twice (new-column-ascending, then flip-to-
      descending) and asserts both `visibleViolationsProvider`'s order
      and the on-screen row y-positions reorder to match.
- [x] Source preview jump-to-source on a violation — extended
      `violations/violation_table_journey_test.dart`'s row-select step:
      after selecting a row, asserts `sourcePreviewWindowProvider`
      resolves the selected violation's file/line, and re-asserts on a
      second row selection that the preview updates to the new file.
- [x] Engine aggregation result rendering —
      `violations/engine_aggregation_test.dart`. Seeds two engine ids
      into the same tab via `seedLintRun` and asserts the table shows
      the union; re-seeds one engine and asserts only that engine's
      rows change while the other engine's rows survive untouched.
