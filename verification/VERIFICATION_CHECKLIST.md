# LintCrux (Open Core) — Verification Checklist

> **Purpose.** Quick pre-release sign-off list. For step-by-step instructions, fixture inventory, and rationale, see `VERIFICATION_GUIDE.md` (sibling, this folder).
>
> **Pro overlay.** If you are signing off a Pro build, run this checklist first, then run the Pro overlay's own checklist for the Pro/Enterprise delta.

> **Coverage markers.** Same taxonomy as WaveCrux's checklists. Bullets tagged `WIDGET` or `INTEGRATION_TEST` (without `pending`) are CI-protected.

---

## Release metadata

- LintCrux version: ____________________
- Open Core SHA: ____________________
- Verifier: ____________________
- Date: ____________________
- Platform(s) tested: ____________________

---

## Pre-flight

- [ ] All fixtures present under `verification/fixtures/` — `[Coverage: MANUAL]`
- [ ] Lint engines installed on the verifier's machine (Verilator + Verible + Yosys + GHDL as needed for the phase) — `[Coverage: MANUAL]`

---

## Foundation

See `VERIFICATION_GUIDE.md` §3.

- [ ] CI matrix (analyze + test + build) green on Linux / macOS / Windows — `[Coverage: CI]` (`.github/workflows/ci.yml`)
- [ ] Boot to empty-canvas without a project; Settings / About / menu bar reachable — `[Coverage: WIDGET]` (`test/widget_test.dart`)
- [ ] The welcome screen's Recent projects list shows projects opened in earlier sessions, most recent first; a deleted entry is removed when clicked — `[Coverage: UNIT]` (`test/features/workspace/providers/recent_projects_provider_test.dart`) + `[Coverage: MANUAL]`
- [ ] A `<design>.crux-project` manifest opens its `lint:` project from the command line and from Open Project on every desktop platform; a legacy bare `.crux-project` opens with a rename notice; a folder holding two manifests opens nothing and names both — `[Coverage: UNIT]` (`test/features/workspace/services/crux_project_resolution_test.dart`, `test/features/workspace/services/open_project_in_workspace_test.dart`) + `[Coverage: WIDGET]` (`test/features/project/services/open_project_feedback_test.dart`) + `[Coverage: MANUAL]`
- [ ] Theme light/dark/preset switch repaints chrome — `[Coverage: MANUAL]`
- [ ] OS "increase contrast" accessibility toggle shifts LintCrux to the high-contrast palette (MaterialApp `highContrastTheme`/`highContrastDarkTheme` wired) — `[Coverage: AUTOMATED]` (`test/core/theme/lintcrux_theme_test.dart`, `test/widget_test.dart`) + `[Coverage: MANUAL]` (OS toggle)
- [ ] Locale sweep en / zh_CN / ja / ko renders without overflow — `[Coverage: WIDGET]` (`empty_canvas_content_test.dart`)
- [ ] Window shrinks only to the 800×500 logical minimum on every desktop runner — `[Coverage: MANUAL]`
- [ ] File-picker failure surfaces a localized snackbar (no silent dead button) — `[Coverage: MANUAL]`
- [ ] **A first-run user has something to open.** `File → Open Project…` → `examples/getting-started/project.lintcrux` → `Tools → Run All Engines` reports 7 violations over 6 rules; `examples/vhdl-getting-started/` reports 3; with no engine on `PATH`, `File → Import SARIF report…` → `examples/getting-started/report.sarif` populates the table — `[Coverage: UNIT]` (`test/examples/examples_test.dart`) + `[Coverage: MANUAL]` (live build)
- [ ] Domain models + in-memory `ViolationStore` indices + SARIF round-trip — `[Coverage: UNIT]` (`test/domain/**`, `test/services/violations/**`, `test/services/sarif/**`)

## Verilator + Verible + Slang Aggregation

See `VERIFICATION_GUIDE.md` §4.

- [ ] Core loop end-to-end (open → seeded run → table → filter → select → inspector) on a live macOS build — `[Coverage: INTEGRATION_TEST]` (`integration_test/violations/violation_table_journey_test.dart`)
- [ ] All enabled engines run in parallel; violations stream in as each finishes — `[Coverage: UNIT]` (`parallel_engine_runner_*.dart`); multi-engine `replaceFromEngine` union rendering in the live table — `[Coverage: INTEGRATION_TEST]` (`integration_test/violations/engine_aggregation_test.dart`)
- [ ] Per-engine parser (format / continuation / related-locations) → golden SARIF — `[Coverage: GOLDEN]` (`engine_golden_test.dart` + `test/fixtures/engines/**`)
- [ ] Sort by any column; filter chips (severity / engine / rule-substring / file-glob) AND across dimensions — `[Coverage: UNIT/WIDGET]` (`test/features/violations/**`); header-tap sort-cycle contract on a live build — `[Coverage: INTEGRATION_TEST]` (`integration_test/violations/violation_table_sort_order_test.dart`)
- [ ] Plain **left-click** anywhere in a violation row body (severity / engine / rule / file / line / tooltipped message cell) highlights the row with no perceptible delay and populates the inspector + source preview; double-click selects **and** opens the editor; right-click selects before opening the menu — `[Coverage: WIDGET]` (`test/features/violations/widgets/violation_table_row_test.dart`, locale sweep) + `[Coverage: MANUAL]` (release build — the 2026-07-16 beta bug was invisible to tests that advanced the clock past the double-tap window)
- [ ] Inspector + source-preview populate from the selected violation — `[Coverage: WIDGET]` (`test/features/inspector/**`, `test/features/source_preview/**`); jump-to-source on row selection on a live build — `[Coverage: INTEGRATION_TEST]` (`integration_test/violations/violation_table_journey_test.dart`)
- [ ] Double-tap / Open-in-editor shells out to the configured editor; bad command → snackbar reproducer — `[Coverage: UNIT]` (`test/services/click_to_source/**`)
- [ ] Verible against a **stock upstream `verible-verilog-lint`** produces violations, not a clean run (§4.3.1) — column ranges `file:L:C-C2:` parse, `[Style: …]` tags are stripped from messages, stderr diagnostics are read, and the rejected `--lint_output=jsonline` flag triggers an automatic text-mode retry — `[Coverage: UNIT]` (`verible_parser_test.dart`, `verible_engine_test.dart`, `engines/verible/generated/upstream_text_column_range/`) + `[Coverage: MANUAL]` (real upstream binary)
- [ ] **No silent false clean:** an engine whose binary exits non-zero with nothing parseable reports **failed** with an output excerpt, never "Completed, 0 violations" — `[Coverage: UNIT]` (`verible_engine_test.dart` "non-zero exit contract")
- [ ] Inline `// verilator lint_off` pragma suppresses the matching violation — `[Coverage: UNIT]` (`pragma_waiver_*.dart`)
- [ ] Per-rule severity override round-trips through `.lintcrux` and applies on re-run; an override chosen in Settings is saved to the tab's project file — `[Coverage: UNIT]` (`severity_override_*.dart`, `test/services/project/current_project_provider_test.dart`) + `[Coverage: WIDGET]` (`test/features/engine_config/widgets/severity_override_list_test.dart`)
- [ ] Export SARIF / JSON / CSV / HTML — `[Coverage: UNIT]` (`violation_exporters_test.dart`)
- [ ] Rule metadata resolves from the bundled rule database — `[Coverage: UNIT]` (`rule_database_test.dart`)
- [ ] Verilator against a **stock upstream `verilator`** reports its opt-in lint set, not a clean run — the adapter passes `-Wall` by default (without it UNUSEDSIGNAL / UNDRIVEN / DECLFILENAME / PINMISSING / VARHIDDEN / UNUSEDPARAM can never fire) and `perEngineOptions.verilator.warnFlags` overrides it — `[Coverage: UNIT]` (`verilator_engine_test.dart` "warnFlags") + `[Coverage: MANUAL]` (real binary)
- [ ] `verilator.json` covers every code the installed Verilator accepts, each with the `verilator.org/warn/<CODE>` help link — `[Coverage: UNIT]` (`rule_database_test.dart`)
- [ ] **Project-fixture goldens are captured, never authored.** `dart run tool/capture_project_fixtures.dart` reproduces every `expected.sarif.json` byte-for-byte; each fixture's `capture.json` names the binary and version behind it, and any engine the host lacked is listed under `unverified` with a reason — `[Coverage: GOLDEN]` (`project_fixture_golden_test.dart`) + `[Coverage: MANUAL]` (re-capture on a host with all engines)
- [ ] Tier-gate: engine aggregation is Open Core; only engine-native pragmas are free (managed waivers / baseline / trends are Pro) — `[Coverage: MANUAL]`

## Yosys Checks + VHDL Foundation

See `VERIFICATION_GUIDE.md` §5.

- [ ] Yosys adapter maps diagnostics → violations (module fallback when file:line absent) — `[Coverage: UNIT]` (`test/services/engines/yosys/**`)
- [ ] A missing or bad Yosys binary makes `yosys` and `cdc` unavailable (exit 3 headless, hint names `--yosys-path`); a Custom Yosys path and `--yosys-path` reach both, and **Probe** reports that binary — `[Coverage: UNIT]` (`test/services/engines/cdc/cdc_engine_unavailable_test.dart`, `test/services/headless/headless_runner_test.dart`)
- [ ] Yosys canned output → golden SARIF — `[Coverage: GOLDEN]` (`engines/yosys/generated/**`)
- [ ] `yosys` engine is default-disabled (opt-in via `enabledEngineIds`) — `[Coverage: UNIT]`
- [ ] GHDL availability probe resolves bundled → PATH → null — `[Coverage: UNIT]` (`ghdl_availability_service_test.dart`)
- [ ] Mixed-language `.lintcrux` schema (`ProjectSourceFileLanguage`, auto-detect) round-trips — `[Coverage: UNIT]` (`project_file_codec_test.dart`)
- [ ] Tier-gate: Open Core, no gating — `[Coverage: MANUAL]`

## Project Files, VHDL, Web Read-Only

See `VERIFICATION_GUIDE.md` §6.

- [ ] GHDL + Svlint engines + parsers → golden SARIF (default-disabled) — `[Coverage: UNIT/GOLDEN]` (`engines/ghdl/**`, `engines/svlint/**`)
- [ ] A project-root `.rules.verible_lint` enables Verible's `--rules_config_search` and a project-root `.svlint.toml` reaches Svlint via `--config` (sources outside the root included); editing either invalidates the Pro lint cache for that engine — `[Coverage: UNIT]` (`verible_engine_test.dart`, `svlint_engine_test.dart`, `cache_fingerprint_test.dart`)
- [ ] Language routing: each engine lints only its accepted sources; run-status shows the subset — `[Coverage: UNIT]` (`engine_language_router_test.dart`)
- [ ] `.f` filelist import (incdir / define / recursive `-f` / env expansion / cycle rejection) — `[Coverage: UNIT]` (`filelist_reader_test.dart`)
- [ ] Custom per-engine binary path (Settings + CLI override + Probe), saved across restarts and applied to a restored tab's first run — `[Coverage: UNIT]` (`test/services/persistence/engine_binary_overrides_settings_codec_test.dart`, `test/core/cli/**`)
- [ ] Per-file incremental re-run patches only the changed files; indices stay correct — `[Coverage: UNIT]` (`partial_replace_index_sync_test.dart`)
- [ ] Streaming SARIF reader ingests large docs in bounded memory; malformed rejected without corrupting prior state — `[Coverage: HYBRID]` (`streaming_sarif_reader_*.dart`)
- [ ] Web read-only viewer: `?sarif=<url>` / file upload renders the table; nothing uploaded to a server; source-preview shows the no-disk placeholder — `[Coverage: WIDGET]` (`test/features/web_viewer/**`) + `[Coverage: MANUAL]` (real browser)
- [ ] Web viewer loads rule metadata: selecting a row shows tags and **Learn more** in the Inspector, and the Rules panel lists rules — `[Coverage: UNIT]` (`test/services/rules/rule_database_provider_test.dart`, rule database loads without the engine registry) + `[Coverage: MANUAL]` (real browser)
- [ ] Web build smoke — `[Coverage: CI]` (`.github/workflows/ci.yml` `build-web`)
- [ ] Tier-gate: Open Core; the web viewer has no Pro affordances — `[Coverage: MANUAL]`

## Workspace + Multi-Tab + Split-Pane Adoption

Per `VERIFICATION_GUIDE.md` §6.5.

- [ ] Empty-canvas startup state renders on fresh launch with no auto-saved workspace — `[Coverage: WIDGET]`
- [ ] Empty-canvas locale sweep (en / zh_CN / zh / ja / ko) — `[Coverage: WIDGET]`
- [ ] **Open Project…** / **Open Workspace…** / **Open Session…** / **New Project…** buttons each fire their picker — `[Coverage: MANUAL]`
- [ ] Recent-projects empty-state placeholder renders correctly — `[Coverage: WIDGET]`
- [ ] Multi-tab: opening N `.lintcrux` files yields N tabs with distinct `LintRunNotifier` / `ViolationStore` / filter state — `[Coverage: INTEGRATION_TEST]` (test/features/workspace/providers/tab_overrides_factory_test.dart)
- [ ] Switching tabs preserves per-tab cursor / filter / sort / selection — `[Coverage: MANUAL]`
- [ ] Startup-provider seams keep overlay listeners alive via held container subscriptions (a `read`-realized listener is paused and drops every event) — `[Coverage: UNIT]` (test/plugins/eager_startup_providers_test.dart, test/plugins/per_tab_startup_providers_test.dart)
- [ ] Trend ingest failure is reported to `trendIngestDiagnosticsSinkProvider` and the ingestion subscription survives for later runs — `[Coverage: UNIT]` (test/services/trends/lint_run_completion_listener_provider_test.dart, test/services/trends/trend_ingest_diagnostics_provider_test.dart)
- [ ] Closing the last tab restores the empty-canvas state — `[Coverage: MANUAL]`
- [ ] Split-pane: `Cmd/Ctrl+\` splits the active pane; cross-pane tab drag moves a tab — `[Coverage: MANUAL]` (mutation contract: `[Coverage: INTEGRATION_TEST]` integration_test/workspace/split_pane_test.dart)
- [ ] Split-pane: closing the last tab in a non-active pane auto-collapses to single-pane — `[Coverage: MANUAL]` (empty-pane-collapse contract: `[Coverage: INTEGRATION_TEST]` integration_test/workspace/split_pane_test.dart)
- [ ] Workspace auto-save: quit + relaunch restores tabs + panes + active selection — `[Coverage: MANUAL]`
- [ ] Workspace auto-save: corrupt `workspace.json` falls back to empty workspace (no crash) — `[Coverage: INTEGRATION_TEST]` (test/features/workspace/providers/workspace_provider_test.dart)
- [ ] Workspace save/load round-trip: `Save Workspace As…` → `Open Workspace…` reproduces the exact arrangement — `[Coverage: INTEGRATION_TEST]` (test/features/workspace/providers/workspace_provider_test.dart, integration_test/workspace/named_workspace_test.dart) + `[Coverage: MANUAL]` for UI
- [ ] Tab export as session: `Export Tab as Session…` → `Open Session…` reproduces the active tab's filter / sort / selection — `[Coverage: INTEGRATION_TEST]` (integration_test/workspace/session_open_replay_test.dart) + `[Coverage: MANUAL]` for the export half
- [ ] `Open Workspace…` on a document whose tabs reference a since-deleted project file skips only that tab; `Open Session…` on a missing file surfaces the real error via a snackbar — `[Coverage: INTEGRATION_TEST]` (integration_test/workspace/workspace_open_error_path_test.dart)
- [ ] CLI: `lintcrux a.lintcrux b.lintcrux` opens two tabs — `[Coverage: INTEGRATION_TEST]` (integration_test/tabs/cli_multi_file_test.dart, 3-project variant) + `[Coverage: MANUAL]` for UI
- [ ] CLI: `lintcrux --workspace name.lintcrux-workspace` opens a named workspace — `[Coverage: MANUAL]` (parser path: `[Coverage: WIDGET]` test/core/cli/cli_args_parser_test.dart)
- [ ] CLI: `lintcrux --session name.lintcrux-session` opens a session as a tab — `[Coverage: MANUAL]`
- [ ] Auto-reload (mode = auto): editing a source in tab A re-runs only tab A's engines — `[Coverage: MANUAL]` (structural seam: `[Coverage: INTEGRATION_TEST]` test/features/workspace/auto_reload_multi_tab_test.dart)
- [ ] Auto-reload (mode = prompt): editing a source in tab A shows the Re-run now snackbar for tab A only, and Re-run now runs tab A's engines; the mode comes from Settings > General — `[Coverage: WIDGET]` (`test/features/auto_reload/widgets/auto_reload_host_test.dart`) + `[Coverage: MANUAL]`
- [ ] Severity overrides / saved filter presets in tab A survive tab A's incremental re-run — `[Coverage: INTEGRATION_TEST]` (test/features/workspace/auto_reload_multi_tab_test.dart) + `[Coverage: MANUAL]` for the UI surface
- [ ] Presets saved or deleted from the Filter preset dropdown are written to the project's `.lintcrux` `filterPresets` and listed again after reopening the project — `[Coverage: UNIT]` (`test/features/violations/providers/saved_filter_presets_provider_test.dart`)
- [ ] Settings screen + command palette + menu bar accessible from the empty-canvas state without a project open — `[Coverage: MANUAL]`
- [ ] Every open flow (File → Open, CLI positional, filelist import, session/workspace restore) lands the project in a NEW TAB's container; the root `currentProjectProvider` stays null — `[Coverage: UNIT]` (test/features/workspace/services/open_project_in_workspace_test.dart)
- [ ] Tab Diagnostics / App Diagnostics / Settings dialogs resolve the ACTIVE tab's per-tab providers (two tabs: reports and severity-override edits follow the front tab) — `[Coverage: MANUAL]` (guide §6.5.10)
- [ ] Tab Diagnostics and App Diagnostics report only measured values: resident memory, each engine's binary source and probed version (`not detected` when the probe got nothing), and a duration only for an engine that ran; no zero or placeholder stands in for a missing value — `[Coverage: UNIT]` (test/features/diagnostics/providers/diagnostics_providers_test.dart, test/domain/models/diagnostics/diagnostics_report_test.dart)
- [ ] Release build: Tools → Tab Diagnostics / App Diagnostics open nothing and name Settings → General until Enable diagnostics is on; the switch appears only in release builds and survives a relaunch — `[Coverage: UNIT]` (test/app_action_dispatch_test.dart, test/features/settings/widgets/settings_general_section_test.dart, test/services/persistence/diagnostics_enabled_settings_codec_test.dart) + `[Coverage: MANUAL]`
- [ ] Web: answering the usage-statistics disclosure at app.lintcrux.app sticks — reload the page and it does not come back, and `Settings → Privacy` still shows the answer — `[Coverage: UNIT]` (test/core/telemetry/lintcrux_web_telemetry_storage_test.dart) + `[Coverage: MANUAL]`
- [ ] macOS: double-clicking each registered document type in Finder (`.lintcrux`, `.crux-project`, `.lintcrux-workspace`, `.lintcrux-session`, `.f`, `.sarif`, an HDL source) opens it through the matching command, both on a cold launch and with the app running; Open With on an unrelated file shows the refusal snackbar — `[Coverage: UNIT]` (test/features/workspace/incoming_file_open_test.dart) + `[Coverage: MANUAL]` (the native `application(_:open:)` half runs only in a real app)
- [ ] Filter-preset **Manage presets…** lists the tab's saved presets (not "No saved presets yet.") and its delete affordance removes them from the dropdown behind it — `[Coverage: WIDGET]` (`filter_preset_dropdown_test.dart` — two-container shape, mutation-verified) + `[Coverage: STATIC]` (crux-shared `route_mounted_scope_leak_test.dart` guards the class) (guide §6.5.10a)
- [ ] Tier-gate scenarios — the workspace, multi-tab and split-pane shell is Open Core, no gating applies. The disabled "Move to New Window" tab-bar entry renders correctly until Flutter multi-window stabilizes — `[Coverage: MANUAL]`

## Cross-Probing & CXP Receive

Per `VERIFICATION_GUIDE.md` §7.

- [ ] CXP server starts on launch when `cxpServerEnabled` is true and binds to `cxpServerPort` (default 54324) — `[Coverage: INTEGRATION_TEST]` (test/features/remote/cxp_server_lifecycle_test.dart, integration_test/remote_control/cxp_server_lifecycle_test.dart)
- [ ] CXP server does not start when `cxpServerEnabled` is false — `[Coverage: INTEGRATION_TEST]` (test/features/remote/cxp_server_lifecycle_test.dart, integration_test/remote_control/cxp_server_lifecycle_test.dart)
- [ ] Cross-probe panel status line flips immediately when the Settings toggle is changed — `[Coverage: MANUAL]` (underlying start/stop-on-toggle contract: `[Coverage: INTEGRATION_TEST]` integration_test/remote_control/cxp_server_lifecycle_test.dart)
- [ ] Discovery manifest is written on start and removed on graceful shutdown — `[Coverage: MANUAL]` (write path: `[Coverage: INTEGRATION_TEST]` via lifecycle test)
- [ ] Peers appearing in the suite-shared `crux/cxp/peers/` directory (per-user app-data root, NOT the per-app container) are reflected in the cross-probe panel within the scan interval; removed when the file vanishes; LintCrux never lists itself — `[Coverage: INTEGRATION_TEST]` (test/features/remote/cxp_server_lifecycle_test.dart)
- [ ] **Mutual-connection regression:** two suite apps mutually list each other as CONNECTED within ~5 s and stay listed past 5 minutes (manifest heartbeat) — `[Coverage: AUTOMATED]` (`lintcrux_cxp_server_test.dart` "peer connector (mutual-connection regression)"; `crux_cxp` `peer_connectivity_test.dart`) + real two-app flow `[Coverage: MANUAL]`
- [ ] Discovered-but-unreachable peers show a persistent "Couldn't reach `<peer>`" warning row (amber icon) below the peers list; the section is empty when all peers are reachable, prunes a peer once its handshake succeeds or its manifest vanishes, and resets on server disable/port change (§7.2.1) — `[Coverage: UNIT]` (test/features/remote/cxp_dial_failures_provider_test.dart) + `[Coverage: INTEGRATION_TEST]` (test/features/remote/cxp_server_lifecycle_test.dart "surfaces a discovered-but-unreachable peer") + `[Coverage: WIDGET]` (test/features/remote/cross_probe_panel_test.dart, en/zh_CN/zh/ja/ko) + `[Coverage: MANUAL]` (live prune-on-reconnect)
- [ ] RequestHighlight `rule` kind selects the matching violation and clears filters — `[Coverage: INTEGRATION_TEST]` (test/services/remote/cxp/lintcrux_cxp_request_handler_test.dart + test/features/remote/cxp_server_lifecycle_test.dart)
- [ ] Inbound requests resolve the ACTIVE tab's per-tab store/table state (two tabs, two projects: honored only when the matching project's tab is active; mutations land in the active tab only) — `[Coverage: INTEGRATION_TEST]` (live socket over the running app: integration_test/remote_control/cxp_inbound_highlight_journey_test.dart — honored+selected against the active tab, then honored:false without disturbing selection; mutation-proof against a root-store rewire; resolution seam: `[Coverage: UNIT]` test/services/workspace/active_tab_container_handle_test.dart; guardrail: test/static/per_tab_provider_scope_leak_test.dart allowlist)
- [ ] RequestHighlight `source` kind narrows the file-glob filter and selects the nearest-line violation — `[Coverage: INTEGRATION_TEST]` (test/services/remote/cxp/lintcrux_cxp_request_handler_test.dart)
- [ ] RequestHighlight `signal` / `instance` kinds set the rule-substring filter — `[Coverage: INTEGRATION_TEST]` (test/services/remote/cxp/lintcrux_cxp_request_handler_test.dart)
- [ ] RequestHighlight unsupported kinds (`scope` / `net` / `port` / `marker` / `test` / `breakpoint`, and any unknown wire kind via the open `ElementKind` enum) ack `honored: false` without mutating state or throwing — `[Coverage: INTEGRATION_TEST]` (test/services/remote/cxp/lintcrux_cxp_request_handler_test.dart)
- [ ] Non-highlight message kinds (e.g. a directly-addressed `notify_selection`) reply with `error_response` `code: "unsupported"` echoing `in_reply_to` — **not** a fabricated `request_highlight_ack` — leaving table state + selection untouched — `[Coverage: INTEGRATION_TEST]` (test/services/remote/cxp/lintcrux_cxp_request_handler_test.dart)
- [ ] RequestOpenSource shells out via the configured editor command — `[Coverage: INTEGRATION_TEST]` (test/features/remote/cxp_server_lifecycle_test.dart)
- [ ] Malformed inbound paths and invalid line numbers ack `honored: false` with a populated `reason` — `[Coverage: INTEGRATION_TEST]` (test/services/remote/cxp/lintcrux_cxp_request_handler_test.dart)
- [ ] **Containment (CXP §11):** a `request_open_source` path outside the directories of the projects the user has opened (every tab's, the Recent projects list, and the active project's source directories) acks `honored: false` with a reason that never repeats the path, and no editor runs; a `request_open_artifact` whose recorded project lies outside them is never opened (§7.7) — `[Coverage: INTEGRATION_TEST]` (test/features/remote/cxp_server_lifecycle_test.dart "refuses a RequestOpenSource outside the opened projects", "RequestOpenArtifact opens a recorded project inside the opened projects") + `[Coverage: UNIT]` (test/services/remote/cxp/lintcrux_cxp_server_test.dart, test/services/remote/cxp/lintcrux_cxp_request_handler_test.dart) + `[Coverage: WIDGET]` (test/features/workspace/widgets/workspace_root_test.dart, the roots are published and withdrawn)
- [ ] **Peer auth:** a peer whose `hello` does not carry the token LintCrux published in its discovery manifest is refused `unauthorized` and never dispatched — `[Coverage: UNIT]` (test/services/remote/cxp/lintcrux_cxp_server_test.dart "a peer that does not present the token is refused")
- [ ] Cross-probe panel renders all three states (running / disabled / errored) — `[Coverage: WIDGET]` (test/features/remote/cross_probe_panel_test.dart)
- [ ] Cross-probe panel locale sweep (en / zh_CN / zh / ja / ko) — `[Coverage: WIDGET]` (test/features/remote/cross_probe_panel_test.dart)
- [ ] Settings → Remote Control toggle + port input round-trips through `appSettingsProvider` and persists across launches via `LintCruxSettingsCodec` — `[Coverage: INTEGRATION_TEST]` (test/services/settings/lintcrux_settings_codec_test.dart) + `[Coverage: WIDGET]` (test/features/settings/widgets/settings_remote_control_section_test.dart)
- [ ] Out-of-range port values clamp back to 54324 without crashing — `[Coverage: WIDGET]` (test/features/settings/providers/app_settings_provider_test.dart)
- [ ] Selecting a violation broadcasts `notify_selection` to connected peers in every tier while **Broadcast selection automatically** is on, and not when it is off — `[Coverage: INTEGRATION_TEST]` (`test/features/remote/providers/violation_selection_emitter_test.dart`) + `[Coverage: WIDGET]` (`test/features/workspace/widgets/project_tab_content_test.dart`, the tab realizes the emitter)
- [ ] Tier-gate scenarios: CXP receive and the selection broadcast are Open Core, no gating applies. Per-peer "Send selection to" actions are Pro — `[Coverage: MANUAL]` (absence verification)

## Lint Run Cache Seam (Open Core surface)

- [ ] `LintRunCacheService` interface defined; `NoopLintRunCacheService` is the registered default for `lintRunCacheServiceProvider` — `[Coverage: UNIT]` (test/services/lint_cache/lint_run_cache_service_provider_test.dart, test/domain/interfaces/lint_run_cache_service_test.dart)
- [ ] `LintCacheKey` / `LintCacheEntry` / `LintCacheStats` / `LintCacheInvalidationEvent` models structurally equal across all documented fields — `[Coverage: UNIT]` (test/domain/models/lint_cache_*.dart)
- [ ] `CacheFingerprint` produces deterministic SHA-256 source + config digests; CRLF normalization holds — `[Coverage: UNIT]` (test/services/lint_cache/cache_fingerprint_test.dart)
- [ ] `CacheViolationCodec` round-trips violations including the `raw` map; drops `suppression` field intentionally — `[Coverage: UNIT]` (test/services/lint_cache/cache_violation_codec_test.dart)
- [ ] `ParallelEngineRunner` consults the cache before invoking each engine; misses run + store; hits skip the engine + emit cached violations through the transformer pipeline — `[Coverage: UNIT]` (test/services/engines/parallel_engine_runner_cache_test.dart)
- [ ] `lintCacheEnabledProvider = false` bypasses lookup and store entirely — `[Coverage: UNIT]` (test/services/engines/parallel_engine_runner_cache_test.dart)
- [ ] `forceBypassCache = true` bypasses cache for one runner instance only — `[Coverage: UNIT]` (test/services/engines/parallel_engine_runner_cache_test.dart)
- [ ] `clearLintCache` / `openLintCacheStats` / `forceLintRunWithoutCache` actions are Pro-tier; rendered with the tier badge on open-core builds — `[Coverage: UNIT]` (test/core/shortcuts/lintcrux_action_test.dart)
- [ ] Tier-gate scenarios: cache UI / SQLite persistence is Pro work verified in the Pro overlay's guide. Open-core build serves the no-op service and re-invokes engines on every run — `[Coverage: MANUAL]`

## Keyboard shortcuts (§8.5)

- [ ] Default keymap is collision-free — fresh profile shows no conflict banner; Toggle Theme is Cmd/Ctrl+Shift+K (moved off New Tab's Cmd/Ctrl+T) — `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_conflicts_test.dart` default-keymap guard)
- [ ] Run All Engines is F5, Cancel Run is Esc (moved off Shift+F5 for suite-wide cancel/stop consistency) — `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_bindings_test.dart`)
- [ ] Keyboard-shortcut conflict resolution — rebinding an action onto another's chord shows asymmetric warnings (winner "Takes precedence over …", shadowed "Won't fire — shadowed by …"), a summary banner with the count, and at runtime the **remapped** action fires (deterministic, not enum-order) — `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_conflicts_test.dart`) + `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart`, `test/features/settings/widgets/shortcuts_settings_section_test.dart`)
- [ ] Command palette always reachable (§8.6) — Open Command Palette appears under the Help menu (not in the palette itself); after unbinding Cmd/Ctrl+Shift+P it is still reachable via Help → Command Palette (issue #38) — `[Coverage: UNIT]` (`test/core/shortcuts/action_category_test.dart`)
- [ ] Action toolbar (§8.7) — `common` carries the suite-canonical block (Open Project · Save Session · Close Active Project │ Find · Cross-Probe · Settings) **identically to the other three products**; `specific` carries Open Source Files · Open Workspace · Import SARIF │ Run/Stop │ grouped Export; each dispatches the same action as its menu/palette equivalent (tooltips = localized label + live binding); open-core only (baseline/Verible/bookmark buttons stay in the violation table); overflows into the trailing menu when narrow — `[Coverage: WIDGET]` (`lintcrux_toolbar_test.dart`) + `[Coverage: MANUAL]` (Run All actually runs the engines)
- [ ] Toolbar enablement comes from the descriptor table only — on the empty canvas **Open Source Files**, Save Session, Close Active Project, Find, Run and Export are all greyed; Open Project / Open Workspace / Import SARIF / Cross-Probe / Settings stay live. Open Source Files tracks `hasProject`, not `hasOpenTab`, because appending sources needs a loaded `.lintcrux` to rewrite — `[Coverage: WIDGET]` (`lintcrux_toolbar_test.dart`, "Open Source Files")
- [ ] Find in Violations dialog (§8.7.1) — `focusSearch` (Cmd/Ctrl+F, toolbar **Search**, "Find in Violations…") opens the modal `SearchDialog` over the **active tab's** violations (substring/glob/regex over rule id + message); picking a result selects + scrolls to the violation and closes; searches the active tab (not another tab); silent no-op with no project open; the inline filter chip is unchanged — `[Coverage: WIDGET]` (`test/features/search/widgets/search_dialog_test.dart`) + `[Coverage: WIDGET]` (`test/app_action_dispatch_test.dart` — empty-workspace no-op) + `[Coverage: MANUAL]` (active-tab scoping, step 5)
- [ ] Web viewer: Cmd/Ctrl+F on the viewer searches the loaded report and selects the picked row; on the landing screen it opens nothing — `[Coverage: WIDGET]` (`test/features/web_viewer/web_viewer_search_web_test.dart`, headless Chrome via `tool/run_web_tests.sh`) + `[Coverage: MANUAL]` (the browser's own find bar stays closed, step 7)
- [ ] Tier affordances (§8.8) — command-palette Pro rows show a `LintCruxFeatureTierBadge`, free rows show none; native menu-bar Pro items append a localized `(PRO)`/`(ENT)` suffix (`tierLabelSuffix`), free items none; both localize across en / zh_CN / ja / ko — `[Coverage: UNIT]` (`test/core/shortcuts/action_tier_label_test.dart`) + `[Coverage: WIDGET]` (`test/features/command_palette/widgets/command_palette_dialog_test.dart`, `test/features/menu_bar/widgets/desktop_menu_bar_test.dart`)
- [ ] Switch Project (Cmd/Ctrl+P) / Reopen Recent Project / Search Across Projects (Cmd/Ctrl+Shift+F) are **Pro-tier** (per `requiredTier` — the multi-project registry is Pro) so they render the PRO badge + ` (PRO)` menu suffix. All three appear under File → projects group (switch · reopen · pin) and Search → Find across projects, in the menu and the command palette but never the toolbar. In **open core** each shows the Pro-upsell snackbar (not the neutral "not available yet" — the feature exists, it is the tier that is missing); in a **Pro** build Switch Project and Reopen Recent open the shared project switcher and Search Across Projects opens the cross-project search dialog — `[Coverage: UNIT]` (`test/core/shortcuts/lintcrux_action_test.dart`, `test/app_action_dispatch_test.dart`) + `[Coverage: WIDGET]` (`test/app_opener_seam_feedback_test.dart` open-core snack; the Pro overlay's project-action reachability test for the Pro dialogs)

## Color Theming & Customization (suite-wide)

See VERIFICATION_GUIDE.md §9 for step-by-step instructions.

- [ ] Picking `WaveCrux Light` flips MaterialApp brightness to light — `[Coverage: MANUAL]`
- [ ] Picking `WaveCrux Dark` from light state flips brightness back to dark — `[Coverage: MANUAL]`
- [ ] Picking `Solarized Dark` re-tints toolbar / scaffold / panel backgrounds with Solarized hues — `[Coverage: MANUAL]`
- [ ] Picking `Oscilloscope` re-tints chrome with phosphor-green-on-black — `[Coverage: MANUAL]`
- [ ] Active preset survives an app restart — `[Coverage: MANUAL]`
- [ ] Per-token chrome override: edit `toolbar.background`, observe immediate repaint, reset clears it — `[Coverage: MANUAL]`
- [ ] Import `.crux-theme.json` via Theme pack browser: pack appears in installed list, Activate applies tokens — `[Coverage: MANUAL]`
- [ ] Export active theme writes a valid `.crux-theme.json` — `[Coverage: AUTOMATED]` (`crux_theme` package suite)
- [ ] No exception in en / zh_CN / ja / ko locale sweeps for Settings → Appearance — `[Coverage: MANUAL]`

## About Box (suite-wide)

See VERIFICATION_GUIDE.md §13 for step-by-step instructions. Shared
`crux_about_dialog` surface; replaced the Material `showAboutDialog` stub.

- [ ] **Help → About LintCrux** opens the dialog; title reads "About LintCrux" — `[Coverage: WIDGET]` (`test/features/about/lintcrux_about_dialog_test.dart`)
- [ ] Version / Build / Commit rows show the resolved build info (stub values in test) — `[Coverage: WIDGET]` (`lintcrux_about_dialog_test.dart`)
- [ ] Locale sweep (en / zh_CN / ja / ko) renders without exception — `[Coverage: WIDGET]` (`lintcrux_about_dialog_test.dart`)
- [ ] Edition chip hidden for openCore; EDU badge shown for the edu tier; "Public Beta" chip while `kBetaPeriod = true` — `[Coverage: WIDGET]` (`lintcrux_about_dialog_test.dart`)
- [ ] Exactly two action buttons — **Visit Website** + **Copy Version Info** (no attribution section) — `[Coverage: WIDGET]` (`lintcrux_about_dialog_test.dart`)
- [ ] Visit Website opens `https://ferriteengineering.com` in the system browser — `[Coverage: MANUAL]`
- [ ] Copy Version Info copies the version paragraph + shows the confirmation snackbar — `[Coverage: MANUAL]`
- [ ] Tier-gate: About is never feature-gated; tier only changes which chips render (beta / edition / EDU), both `kBetaPeriod` true and false — `[Coverage: MANUAL]`

## Robustness — Engine-Output Parsers & Subprocess Orchestration

See VERIFICATION_GUIDE.md §10 for step-by-step instructions.

- [ ] Parser log-and-continue: a garbage/banner line is skipped (not fatal) and surfaced as a SARIF `toolExecutionNotifications` entry, never dropped silently — `[Coverage: UNIT]` (`test/services/engines/parser_fuzz_test.dart`)
- [ ] Parser fuzz: no parser throws on empty / garbage / truncated-JSON / CR-CRLF-LF / NUL / invalid-UTF-8 / >1 MB-line / ANSI input; valid lines mixed with garbage still parse — `[Coverage: UNIT]` (`parser_fuzz_test.dart`)
- [ ] Golden SARIF snapshots match for every committed `output.txt` (`REGENERATE=1` refreshes) — `[Coverage: GOLDEN]` (`test/services/engines/engine_golden_test.dart`)
- [ ] NO_COLOR contract: subprocesses spawn with `NO_COLOR=1` + `TERM=dumb`; engine output decoded with `allowMalformed` — `[Coverage: UNIT]` (`test/services/engines/clean_engine_environment_test.dart`)
- [ ] Engine watchdog: a hung engine is killed after the timeout and reported failed; the other engines still complete — `[Coverage: UNIT]` (`test/services/engines/engine_watchdog_test.dart`, `subprocess_chaos_test.dart`)
- [ ] Cancellation kills **every** concurrent child, leaving the store not half-populated — `[Coverage: UNIT]` (`test/services/engines/parallel_engine_runner_cancellation_test.dart`)
- [ ] Missing binary → unavailable, other engines run; non-zero exit with no parseable output → completed/empty (not error); both stdout+stderr drained (no single-stream deadlock) — `[Coverage: UNIT]` (`subprocess_chaos_test.dart`)
- [ ] Zombie-on-exit OS-level reaping — `[Coverage: MANUAL]` (deferred to a `ProcessLifecycleRegistry` follow-up)

## Robustness — Version Drift, Stress & Static Guardrails

See VERIFICATION_GUIDE.md §11 for step-by-step instructions.

- [ ] Rule-alias table resolves a renamed rule and a waiver against the old id still suppresses the renamed violation; deprecated notice surfaced — `[Coverage: UNIT]` (`test/services/rules/rule_alias_table_test.dart`, Pro `waiver_matcher_test.dart`)
- [ ] Canned N/N-1 drift reconciles through the alias table; live N/N-1 reconciliation gated on `*_NMINUS1_BIN` — `[Coverage: UNIT/INTEGRATION]` (`version_drift_test.dart`, `cross_version_engine_test.dart`)
- [ ] `waiverDeprecatedRuleId` renders in en/zh_CN/zh/ja/ko — `[Coverage: UNIT]`
- [ ] 50K index integrity equals brute-force scan under replace / partial-replace / streaming — `[Coverage: UNIT]` (`index_integrity_test.dart`)
- [ ] 50K single-bucket `replaceFromEngine` stays linear (removal-scan count `≤ 5·N`) and scales sub-quadratically (`< 6x` across a 4x step) on the deterministic `lastRemovalScans` counter — contention-immune, not wall-clock; re-run + cache-hit stay responsive on a large single-severity project — `[Coverage: UNIT]` (`in_memory_violation_store_complexity_test.dart`)
- [ ] Indices stay consistent across 200 randomized replace / partial-replace rounds; equal-but-distinct violations remove individually — `[Coverage: UNIT]` (`in_memory_violation_store_complexity_test.dart`)
- [ ] 100K streaming ingest stays in bounded memory, cancels mid-document with an empty store, and rejects truncated/bad-token/wrong-schema input with a typed `SarifReadException` leaving prior contents intact — `[Coverage: HYBRID]` (`streaming_sarif_reader_stress_test.dart`)
- [ ] Perf harness emits a JSONL row per performance-budget metric — `[Coverage: HYBRID]` (`flutter test --dart-define=RUN_BENCHMARKS=true test/perf/lint_perf_bench_test.dart`)
- [ ] Static guards fail on a loose fixture / engine-without-corpus / missing companion / GPL provenance and pass on the committed tree; CI "fixtures up to date" gate green — `[Coverage: UNIT/CI]` (`test/static/*`, `.github/workflows/ci.yml`)
- [ ] Per-tab provider scope-leak scanner green (open-core + Pro-union seed, override-binding aware) and its seeded-synthetic-leak self-check passes — `[Coverage: UNIT]` (test/static/per_tab_provider_scope_leak_test.dart)

## Robustness — Incremental Merge & Persistence Durability

See VERIFICATION_GUIDE.md §12 for step-by-step instructions.

- [ ] Per-file re-run replaces only the changed engine's bucket; the four indices match a brute-force scan — `[Coverage: UNIT]` (`partial_replace_index_sync_test.dart`)
- [ ] A managed waiver + severity override survive a line shift; an inline pragma wins over a managed waiver — `[Coverage: UNIT]` (`merge_preservation_test.dart`)
- [ ] Atomic JSON write: a crash between temp-write and rename leaves the original intact — `[Coverage: UNIT]` (`atomic_json_persistence_test.dart`)
- [ ] A newer/invalid schema version is rejected with a typed error without clobbering the file — `[Coverage: UNIT]` (same)
- [ ] FileWatcher → debounce → runIncremental coalescing (N rapid edits → exactly one re-run) — `[Coverage: MANUAL]`
- [ ] Multi-project state lifts: two open projects get distinct waiver/cache/customRule/dashboard instances and each retains its state across active-project switches — `[Coverage: UNIT]` (`per_project_state_isolation_test.dart`)

## Subsequent phases **(placeholder)**

Add a checklist group the same day the corresponding phase ships its first deliverable.

---

## Action-surface feedback & destructive-action confirmation

See VERIFICATION_GUIDE.md §14 for step-by-step instructions.

- [ ] Every Pro-badged menu / palette entry in an **open-core** build raises the "requires LintCrux Pro" snackbar on activation — no silent dead items — `[Coverage: UNIT]` (`test/app_opener_seam_feedback_test.dart`)
- [ ] Open-core-tier actions whose surface has not shipped use the neutral "not available yet" snack, never a false Pro upsell — `[Coverage: UNIT]` (`test/app_opener_seam_feedback_test.dart`)
- [ ] Every opener seam resolves `null` in open-core (a no-op default would re-create the dead-item class) — `[Coverage: UNIT]` (`test/app_opener_seam_feedback_test.dart`)
- [ ] Native menu-bar activation of a `(PRO)`-suffixed item produces the same snackbar — `[Coverage: MANUAL]`
- [ ] `File → New Workspace` and reset-workspace both mount the "Reset workspace?" dialog; Cancel preserves all tabs, Reset closes them — `[Coverage: UNIT]` (`test/app_reset_workspace_confirm_test.dart`)
- [ ] "Review Verible Fixes…" opens the review dialog and applies nothing until confirmed inside it (label matches behavior) — `[Coverage: MANUAL]`

### `File → Close All Tabs` (open-core; guide §6.5.8.1)

- [ ] Renders in the File menu and command palette with **no** `(PRO)` suffix / tier badge, unlike the adjacent Close All Projects — `[Coverage: UNIT]` (`test/app_close_all_tabs_test.dart`)
- [ ] Has no default keyboard accelerator (menu / palette only) — `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_bindings_test.dart`)
- [ ] Mounts the "Close all tabs?" confirmation; Cancel preserves every tab, "Close All" empties the workspace — `[Coverage: UNIT]` (`test/app_close_all_tabs_test.dart`)
- [ ] On an already-empty workspace it is a silent no-op — no confirmation dialog appears — `[Coverage: UNIT]` (`test/app_close_all_tabs_test.dart`)
- [ ] Layout `extras` (statistics-strip visibility) survive Close All Tabs but not Reset Workspace — the distinction that justifies both actions — `[Coverage: UNIT]` (`test/app_close_all_tabs_test.dart`)
- [ ] Post-beta (`kBetaPeriod = false`), unlicensed: Close All Projects is denied while Close All Tabs still works in the same session — `[Coverage: MANUAL]`
- [ ] Localized in en / zh-CN / ja / ko — `[Coverage: UNIT]` (`test/app_close_all_tabs_test.dart`)

## Update mechanism

See `VERIFICATION_GUIDE.md` §15.

- [ ] Newer manifest version → banner appears above the app content naming the version — `[Coverage: UNIT]` (`test/features/update/update_status_wiring_test.dart`) + `[Coverage: MANUAL]`
- [ ] **View Changes** opens the manifest's `changelog_url`; **Update Now** opens `https://lintcrux.app/download` — `[Coverage: UNIT]` (`test/features/update/lintcrux_update_config_test.dart`) + `[Coverage: MANUAL]` (browser launch)
- [ ] Dismiss hides the banner for the session; a *newer* version brings it back — `[Coverage: WIDGET]` (`crux-shared/packages/crux_updates/test/widgets/`)
- [ ] `mandatory: true` (or a running build below `min_supported_version`) renders **no** close affordance — `[Coverage: UNIT]` (`test/features/update/update_status_wiring_test.dart`) + `[Coverage: MANUAL]`
- [ ] Manual **Check for Updates** (Help menu / palette / About box) shows the in-flight toast, then the outcome — `[Coverage: MANUAL]`
- [ ] Already-current → "You're on the latest version (N)"; unreachable manifest → one non-fatal "Couldn't check for updates" and nothing else breaks — `[Coverage: UNIT]` (`test/features/update/update_status_wiring_test.dart`) + `[Coverage: MANUAL]`
- [ ] Malformed manifest (bad JSON / no `latest` / no `version`) fails soft — no banner, no crash — `[Coverage: UNIT]` (`test/features/update/update_status_wiring_test.dart`)
- [ ] Settings ▸ General ▸ *Automatically check for updates* defaults **on**, persists across relaunch, and when off suppresses the launch/periodic check while the manual action still runs — `[Coverage: WIDGET]` (`test/features/settings/widgets/settings_general_section_test.dart`), `[Coverage: UNIT]` (`test/services/persistence/auto_update_check_settings_codec_test.dart`, `test/features/update/update_status_wiring_test.dart`)
- [ ] `server_time` is recorded and persisted on every successful fetch, including one reporting the build is current — `[Coverage: UNIT]` (`test/services/updates/observed_server_time_store_test.dart`)
- [ ] Web build runs the check but never renders the banner — `[Coverage: MANUAL]`
- [ ] Banner strings localized in en / zh-CN / ja / ko and the banner names the product — `[Coverage: UNIT]` (`test/features/update/lintcrux_update_strings_test.dart`)
- [ ] `Check for Updates` carries **no** tier badge / `(PRO)` suffix in any surface, beta and post-beta — `[Coverage: UNIT]` (`test/core/shortcuts/lintcrux_action_test.dart`)

---

## Beta issue reporter

See `VERIFICATION_GUIDE.md` §16.

- [ ] Help ▸ *Submit Issue* (and the palette entry, and the About-box button) opens the reporter modal — `[Coverage: MANUAL]`
- [ ] **PRIVACY: the Session State section of a real report contains no path separator, no project / file / module name, and no user-typed filter text** — `[Coverage: UNIT]` (`test/features/issue_reporter/providers/issue_session_context_test.dart`) + `[Coverage: MANUAL]` (read-through of one real report)
- [ ] Session State reports each enabled engine **with its detected version**; an unresolvable engine reads `(not detected)` without blanking the line — `[Coverage: UNIT]` (`test/features/issue_reporter/providers/issue_session_context_test.dart`, `test/features/engine_config/providers/engine_versions_provider_test.dart`) + `[Coverage: MANUAL]`
- [ ] Session State reports violation counts by severity, distinct firing rules, active waivers, and filter/view state as flags — `[Coverage: UNIT]` (`test/features/issue_reporter/providers/issue_session_context_test.dart`)
- [ ] The report describes the **active tab**, not the root scope — switch tabs and confirm the counts follow — `[Coverage: UNIT]` (`test/features/workspace/providers/tab_overrides_factory_test.dart`) + `[Coverage: MANUAL]`
- [ ] Toggling a category off removes its section from the live preview; App & Environment cannot be toggled off — `[Coverage: WIDGET]` (`crux-shared/packages/crux_issue_reporter/test/widgets/`)
- [ ] Screenshot tile shows the app **without** the reporter dialog; submitting writes the PNG and reveals it — `[Coverage: MANUAL]`
- [ ] Submit opens the pre-filled GitHub form against `Ferrite-Engineering/lintcrux` with template `bug_report.yml`, and copies the body to the clipboard — `[Coverage: UNIT]` (`test/app_phase5_wiring_test.dart`) + `[Coverage: MANUAL]`
- [ ] An over-long body is dropped from the URL and the toast says to paste from the clipboard — `[Coverage: WIDGET]` (`crux-shared/packages/crux_issue_reporter/test/`)
- [ ] Early-startup warnings appear in the Diagnostics section (the log buffer is attached before the first provider is built) — `[Coverage: MANUAL]`
- [ ] Reporter chrome localized in en / zh-CN / ja / ko — `[Coverage: UNIT]` (`test/features/issue_reporter/lintcrux_issue_reporter_strings_test.dart`)
- [ ] No **Pro State** category in an open-core build (the overlay seam is left at its default) — `[Coverage: UNIT]` (`test/app_phase5_wiring_test.dart`)
- [ ] `Submit Issue` carries **no** tier badge / `(PRO)` suffix, beta and post-beta — `[Coverage: UNIT]` (`test/core/shortcuts/lintcrux_action_test.dart`)

---

## Beta build expiry

See `VERIFICATION_GUIDE.md` §17.

- [ ] No `--dart-define=BETA_EXPIRY` (or `=0`) → no banner and no modal — `[Coverage: UNIT]` (`crux-shared/packages/crux_license/test/beta_expiry_test.dart`) + `[Coverage: MANUAL]`
- [ ] `BETA_EXPIRY` 3 days out → dismissible strip with the correct day count (check the 1-day plural too) — `[Coverage: WIDGET]` (`crux-shared/packages/crux_license/test/beta_expiry_banner_test.dart`) + `[Coverage: MANUAL]`
- [ ] The strip's **Download** opens the same download page the update banner uses — `[Coverage: WIDGET]` (`test/features/beta_expiry/widgets/beta_expiry_gate_test.dart`)
- [ ] Dismissing the strip hides it for the session; resume brings it back — `[Coverage: WIDGET]` (dismissal), `[Coverage: MANUAL]` (resume)
- [ ] `BETA_EXPIRY` in the past → blocking modal; content behind is non-interactive; back gesture / Escape does not dismiss — `[Coverage: WIDGET]` (`test/features/beta_expiry/widgets/beta_expiry_blocking_overlay_test.dart`) + `[Coverage: MANUAL]`
- [ ] **Quit LintCrux** actually terminates the process — the only way out on Windows / Linux, where the window close button is behind the barrier — `[Coverage: MANUAL]`
- [ ] The expiry banner renders with no `Overlay` ancestor (no `Tooltip` — a regression here red-screens every launch in the warning window) — `[Coverage: WIDGET]` (`crux-shared/packages/crux_license/test/beta_expiry_banner_test.dart`)
- [ ] Invalid dates (`20261301`, `20260230`, negative, pre-2000) resolve to "never expires" — `[Coverage: UNIT]` (`crux-shared/packages/crux_license/test/beta_expiry_test.dart`)
- [ ] **Clock rollback:** after observing a `server_time` past the expiry, setting the device clock back does not defer expiry; wiping the watermark restores device-clock behaviour — `[Coverage: UNIT]` (`test/services/updates/observed_server_time_store_test.dart`) + `[Coverage: MANUAL]`
- [ ] The gate blocks **every** tier — Pro and Enterprise licensees included (build shelf life, not a licence check) — `[Coverage: WIDGET]` (`test/features/beta_expiry/widgets/beta_expiry_gate_test.dart`)
- [ ] `kBetaPeriod = false` makes the mechanism inert regardless of the injected define — `[Coverage: UNIT]` (`crux-shared/packages/crux_license/test/beta_expiry_test.dart`) + `[Coverage: MANUAL]`
- [ ] Banner and modal localized in en / zh-CN / ja / ko — `[Coverage: WIDGET]` (`test/features/beta_expiry/widgets/`)

---

## Headless CI binary (`bin/lintcrux.dart`)

See `VERIFICATION_GUIDE.md` §19. Run every exit-code row from a shell and
assert on `echo $?`, not on the printed summary.

- [ ] `tool/build_cli.sh` produces `build/cli/bundle/bin/lintcrux`; `--version` and `--help` run — `[Coverage: MANUAL]`
- [ ] The **desktop** executable run with `--version`, `--help`, an unknown flag or a missing `--import-filelist` file prints, then the process ends with `0` / `0` / `64` / `65` (it does not stay alive behind a window) — `[Coverage: UNIT]` (`test/app_headless_exit_test.dart`, through an injected exit) + `[Coverage: MANUAL]`
- [ ] `--help` lists every CI flag (`--top`, `--engine`, `--export`, `--out`, `--sarif`, `--baseline`, `--exit-code`, `--fail-on-new-violations`, `--allow-missing-engines`, `--config`, `--quiet`) and the full exit-code table — `[Coverage: UNIT]` (`test/core/cli/lintcrux_cli_test.dart`) + `[Coverage: MANUAL]`
- [ ] `--reset-eula`: the **desktop** app, on an installation that has already accepted, presents the End User License Agreement again on that same launch; accept it, relaunch without the flag, and it is not presented. Beside `--reset-telemetry-consent` the agreement comes first, then the disclosure. `--help` lists it; the headless binary accepts and ignores it; an unknown flag is still exit `64` — `[Coverage: UNIT]` (`test/app_reset_eula_test.dart`, `test/core/cli/cli_args_parser_test.dart`, `test/core/cli/lintcrux_cli_test.dart`) + `[Coverage: MANUAL]` (the dialog itself)
- [ ] Violations present, **no gate flag** → exit `0` (a bare run is a report, not a gate) — `[Coverage: UNIT]` (`test/services/headless/headless_runner_test.dart`) + `[Coverage: MANUAL]`
- [ ] `--exit-code` with findings → exit `1`; without findings → exit `0` — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] `--fail-on-new-violations` against a Pro-written baseline: unchanged tree → `0`; introduced violation → `2` with the line annotated `(new)`; reverted → `0` — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] Both gates on a regression → `2`, not `1` (the specific code wins) — `[Coverage: UNIT]`
- [ ] **No baseline file** → every violation is new, exit `2`, plus a note saying where it looked. Never exit `0` — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] **Corrupt baseline** → exit `3`, not a silent pass — `[Coverage: UNIT]`
- [ ] A baseline set in one checkout gates a run in another (project-relative fingerprints); a version 1 baseline is migrated on read — `[Coverage: UNIT]` (`test/services/headless/headless_runner_test.dart`, `test/domain/models/lint_baseline_test.dart`)
- [ ] An engine that fails → exit `3`, **even when violations were also found** (a partial run is not a count) — `[Coverage: UNIT]`
- [ ] A missing engine binary → exit `3` by default, and the message names `--<engine>-path` / `--engine` / `--allow-missing-engines` — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] `--allow-missing-engines` demotes it to a `note:` and exits `0` — `[Coverage: UNIT]`
- [ ] An unusable positional (`notes.txt`, a directory, a missing file, two projects, a project mixed with sources) → exit `64`, **never a silent skip**, and stdout stays empty — `[Coverage: UNIT]` (`test/services/headless/headless_input_resolver_test.dart`) + `[Coverage: MANUAL]`
- [ ] A project file that exists but cannot be loaded (unparseable, no sources, a listed source missing) → exit `3`, not `64` — `[Coverage: UNIT]` (`test/services/headless/headless_runner_test.dart`)
- [ ] An unknown `--engine` id → exit `64` listing the registered ids — `[Coverage: UNIT]`
- [ ] `--export` without `--out` (and `--out` without `--export`, and an unknown format) → exit `64` — `[Coverage: UNIT]` (`test/core/cli/cli_args_parser_test.dart`)
- [ ] SARIF lands on disk, parses, and validates against the OASIS 2.1.0 schema — `[Coverage: MANUAL]`
- [ ] SARIF `artifactLocation.uri` is **repo-relative** with `uriBaseId: "%SRCROOT%"`, and `originalUriBaseIds` declares the root — an absolute `uri` means GitHub annotates nothing — `[Coverage: UNIT]` (`test/services/headless/headless_export_writer_test.dart`) + `[Coverage: MANUAL]`
- [ ] `automationDetails.id` carries **no timestamp**, so re-uploads supersede rather than duplicate — `[Coverage: UNIT]`
- [ ] No absolute path from `Violation.raw` leaks into the exported SARIF — `[Coverage: UNIT]`
- [ ] A pragma-suppressed violation is exported with a SARIF `suppressions` entry (`inSource`, `accepted`; a managed waiver is `external`), engine `raw` keys land in `result.properties` (never on the result), and a SARIF re-import restores the waiver — desktop and headless — `[Coverage: UNIT]` (`test/services/sarif/sarif_writer_test.dart`, `test/services/headless/headless_export_writer_test.dart`)
- [ ] `--export json|csv|html --out` each write a readable file — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] `--config` overlay applies severity overrides / engine selection; an unknown key or wrong-typed value → exit `3`, never ignored — `[Coverage: UNIT]` (`test/services/headless/project_config_overlay_test.dart`) + `[Coverage: MANUAL]`
- [ ] Ad-hoc `lintcrux a.sv b.sv --top top_module` lints without a project file — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] A committed `.lintcrux` with a **relative** `rootPath` resolves to the project file's own directory (otherwise SARIF relativization silently breaks) — `[Coverage: UNIT]`
- [ ] `--import-filelist` prints the emitted path and lints it; a broken `.f` → exit `65` — `[Coverage: UNIT]`
- [ ] `--import-edam` prints stderr warnings + the emitted path and lints it; a broken `.eda.yml` or one with zero HDL sources → exit `65` — `[Coverage: UNIT]` (`test/core/cli/lintcrux_cli_test.dart`)
- [ ] Source pragmas suppress violations and the suppressed count appears in the summary; suppressed violations do not trip `--exit-code` — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] `--quiet` drops the listing, keeps the summary and the exit code — `[Coverage: UNIT]`
- [ ] The CLI and the desktop app report the **same violation count** for the same project (one shared `EngineRunPlanner`) — `[Coverage: UNIT]` (`test/services/run/engine_run_planner_test.dart`) + `[Coverage: MANUAL]`
- [ ] `SIGTERM` mid-run reaps any Yosys subprocess and exits `128 + signal` — `[Coverage: MANUAL]`
- [ ] **Tier:** every flag works in an open-core build under both `kBetaPeriod` values; `--help` carries no `(PRO)` suffix — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] The GitHub Actions example in `docs-site/docs/cookbook/ci-integration.md` runs as written — `[Coverage: MANUAL]`

---

## FuseSoC EDAM import (guide §22)

- [ ] `EdamReader` maps the SERV captures (`verification/fixtures/edam/`): sources + per-file language from `file_type`, `is_include_file` dirs, `toplevel`, `-Wall` → `warnFlags`, `.vlt` → Verilator `waiverFiles`, `files[].core` → `sourceFileProvenance` — `[Coverage: UNIT]` (`edam_reader_test.dart`, `edam_import_service_test.dart`)
- [ ] Declaration-only parameters apply nothing; `vlogdefine` defaults become defines; `vlogparam` defaults become Verilator-only `-G` with a warning — `[Coverage: UNIT]` (`edam_reader_test.dart`)
- [ ] Verilator receives `extraOptions` then `waiverFiles` **before** the sources; no other engine sees the `.vlt` — `[Coverage: UNIT]` (`verilator_engine_test.dart`)
- [ ] `File → Import FuseSoC EDAM…` opens the picker and lands the imported project in a NEW TAB — `[Coverage: WIDGET]` (`app_action_dispatch_test.dart`) + `[Coverage: MANUAL]`
- [ ] End-to-end on a machine with FuseSoC: `fusesoc run --target=lint --setup award-winning:serv:servant` then `lintcrux --import-edam build/…/*.eda.yml --sarif out.sarif` lints the full SoC with no hand-editing — `[Coverage: MANUAL]` (guide §22.2)

---

## Workspace launch behavior — tab dedupe, restore gate, persisted state

See `VERIFICATION_GUIDE.md` §20. Quit the app before touching anything under
`<appSupport>` — the workspace document is flushed on exit.

- [ ] Relaunching **seven times** with the same positional `.lintcrux` path yields **one** tab, not seven — `[Coverage: UNIT]` (`test/features/workspace/providers/workspace_provider_test.dart`) + `[Coverage: MANUAL]`
- [ ] A relative, a `..`-bearing, a trailing-separator, a symlinked (`/tmp` → `/private/tmp`) and a case-different spelling all dedupe against the tab restored from disk — `[Coverage: UNIT]` (`test/services/workspace/lintcrux_workspace_codec_test.dart`) + `[Coverage: MANUAL]`
- [ ] File → Open on an already-open project **focuses** its tab and leaves that tab's filters / sort / selection / current run untouched — `[Coverage: UNIT]` (`test/features/workspace/services/open_project_in_workspace_test.dart`) + `[Coverage: MANUAL]`
- [ ] A different project still opens its own tab; two empty-canvas tabs never fold together — `[Coverage: UNIT]`
- [ ] Settings → General shows **Restore tabs on launch**, on by default, 44 dp, localized en / zh-CN / zh / ja / ko — `[Coverage: WIDGET]` (`test/features/settings/widgets/settings_general_section_test.dart`)
- [ ] Turning it **off** and relaunching gives an empty workspace; turning it back on restores the same session (the document is left on disk, not cleared) — `[Coverage: UNIT]` (`test/features/workspace/providers/workspace_provider_test.dart`) + `[Coverage: MANUAL]`
- [ ] Restore **off** + a positional `.lintcrux` argument → exactly one tab (the CLI one) — `[Coverage: MANUAL]`
- [ ] Restore **on** + a positional argument naming an already-restored project → the restored tabs plus **exactly one** deduped CLI tab, focused — `[Coverage: MANUAL]`
- [ ] The preference is read from `settings.restoreTabsOnLaunch` — the key `CoreSettingsCodec` owns and the one `defaults write flutter.settings.restoreTabsOnLaunch` sets — `[Coverage: UNIT]` (`test/services/persistence/restore_tabs_settings_codec_test.dart`)
- [ ] An unreadable settings store still **restores**, and never leaves the launch hanging — `[Coverage: UNIT]`
- [ ] The gate reads a value `bootstrap` resolved, never storage from inside the workspace notifier (awaiting `SharedPreferences` there hangs every workspace-touching widget test under fake-async) — `[Coverage: UNIT]` (`test/features/workspace/providers/workspace_provider_test.dart`)
- [ ] A stale tab closed in the app leaves both `<appSupport>/workspace.json` and `<appSupport>/lintcrux/workspace.json` — `[Coverage: MANUAL]`
- [ ] Full state reset requires deleting **both** `workspace.json` files (tabs vs. projects) plus `sessions/`; deleting one leaves the other to re-seed — `[Coverage: MANUAL]`
- [ ] Restore-off is not defeated by the project registry re-seeding tabs at launch — `[Coverage: UNIT]` (`test/features/workspace/providers/project_workspace_sync_test.dart`) + `[Coverage: MANUAL]`
- [ ] `ProjectWorkspaceSync` records a project once per open, not once per convergence pass, whatever spelling the tab carries — `[Coverage: UNIT]`
- [ ] Command palette: typing a query and pressing **Enter** runs the highlighted action; ↑/↓ move the highlight without moving the caret; Escape closes once — `[Coverage: WIDGET]` (`test/features/command_palette/widgets/command_palette_dialog_test.dart`) + `[Coverage: MANUAL]`
- [ ] **Tier:** all of the above is open-core on every tier under both `kBetaPeriod` values; no `(PRO)` suffix on the Settings row. In an open-core build `<appSupport>/lintcrux/workspace.json` does not exist (`NoopProjectRegistry`) — `[Coverage: MANUAL]`

---

## Verible rule profiles — lowRISC / OpenTitan style guide

See `VERIFICATION_GUIDE.md` §21. Needs a real `verible-verilog-lint`
(verified against v0.0-3795-gf4d72375 and v0.0-4084-gf3e4d98b).

- [ ] `"perEngineOptions": {"verible": {"ruleProfile": "lowrisc"}}` in `project.lintcrux` makes the run **complete** — a nonexistent rule name would exit non-zero having linted nothing — `[Coverage: UNIT]` (`test/services/engines/verible/builtin_rule_profiles_test.dart`) + `[Coverage: MANUAL]`
- [ ] The command line carries `--ruleset=none` plus one comma-separated `--rules=…` of 41 tokens, before `extraArgs` and before the file list — `[Coverage: UNIT]` (`test/services/engines/verible/verible_engine_test.dart`) + `[Coverage: MANUAL]`
- [ ] A lower-case `parameter` name is flagged and the message quotes the CamelCase-or-ALL_CAPS regex (upstream's `localparam_style` config arrived intact) — `[Coverage: MANUAL]`
- [ ] A nested struct typedef is **not** flagged with the profile and **is** flagged without it (`typedef-structs-unions` is deliberately absent) — `[Coverage: MANUAL]`
- [ ] A typo'd or non-string `ruleProfile` fails the engine loudly in Diagnostics and never spawns the subprocess — it must not fall back to Verible's defaults — `[Coverage: UNIT]` + `[Coverage: MANUAL]`
- [ ] Omitting the key emits no `--rules` / `--ruleset` at all — `[Coverage: UNIT]`
- [ ] Every rule the profile names resolves in the Inspector to a rule with a help URL and tags — `[Coverage: UNIT]` (profile ⊆ `lib/data/rules/verible.json`) + `[Coverage: MANUAL]`
- [ ] **Tier:** identical on Open Core / EDU / Pro / Enterprise and under both `kBetaPeriod` values; no FeatureGate, no `(PRO)` affordance — `[Coverage: MANUAL]`

---

## Screen-reader and keyboard access (guide §23)

- [ ] At launch the screen reader announces **Open Project…** with no mouse input; the start-screen Tab walk has no silent or nameless stop and cycles — `[Coverage: WIDGET]` (`test/accessibility/screen_reader_test.dart`) + `[Coverage: MANUAL]`
- [ ] F6 / Shift+F6 move between toolbar, IDE panes and status bar on the workspace screen and in the imported-report viewer — `[Coverage: MANUAL]`
- [ ] Imported SARIF: each violation row is announced as one sentence; the rule browser is one Tab stop with Up/Down between rules — `[Coverage: WIDGET]` (`test/accessibility/screen_reader_test.dart`, `test/features/rules/rules_panel_test.dart`) + `[Coverage: MANUAL]`
- [ ] The violation rows are one Tab stop: Up/Down/Home/End move and scroll, the focused row has a visible ring and is shown in Details; Space checks, Enter opens the editor, Shift+F10 opens the context menu — `[Coverage: WIDGET]` (`test/features/violations/widgets/violation_row_focus_test.dart`) + `[Coverage: MANUAL]`
- [ ] Web viewer: F6 / Shift+F6 between the app bar and the panes — `[Coverage: WIDGET]` (`test/features/web_viewer/screens/web_viewer_screen_test.dart`) + `[Coverage: MANUAL]`
- [ ] With two tabs open, each close button is announced "Close *name*" — `[Coverage: UNIT]` (`test/features/workspace/widgets/lintcrux_viewer_tab_bar_strings_test.dart`) + `[Coverage: MANUAL]`
- [ ] The transcript goldens under `test/accessibility/goldens/` were read, not just regenerated, in any release that changed them — `[Coverage: MANUAL]`
- [ ] No ARB string contains an arrow or box glyph — `[Coverage: UNIT]` (`test/static/speakable_strings_test.dart`)
- [ ] **Tier:** identical on every tier under both `kBetaPeriod` values — `[Coverage: MANUAL]`

---

## Telemetry — cross-platform end-to-end pass (staging)

> **Run 2026-08-05/06** against the **staging** dataset `crux_telemetry_dev`, from
> builds made with `--dart-define=TELEMETRY_DEV=true`. What is collected and how to turn
> it off is documented at `https://edacrux.app/telemetry`.
>
> **Method per cell.** Build with the dev flag, launch, let the app settle, quit,
> **launch again** — the launch flush ships the *previous* session's queue — quit,
> then read the dataset after the 60–90 s ingest delay. No UI interaction is needed,
> because under the dev flag consent `unset` counts as `enabled`.
>
> **Attribution.** All four products ship `0.6.0`, so `app_version` cannot separate
> the runs. Rows are attributed by **`installation_id` (`blob8`)**: every platform has
> its own app-support container or browser origin, so each run mints a distinct id
> (recorded below). Runs were serialised, so the UTC window corroborates the id.
> Bring-up probe rows are excluded by `blob2 = '0.6.0'` (probes are `8.8.x` / `9.8.x`
> / `9.9.x`), and the Worker's own contract fixture by
> `blob8 != '6f1b0d3e-2a44-4c9e-9f1a-8d5b7c2e4a10'`.

| Platform | `os` | `form_factor` expected | observed | Result |
|---|---|---|---|---|
| macOS 26.6 (Apple silicon), release | `macos` | `desktop` | `desktop` | **PASS** |
| Chrome 151, release web build | `web` | `web` | `web` | **PASS** — re-run 2026-08-06 after the web form-factor fix; installation `14c6c298-1a39-4e87-ab1a-97e69c574447` |
| Windows | `windows` | `desktop` | — | **DEFERRED** — no Windows machine on this host |
| Linux | `linux` | `desktop` | — | **DEFERRED** — no Linux machine on this host |
| iOS / Android | — | — | — | **N/A — LintCrux ships no mobile target.** The repo has `macos/`, `web/`, `windows/` and `linux/` runners and no `ios/` or `android/` directory, so there is no build to run and nothing is being deferred for want of hardware |

LintCrux's `form_factor` is `web` or `desktop` and nothing else — the `panes` `IdeLayout` is the only layout, so the derivation takes `isWeb` and reads no device class. `desktop` on macOS is the only answer it can give, and it gave it. Note LintCrux is also the one product whose consent lives, on the desktop, in a **file** rather than `SharedPreferences` (`~/Library/Application Support/crux/telemetry/lintcrux.json`), which is what lets `lintcrux --ci` honour the headless rule (the browser viewer has no headless surface and no file system, so there it is `SharedPreferences`, as in the other three products); the installation id below was read from that file and matches the transmitted row.

- [x] The passing row carried the right envelope: `product=lintcrux`, `locale=en`, `country=US` (stamped at the edge), `license_tier=openCore`, and a normalized `session_start` — `[Coverage: MANUAL]` (staging dataset)
- [x] `_sample_interval = 1` on every row, so the `product/event_name/properties` index is not sampling at this volume — `[Coverage: MANUAL]`

**Installation ids** — Chrome web `14c6c298-1a39-4e87-ab1a-97e69c574447` (re-run 2026-08-06) · macOS `54da1116-fcba-4e27-b58a-3031be77c89d`.

### Picking up the deferred cells on another machine

```bash
# On a Windows or Linux host:
flutter build windows --release --dart-define=TELEMETRY_DEV=true   # or: build linux
#   launch the built binary twice, quitting in between, then query the staging
#   dataset for the new installation id.
```

### The negative cases

- [x] **A beta build without the dev flag performs zero telemetry HTTP.** Primary
  evidence is the traffic-level beta-inert test — `[Coverage: PACKAGE]`
  (`crux_telemetry`'s `telemetryServiceProvider` suite, 64 tests, sweeps all 12
  `policy × consent` cells asserting an empty request list) — plus this repo's own
  group — `[Coverage: UNIT]` (`test/core/providers/telemetry_service_provider_test.dart`).
  Corroborated at runtime — `[Coverage: MANUAL]`: a NetCrux release built with **no**
  `--dart-define` was launched twice and **never created `telemetry_queue.jsonl` at
  all** (the live service is never constructed, so `record()` hits the no-op and
  nothing touches disk or the network), and the **production** dataset
  `crux_telemetry` holds **0 rows over 90 days**.
- [x] **Consent `disabled` with the dev flag sends nothing.** — **PASS** on the
  2026-08-06 re-run. Exercised on WaveCrux (shared gate; every product resolves
  the same `telemetryEnabledProvider` from `crux_telemetry`, so the fix is
  suite-wide). See D3 below.

### Defects found — all three FIXED on 2026-08-06

- [x] **D1 — web builds never transmit; the `web` `form_factor` is unreachable in
  practice.** All four products' release web builds produced **zero** rows across two
  page loads each, lintcrux included. A full Chrome `--log-net-log` capture over a 90 s
  web session shows **zero requests to `telemetry.edacrux.app`** (the same capture
  holds 300 references to the page's own assets, so the capture itself is sound).
  Mechanism, reproduced hermetically against `LiveTelemetryService` with a
  `directoryFactory` that throws (exactly what web does): on web `path_provider` is
  unavailable, so `TelemetryEventQueue` degrades to memory-only and `load()` returns
  empty; `start()`'s launch flush therefore runs against an empty `_pending` and
  returns at `if (_pending.isEmpty) return;` **without arming anything**; the only
  remaining trigger is the 6-hourly timer, which no browser session survives. On
  desktop the disk queue carries events to the next launch, which is why only web is
  affected. **Not a shipping-harm defect today** (the pipeline is dark-launched until
  `kBetaPeriod` flips), but the field exists to answer "does the web build earn its
  maintenance" and it cannot. Fix is a design call between (a) backing the queue with
  the `TelemetryStorage` seam on web so it survives a reload, or (b) arming a short
  follow-up flush when the launch flush finds the queue empty — (b) changes the
  documented "this session's events go out on the next six-hourly tick or the next
  launch" contract on every platform. **Lives in
  `crux-shared/packages/crux_telemetry`. **FIXED 2026-08-06** in
  `crux_telemetry` 0.3.0 (crux-shared `1c30b1f`) — option (b), scoped to the
  volatile queue only, so desktop and mobile keep the documented contract
  verbatim: where `hasPersistentBacking()` is false, `record()` arms one flush
  per `volatileFlushInterval` (60 s) and the host's hidden/paused/detached
  signal flushes too. Verified above.**
- [x] **D2 — `form_factor` races the first layout (WaveCrux only).** WaveCrux's
  derivation reads a size that is pushed from inside `MaterialApp.builder`, while the
  envelope is resolved at launch-flush time, ahead of it; on a Pixel Tablet the same
  build in the same orientation reported `desktop` three times and `tablet` once.
  **LintCrux is not affected**: its `telemetryFormFactorFor` takes `isWeb` and
  nothing else, so it has no size to race. **FIXED 2026-08-06** in WaveCrux; the
  shared half is `telemetryFormFactorProvider` becoming `Provider<String?>`,
  where `null` means "not knowable yet" and the flush defers rather than
  reporting a pre-layout default. LintCrux keeps returning a value — `kIsWeb` is a
  compile-time constant, so there is no race to lose and deferring would cost a
  flush interval to answer a question that was never open. Stated in the
  override; see WaveCrux's checklist §13A.3.
- [x] **D3 — a stored consent of `disabled` still transmits under the dev flag.**
  Exercised on WaveCrux: with `flutter.telemetry.consent = disabled` and a
  `TELEMETRY_DEV=true` build, two launches produced a real row in the staging dataset
  from the very installation whose consent is `disabled`. Cause:
  `TelemetryConsentStore.build()` publishes `TelemetryConsentState.unset`
  **synchronously** and loads the persisted value asynchronously, while
  `telemetryEnabledProvider` computes `consent == enabled || (dev && consent ==
  unset)` — so for the first frames of a cold start a stored `disabled` is
  indistinguishable from "not answered", and under the dev flag the gate opens.
  **Blast radius is dev builds only**: with `dev == false` the beta branch
  short-circuits synchronously during the beta, and post-flip the gate reads
  `consent == enabled`, where `unset` fails safe. No shipping build is affected and
  the beta promise is intact — but the dev flag's documented guarantee is
  broken. The 36-cell gating matrix cannot catch this: it seeds consent by assigning
  `notifier.state` directly, so **no cell exercises a value read back through
  storage**. Fix: gate the dev-flag `unset` promotion on the store having settled (it
  already owns a `loaded` completer), and add a storage-backed cell to the matrix.
  **LintCrux shares the gate, so it is affected identically.** Lives in
  `crux-shared/packages/crux_telemetry` and needs a submodule-pin bump in all four
  products. **FIXED 2026-08-06** in `crux_telemetry` 0.3.0: the dev-flag
  promotion of `unset` now waits on `telemetryConsentReadyProvider`, the same
  `loaded` signal the disclosure already waited on, and the package gained a
  pre-load group that seeds *storage* behind a gated read — the gap that let
  this through. Pinned at crux-shared `1c30b1f`.

  One consequence worth recording, because it was found only by re-running on a
  real client: waiting for the store creates a window, and the window is not
  incidental — the store's read does not *start* until something reads the
  telemetry graph, so the first event of every launch falls inside it by
  construction. Resolving the no-op there **discarded** that event, which on web
  is the whole session. The gate is therefore a tri-state now
  (`TelemetryGate { open, closed, pending }`) and `PendingTelemetryService`
  buffers the window, replaying into the live service when the gate opens and
  dropping the buffer when it closes. The beta never enters that state.**

---

## Sign-off

- [ ] All phase groups above signed off
- [ ] Pro overlay checklist ran cleanly (if signing off a Pro build)
- [ ] Cross-platform smoke pass (Linux + macOS + Windows) for any UI-affecting change
