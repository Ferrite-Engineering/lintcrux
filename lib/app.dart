// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';
import 'package:crux_eula/crux_eula.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/core/app_info/about_providers.dart';
import 'package:lintcrux/core/app_info/build_info.dart';
import 'package:lintcrux/core/cli/cli_args.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/core/cli/cli_args_provider.dart';
import 'package:lintcrux/core/eula/lintcrux_eula_storage.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/core/lintcrux_url_launcher.dart';
import 'package:lintcrux/core/platform/linux_desktop_identity.dart';
import 'package:lintcrux/core/platform/platform_localizations.dart';
import 'package:lintcrux/core/platform/web_mode.dart';
import 'package:lintcrux/core/policy/lintcrux_policy_keys.dart';
import 'package:lintcrux/core/router/app_router.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:lintcrux/core/telemetry/lintcrux_telemetry_storage.dart';
import 'package:lintcrux/core/theme/lintcrux_color_theme_bootstrap.dart';
import 'package:lintcrux/core/theme/lintcrux_theme.dart';
import 'package:lintcrux/core/theme/lintcrux_theme_tokens.dart';
import 'package:lintcrux/core/theme/theme_brightness_toggle.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/features/about/lintcrux_about_dialog.dart';
import 'package:lintcrux/features/beta_expiry/beta_expiry_metrics.dart';
import 'package:lintcrux/features/beta_expiry/widgets/beta_expiry_gate.dart';
import 'package:lintcrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/diagnostics/widgets/app_diagnostics_dialog.dart';
import 'package:lintcrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:lintcrux/features/eula/lintcrux_eula_overrides.dart';
import 'package:lintcrux/features/import_viewer/services/sarif_import_flow.dart';
import 'package:lintcrux/features/issue_reporter/lintcrux_issue_reporter.dart';
import 'package:lintcrux/features/issue_reporter/lintcrux_issue_reporter_strings.dart';
import 'package:lintcrux/features/issue_reporter/providers/issue_session_context.dart';
import 'package:lintcrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/project/services/open_project_feedback.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/search/widgets/search_dialog.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/screens/settings_screen.dart';
import 'package:lintcrux/features/telemetry/lintcrux_telemetry_overrides.dart';
import 'package:lintcrux/features/update/lintcrux_update_config.dart';
import 'package:lintcrux/features/update/lintcrux_update_strings.dart';
import 'package:lintcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:lintcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/providers/project_workspace_sync.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/crux_project_resolution.dart';
import 'package:lintcrux/features/workspace/services/incoming_file_kind.dart';
import 'package:lintcrux/features/workspace/services/open_project_in_workspace.dart';
import 'package:lintcrux/features/workspace/widgets/workspace_root.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/plugins/baseline_comparison_opener_provider.dart';
import 'package:lintcrux/plugins/bookmark_panel_opener_provider.dart';
import 'package:lintcrux/plugins/eager_startup_providers.dart';
import 'package:lintcrux/plugins/extra_localizations_delegates_provider.dart';
import 'package:lintcrux/plugins/filter_preset_manager_opener_provider.dart';
import 'package:lintcrux/plugins/pro_action_openers.dart';
import 'package:lintcrux/plugins/pro_opener.dart';
import 'package:lintcrux/plugins/save_filter_preset_opener_provider.dart';
import 'package:lintcrux/plugins/waiver_review_opener_provider.dart';
import 'package:lintcrux/services/cli/cli_args.dart' as launch_cli;
import 'package:lintcrux/services/export/violation_exporters.dart';
import 'package:lintcrux/services/import/edam_import_service.dart';
import 'package:lintcrux/services/import/edam_reader.dart';
import 'package:lintcrux/services/import/filelist_import_service.dart';
import 'package:lintcrux/services/import/filelist_reader.dart';
import 'package:lintcrux/services/logging/severe_log_stderr_sink.dart';
import 'package:lintcrux/services/persistence/engine_binary_overrides_settings_provider.dart';
import 'package:lintcrux/services/persistence/restore_tabs_settings_provider.dart';
import 'package:lintcrux/services/platform/incoming_file_source.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_file_service.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:lintcrux/services/session/session_service.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';
import 'package:lintcrux/services/updates/observed_server_time_store.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Root-scope overrides wiring the cross-suite beta-distribution packages
/// (`crux_updates`, `crux_issue_reporter`) and the `crux_license` beta-expiry
/// clock into LintCrux.
///
/// Spread by [bootstrap] before `extraOverrides`, so the Pro
/// overlay can layer its own bindings (notably
/// `cruxIssueReporterDataProviderProvider`, the "Pro State" category seam) on
/// top per the open-core conflict semantics.
///
/// Exposed (not private) so tests can build a container with exactly the
/// production wiring.
List<Override> lintcruxPhase5Overrides() => <Override>[
  // ── Update mechanism (crux_updates) ──────────────────────────────────
  // No default binding in the package: an unwired product throws here
  // rather than silently never checking for updates.
  cruxUpdateConfigProvider.overrideWithValue(lintcruxUpdateConfig),
  updateBuildInfoProvider.overrideWith(
    (ref) => ref.watch(aboutBuildInfoProvider.future),
  ),
  // The persisted Settings → General toggle. A FutureProvider because the
  // notifier awaits it before the very first launch check, so a user who
  // turned auto-check off is honored on that first tick too.
  autoUpdateCheckEnabledProvider.overrideWith(
    (ref) async => ref.watch(appSettingsProvider).autoCheckForUpdates,
  ),
  // Every successful manifest fetch reports its `server_time`; the store
  // advances monotonically and persists, and `observedServerTimeProvider`
  // below feeds it back into the beta-expiry reckoning. That pairing is
  // what makes expiry resistant to a device-clock rollback.
  observedServerTimeSinkProvider.overrideWith(
    (ref) =>
        (serverTime) => unawaited(
          ref.read(observedServerTimeStoreProvider.notifier).record(serverTime),
        ),
  ),
  cruxUpdateStringsProvider.overrideWith(
    (ref) => LintcruxUpdateStrings(platformL10N()),
  ),
  // Whether paid features are unlocked, from the same gate the paid features
  // use. A seat without them is offered only releases that changed what it
  // gets (the manifest's `open_core_version`), so a release that touched only
  // Pro features puts no banner in front of free users. The Pro overlay's
  // licence binding drives `licenseTierProvider`; this follows it, and a key
  // entered mid-session re-presents the last check's result at once.
  updateEditionProvider.overrideWith(
    (ref) => UpdateEdition.of(
      paidFeaturesUnlocked:
          ref.watch(betaPeriodProvider) ||
          FeatureGate.satisfiesTier(
            LicenseTier.pro,
            ref.watch(licenseTierProvider),
          ),
    ),
  ),
  updateUrlLauncherProvider.overrideWithValue(launchUrl),

  // ── Beta expiry clock hardening (crux_license) ───────────────────────
  observedServerTimeProvider.overrideWith(
    (ref) => ref.watch(observedServerTimeStoreProvider),
  ),

  // ── Beta issue reporter (crux_issue_reporter) ────────────────────────
  cruxIssueReporterConfigProvider.overrideWithValue(
    const CruxIssueReporterConfig(
      productName: 'LintCrux',
      repositorySlug: 'Ferrite-Engineering/lintcrux',
      issueTemplate: 'bug_report.yml',
    ),
  ),
  cruxIssueReporterBuildInfoProvider.overrideWith(
    (ref) => ref.watch(aboutBuildInfoProvider).value,
  ),
  cruxIssueReporterStringsProvider.overrideWith(
    (ref) => LintcruxIssueReporterStrings(platformL10N()),
  ),
  // PRODUCT SEAM — the privacy-scrubbed session snapshot. Also re-bound per
  // tab in `lintcruxTabOverridesFactory`, because everything it reads is
  // per-tab state; this root binding is what a report filed with no tab open
  // resolves to.
  cruxIssueSessionContextProvider.overrideWith(
    buildLintcruxIssueSessionContext,
  ),

  // ── Audit (crux_audit, via crux_license's binding) ───────────────────
  // Stamps every audit event this installation records with the product id.
  // Open-core, not Pro, and deliberately: one JSONL file holds four products'
  // events, and the id is what makes it filterable — an event tagged
  // `unconfigured` would be a wiring bug in a file an administrator is
  // reading during an investigation. Emission is unconditional; the SINK is
  // what an administrator gates, and it is `NoopAuditSink` until one sets
  // `suite.audit.path`.
  //
  // The same string the policy namespace uses, so filtering the log and
  // writing the policy file use one vocabulary.
  cruxAuditProductIdProvider.overrideWithValue(LintCruxPolicyKeys.productId),
];

/// Runs [bootstrap] and ends the process when it handled a command-line-only
/// invocation: the entry point both `lib/main.dart` files call.
///
/// A Flutter desktop runner creates its window at launch and keeps its event
/// loop alive after Dart's `main` returns. [bootstrap]'s `--help`,
/// `--version`, bad-argument and failed-import branches print, set
/// `exitCode` and return, so without this the process sat behind an empty
/// window and a script never saw the exit code. The exit happens here, after
/// stdout and stderr are flushed; [exitProcess] is injectable for tests.
Future<void> runLintcrux({
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  LinuxDesktopApp? linuxDesktopApp,
  Future<void> Function(int code)? exitProcess,
}) async {
  final handled = await bootstrap(
    args: args,
    extraOverrides: extraOverrides,
    linuxDesktopApp: linuxDesktopApp,
  );
  if (!handled || isWebMode) return;
  await (exitProcess ?? _flushAndExit)(exitCode);
}

Future<void> _flushAndExit(int code) async {
  await stdout.flush();
  await stderr.flush();
  exit(code);
}

/// Starts capturing diagnostics. Idempotent under hot restart.
///
/// The issue reporter's ring buffer takes every log record, and uncaught
/// framework and async errors are routed into the log (the console dumps are
/// preserved), so a failure during the session lands in a bug report. The
/// buffer is memory only, though; off the web, [SevereLogStderrSink] also
/// writes SEVERE records to stderr, the one trace a release build leaves once
/// the session is gone. [stderrSink] replaces the process-wide sink in tests.
@visibleForTesting
void attachDiagnosticSinks({SevereLogStderrSink? stderrSink}) {
  CruxIssueReporterLogBuffer.instance
    ..attachToLogging()
    ..captureFlutterErrors();
  if (!isWebMode) (stderrSink ?? SevereLogStderrSink.instance).attach();
}

/// Entry-point body shared by the open-core `lib/main.dart` and the
/// Pro overlay's entry point, both through [runLintcrux].
/// Open core passes only `args`; the Pro overlay adds
/// `extraOverrides: proOverrides` to layer Pro/Enterprise provider
/// implementations on top without forking the bootstrap logic.
///
/// Returns true when [args] selected a command-line-only outcome (`--help`,
/// `--version`, an argument error, or a failed import) that has finished and
/// set `exitCode`; false once the app is running.
///
/// [linuxDesktopApp] is the freedesktop identity installed when the app runs
/// from an AppImage: open core passes nothing and gets
/// [kLintcruxLinuxDesktopApp]; the Pro overlay passes its own.
///
/// Mirrors the WaveCrux pattern documented in `wavecrux/docs/ARCHITECTURE.md`
/// §10 (Extension Points). When adding extension-point providers, follow the
/// open-core-first rule: define the interface and a default implementation
/// here in the open-core repo, then add the Pro override in the overlay.
Future<bool> bootstrap({
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  Widget Function(Widget app)? wrapApp,
  // Nullable with the identity resolved below rather than a default here:
  // the identity is not a constant, because its declared file types are
  // built by a factory that refuses a type the system already maps.
  LinuxDesktopApp? linuxDesktopApp,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // `--reset-telemetry-consent` puts this installation back to "never
  // answered", so the one-time disclosure mounts again this launch rather than
  // next one. A testing affordance: the dialog is deliberately
  // once-per-installation, which makes it the surface hardest to see twice.
  //
  // Before the container is built, because `TelemetryConsentStore` starts
  // reading the persisted value the moment anything touches the telemetry
  // graph. The installation id is left alone — see `resetTelemetryConsent`.
  if (args.contains('--reset-telemetry-consent')) {
    await resetTelemetryConsent(const LintcruxTelemetryStorage());
  }

  // `--reset-eula` forgets this installation's accepted EULA version, so the
  // agreement is presented again this launch. The same testing affordance and
  // the same ordering constraint as the telemetry flag above: the acceptance
  // store reads the persisted version the first time the gate is built, so
  // the reset has to land before the container exists. Combined with
  // `--reset-telemetry-consent`, the agreement still comes first — the gate
  // holds the rest of the app, the disclosure included, until it is accepted.
  if (args.contains('--reset-eula')) {
    await resetCruxEulaAcceptance(const LintcruxEulaStorage());
  }

  // Attached BEFORE the first provider is constructed so early-startup
  // warnings (engine discovery, settings restore, CXP bind failures) are
  // already captured by the time a user notices something is wrong and opens
  // the reporter.
  attachDiagnosticSinks();

  // Integration-harness seam: when non-null, the fully-composed app
  // widget is passed through [wrapApp] before runApp. The macOS
  // integration driver uses this to mount the tree inside
  // ExcludeSemantics — the embedder's AccessibilityBridge can segfault
  // (CreateRemoveReparentedNodesUpdate) under heavy semantics-node
  // churn when the OS enables accessibility for the test app.
  // Production callers leave it null.
  void launch(Widget app) => runApp(wrapApp == null ? app : wrapApp(app));

  // Register the suite-shared chrome token catalog so Settings →
  // Appearance and `.crux-theme.json` packs resolve every chrome token
  // id to a registered descriptor. Idempotent — a second bootstrap
  // (test hot-restart, doubled init) is a no-op.
  registerLintcruxThemeTokens();

  // Web mode skips the entire CLI surface: browsers don't deliver
  // command-line arguments, the I/O symbols (`stderr`, `stdout`,
  // `exitCode`) throw at runtime, and the web read-only flow drives
  // its own input via the SARIF file picker / `?sarif=<url>` query
  // parameter (see [WebLandingScreen]). The desktop bootstrap below
  // is unchanged.
  if (isWebMode) {
    launch(
      ProviderScope(
        overrides: <Override>[
          cliArgsProvider.overrideWithValue(CliArgs.empty),
          ...lintcruxPhase5Overrides(),
          // Bind the telemetry pipeline: the product slug, the file-backed
          // consent store the headless binary also reads, the localized consent
          // copy, build info, the form-factor derivation and the locale.
          // Spread BEFORE extraOverrides so the Pro overlay can layer the
          // Enterprise policy-file decision on top per the open-core conflict
          // semantics. Inert for the whole beta — nothing here constructs the
          // live service while `kBetaPeriod` is on.
          // Bind the EULA gate's persistence and quit path. Acceptance is
          // required at every edition, Open Core included (EULA 2.1).
          ...lintcruxEulaOverrides,
          ...lintcruxTelemetryOverrides,
          // Bridge LintCrux persistence (AppSettings.core.activeThemeName
          // + themeOverrides) into crux_theme's cruxColorThemeProvider,
          // exactly as WaveCrux / NetCrux do. Spread before
          // extraOverrides so the Pro overlay can layer its own
          // override on top per the open-core conflict semantics.
          lintcruxCruxColorThemeOverride,
          ...extraOverrides,
        ],
        child: const LintcruxApp(),
      ),
    );
    return false;
  }

  // Suite-shared launch recovery flags (`--reset` / `--no-restore`),
  // ported from WaveCrux (`services/cli/cli_args.dart`). Parsed first and
  // stripped from the argument list so the strict `package:args` parser
  // below — shared with the headless binary, where an unknown flag is a
  // usage error by design — never sees them.
  final launchFlags = launch_cli.parseCliArgs(args);

  // Parse the CLI surface up front so the app's startup wiring can read
  // the [CliArgs] snapshot via [cliArgsProvider]. On parse error or
  // explicit `--help` / `--version`, we print the usage block (or
  // version string) and short-circuit before constructing the widget
  // tree.
  final parser = CliArgsParser();
  final result = parser.parse(launch_cli.stripLaunchFlags(args));
  if (!result.isSuccess) {
    stderr
      ..writeln('lintcrux: ${result.error}')
      ..writeln()
      ..writeln(result.usage);
    exitCode = 64; // EX_USAGE
    return true;
  }
  final cliArgs = result.args!;
  if (cliArgs.showHelp) {
    stdout
      ..writeln(result.usage)
      ..writeln(launch_cli.cliHelpText());
    return true;
  }
  if (cliArgs.showVersion) {
    // The same line the headless binary prints; the version constant is
    // held equal to pubspec.yaml by build_info_matches_pubspec_test.
    stdout.writeln(LintCruxBuildInfo.versionLine);
    return true;
  }

  // `--import-filelist <path>` produces a `.lintcrux`
  // beside the source filelist. The resulting project is then opened
  // in the UI by the `_maybeLoadCliProject` post-frame callback (it
  // walks `cliArgs.paths` for `.lintcrux` files). We append the
  // emitted path to the CLI args' paths list so the existing loader
  // picks it up without a special-case branch.
  var effectiveCliArgs = cliArgs;
  if (cliArgs.importFilelistPath != null &&
      cliArgs.importFilelistPath!.isNotEmpty) {
    try {
      const service = FilelistImportService();
      final result = service.importFilelist(
        filelistPath: cliArgs.importFilelistPath!,
      );
      stdout.writeln(
        'Imported filelist → ${result.projectFilePath}',
      );
      effectiveCliArgs = cliArgs.copyWith(
        paths: <String>[...cliArgs.paths, result.projectFilePath],
      );
    } on FilelistImportException catch (e) {
      stderr.writeln('lintcrux: ${e.message}');
      exitCode = 65; // EX_DATAERR
      return true;
    }
  }

  // `--import-edam <path>` — the FuseSoC/Edalize twin of
  // `--import-filelist`: produce a `.lintcrux` beside the `.eda.yml`
  // and let the existing loader open it. Non-fatal reader warnings go
  // to stderr so a scripted GUI launch still surfaces them.
  if (cliArgs.importEdamPath != null && cliArgs.importEdamPath!.isNotEmpty) {
    try {
      const service = EdamImportService();
      final result = service.importEdam(
        edamPath: cliArgs.importEdamPath!,
      );
      for (final warning in result.warnings) {
        stderr.writeln('lintcrux: warning: $warning');
      }
      stdout.writeln(
        'Imported EDAM → ${result.projectFilePath}',
      );
      effectiveCliArgs = effectiveCliArgs.copyWith(
        paths: <String>[...effectiveCliArgs.paths, result.projectFilePath],
      );
    } on EdamImportException catch (e) {
      stderr.writeln('lintcrux: ${e.message}');
      exitCode = 65; // EX_DATAERR
      return true;
    }
  }

  // `--reset` is the documented escape hatch for a session so corrupt it
  // wedges startup: wipe the auto-managed workspace.json and every per-tab
  // session sidecar, then launch into an empty workspace. Runs BEFORE the
  // widget tree exists so the workspace notifier's first load sees nothing
  // to restore. Scoped to session state — settings, waivers, and recent
  // files are kept. Only reached on the desktop path (web returned above).
  if (launchFlags.reset) {
    final workspaceService = WorkspaceService(
      codec: const LintcruxWorkspaceCodec(),
    );
    await workspaceService.clear();
    await workspaceService.clearAllSidecars();
    stdout.writeln(
      'LintCrux: cleared saved session and workspace state (--reset).',
    );
  }

  // Resolve the launch-restore preference before the widget tree exists.
  // `WorkspaceNotifier.build` is the only production caller of
  // `WorkspaceService.load` and consults this *before* loading, so the
  // decision has to be in hand by then — and it has to be a plain value, not
  // a future the notifier awaits, or every workspace-touching widget test
  // hangs waiting on a real-event-loop reply. See
  // [launchRestoreDecisionProvider]. `--no-restore` forces the declining
  // answer for this launch only, without touching the persisted preference
  // or the workspace document — the non-destructive recovery lever.
  final restoreTabsOnLaunch =
      !launchFlags.noRestore && await loadRestoreTabsOnLaunch();
  // Resolved before `runApp` for the same reason: a restored tab runs its
  // engines as it opens, and those runs must use the binaries the user chose
  // in Settings > Engines. See [launchEngineBinaryOverridesProvider].
  final engineBinaryOverrides = await loadEngineBinaryOverrides();

  // Windows/Linux only: switch the window to frameless (TitleBarStyle.hidden)
  // and show it once ready, so the in-window VS Code-style title bar drawn by
  // DesktopMenuBar replaces the OS title bar. Only reached on the desktop
  // launch path (web returns earlier) and a no-op off Windows/Linux. Geometry
  // restore across sessions is not wired yet — the window opens at default size.
  if (useCustomWindowChrome) {
    await initWindowChrome();
  }

  // AppImage first-run desktop self-integration (Linux/Wayland): write the
  // host-side .desktop + hicolor icons so GNOME/Ubuntu matches this window's
  // app_id to its dock icon. Only reached on the desktop launch path (web
  // returned earlier); inert off Linux and off AppImage; never throws.
  await maybeIntegrateDesktopEntry(linuxDesktopApp ?? kLintcruxLinuxDesktopApp);

  launch(
    ProviderScope(
      overrides: <Override>[
        // Open-core overrides go here first. Pro overrides are spread last
        // so later overrides win for any shared extension-point provider.
        cliArgsProvider.overrideWithValue(effectiveCliArgs),
        launchRestoreDecisionProvider.overrideWithValue(restoreTabsOnLaunch),
        launchEngineBinaryOverridesProvider.overrideWithValue(
          engineBinaryOverrides,
        ),
        ...lintcruxPhase5Overrides(),
        // Bind the EULA gate's persistence and quit path — see the web-mode
        // scope above.
        ...lintcruxEulaOverrides,
        // Bind the telemetry pipeline — see the web-mode scope above for
        // why it is spread before `extraOverrides`.
        ...lintcruxTelemetryOverrides,
        // Bridge LintCrux persistence (AppSettings.core.activeThemeName
        // + themeOverrides) into crux_theme's cruxColorThemeProvider,
        // exactly as WaveCrux / NetCrux do. Spread before
        // extraOverrides so the Pro overlay can layer its own
        // override on top per the open-core conflict semantics.
        lintcruxCruxColorThemeOverride,
        ...extraOverrides,
      ],
      child: const LintcruxApp(),
    ),
  );
  return false;
}

/// Root widget that wires the LintCrux theme, localization, and routing
/// into a [MaterialApp.router]. The Welcome screen lives at `/`; future
/// routes (dashboard, settings, about) are registered in
/// [appRouterProvider].
/// Output format selector for [`_LintcruxAppState._handleExport`]. One
/// enum value per `LintcruxAction.exportX` action.
enum ExportFormat { sarif, json, csv, html }

class LintcruxApp extends ConsumerStatefulWidget {
  const LintcruxApp({super.key});

  @override
  ConsumerState<LintcruxApp> createState() => _LintcruxAppState();
}

class _LintcruxAppState extends ConsumerState<LintcruxApp> {
  bool _initialProjectLoadStarted = false;
  final GlobalKey<WorkspaceRootState> _workspaceRootKey =
      GlobalKey<WorkspaceRootState>();

  @override
  void initState() {
    super.initState();
    // Kick off the CLI-driven project load on the next microtask so
    // Riverpod providers are fully wired and the WorkspaceRoot has
    // mounted (its `initState` resolves the root ProviderContainer
    // and constructs the TabContainerManager).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLoadCliProject();
    });
  }

  ProviderContainer Function(crux.TabId)? _tabsForId() {
    // Resolve the WorkspaceRoot's container managers via the
    // GlobalKey's current state. The GlobalKey is attached to the
    // WorkspaceRoot widget itself so currentState yields the
    // WorkspaceRootState — its `tabs` getter gives the
    // TabContainerManager directly, no widget-tree walk required.
    final state = _workspaceRootKey.currentState;
    if (state == null) return null;
    return state.tabs.containerFor;
  }

  void _maybeLoadCliProject() {
    if (_initialProjectLoadStarted) return;
    _initialProjectLoadStarted = true;
    final args = ref.read(cliArgsProvider);
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(tabsForId);

    // Workspace CLI semantics, processed in the order:
    //  1. --workspace replaces the auto-saved workspace document.
    //  2. positional .lintcrux paths each open as new tabs in the
    //     (now-restored) workspace.
    //  3. --session applies the named session export onto the
    //     first .lintcrux path opened (or opens a tab for its
    //     referenced project if no positional was supplied).
    //  4. Then any file macOS opened the app with, so a double-clicked
    //     project lands after the restored workspace, as a positional
    //     argument does.
    unawaited(_runCliFlow(args, opener).then((_) => _receiveIncomingFiles()));
  }

  StreamSubscription<String>? _incomingFiles;

  /// Opens the file that launched the app, then every file opened while it
  /// runs: a Finder double-click, `open -a`, or a drop on the Dock icon.
  /// macOS delivers these through the runner's `application(_:open:)`, never
  /// through `argv`; see [IncomingFileSource].
  Future<void> _receiveIncomingFiles() async {
    if (!mounted) return;
    final source = ref.read(incomingFileSourceProvider);
    final initial = await source.initialFile();
    if (!mounted) return;
    _incomingFiles = source.files.listen(
      (path) => unawaited(_openIncomingFile(path)),
    );
    if (initial != null) await _openIncomingFile(initial);
  }

  /// Opens [path] through the path that already opens its kind of file, so
  /// a double-click behaves exactly like the matching command-line argument
  /// or menu command, errors and all. See [IncomingFileKind].
  Future<void> _openIncomingFile(String path) async {
    BuildContext? navigatorContext() => ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    final kind = classifyIncomingFile(path);
    if (kind == null) {
      final ctx = navigatorContext();
      if (ctx != null && ctx.mounted) {
        showCruxInfoSnack(
          ctx,
          L10N.of(ctx).incomingFileNotSupported(p.basename(path)),
        );
      }
      return;
    }
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(tabsForId);
    switch (kind) {
      case IncomingFileKind.project:
        final result = await opener.openProject(path);
        final ctx = navigatorContext();
        if (ctx != null && ctx.mounted) showOpenProjectOutcome(ctx, result);
      case IncomingFileKind.workspace:
        final error = await opener.openWorkspace(path);
        final ctx = navigatorContext();
        if (error != null && ctx != null && ctx.mounted) {
          showCruxErrorSnack(ctx, L10N.of(ctx).workspaceLoadFailed(error));
        }
      case IncomingFileKind.session:
        final result = await opener.openSession(path);
        final ctx = navigatorContext();
        if (ctx != null && ctx.mounted) showOpenProjectOutcome(ctx, result);
      case IncomingFileKind.filelist:
        await _importFilelist(path, tabsForId);
      case IncomingFileKind.sarif:
        final ctx = navigatorContext();
        if (ctx != null && ctx.mounted) {
          await runSarifImportFlow(ctx, ref, path: path);
        }
      case IncomingFileKind.hdlSource:
        final ctx = navigatorContext();
        if (ctx != null && ctx.mounted) {
          await _addSourcesToActiveProject(ctx, <String>[path]);
        }
    }
  }

  @override
  void dispose() {
    unawaited(_incomingFiles?.cancel());
    super.dispose();
  }

  Future<void> _runCliFlow(
    CliArgs args,
    OpenProjectInWorkspace opener,
  ) async {
    // This runs from a post-frame callback, so the navigator is up and each
    // outcome can be reported where the user will see it.
    BuildContext? navigatorContext() => ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;

    final workspacePath = args.workspacePath;
    if (workspacePath != null && workspacePath.isNotEmpty) {
      // openWorkspace returns null on success or an error string on failure,
      // and on failure the workspace falls back to the auto-saved document.
      // The error is shown: a mistyped or unreadable --workspace otherwise
      // opens the previous session with no word that it was not the one asked
      // for.
      final error = await opener.openWorkspace(workspacePath);
      final ctx = navigatorContext();
      if (error != null && ctx != null && ctx.mounted) {
        showCruxErrorSnack(ctx, L10N.of(ctx).workspaceLoadFailed(error));
      }
    }

    // A `<design>.crux-project` manifest opens the lint project it names.
    final projectPaths = args.paths
        .where(isOpenableProjectPath)
        .toList(growable: false);
    for (final path in projectPaths) {
      final result = await opener.openProject(path);
      final ctx = navigatorContext();
      if (ctx != null && ctx.mounted) showOpenProjectOutcome(ctx, result);
    }

    final sessionPath = args.sessionPath;
    if (sessionPath != null && sessionPath.isNotEmpty) {
      // The session refers to its own project file internally, so
      // openSession opens a fresh tab regardless of how many
      // positional `.lintcrux` arguments preceded it. Matches the
      // documented `--session <path>` semantic in the CliArgsParser
      // usage block.
      final result = await opener.openSession(sessionPath);
      final ctx = navigatorContext();
      if (ctx != null && ctx.mounted) showOpenProjectOutcome(ctx, result);
    }
  }

  Future<void> _handleOpenProject() async {
    final picker = ref.read(projectPickerProvider);
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    if (ctx == null || !ctx.mounted) return;
    final l10n = L10N.of(ctx);
    final path = await picker.pickProjectFile(
      confirmButtonText: l10n.filePickerOpenProjectButton,
      typeLabel: l10n.filePickerTypeProjectLabel,
    );
    if (path == null) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(tabsForId);
    final result = await opener.openProject(path);
    if (ctx.mounted) showOpenProjectOutcome(ctx, result);
    if (result is OpenProjectFailure) return;
    // Recorded per entry point rather than inside `OpenProjectInWorkspace`,
    // which cannot tell a picked project from a restored tab or a CLI
    // argument — and "which project entry paths matter" is a question about
    // the gesture, not about the load.
    _record('project.opened', <String, Object?>{
      'source': telemetryEnumToken(ProjectOpenSource.picker),
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    // Anchor the workspace↔registry sync for the app's lifetime (desktop
    // only — the web build is the read-only SARIF viewer with no
    // multi-tab workspace). Watching the provider here constructs it once
    // and installs its boot-time listeners so opening a project through
    // any real entry point (File → Open / CLI / restore / session /
    // workspace) records it into the ProjectRegistry. Without this anchor
    // the registry stays permanently empty. See ProjectWorkspaceSync.
    if (!isWebMode) {
      ref
        ..watch(projectWorkspaceSyncProvider)
        // Start the CXP server eagerly whenever Settings → CXP Cross-Probe →
        // "Enable CXP server" is on, decoupled from the cross-probe panel.
        // Watching the lifecycle here (app shell, alive for the whole
        // session) builds `CxpServerLifecycle`, which binds the socket,
        // publishes this peer's manifest under the suite-shared
        // `crux/cxp/peers/` directory, and starts discovery + the peer
        // connector — so enabling the setting has an observable effect
        // without opening any panel. Mirrors
        // SimCrux's `_SimcruxAppChrome` eager watch and NetCrux's
        // `CxpInboundListener`. Gated internally on the persisted
        // `cxpServerEnabled` setting: disabled resolves to a non-running
        // state and binds nothing.
        ..watch(cxpServerLifecycleProvider)
        // Install the attention gate for the whole session so the
        // `requestAttentionOnCrossProbe` setting swaps the global
        // `windowAttentionRequester` backend (dock bounce / taskbar flash /
        // Wayland urgency, vs a no-op) as it changes, applying the persisted
        // value at boot via `fireImmediately`.
        ..watch(cxpAttentionGateProvider);
    }
    // Drive the Material brightness from the active preset (so picking
    // Crux Light flips the chrome to light, Solarized Dark to dark,
    // etc.) and apply the preset's chrome tokens onto the base LintCrux
    // theme. See applyChromeTokens in package:crux_theme/crux_theme.dart.
    final cruxColorTheme = ref.watch(cruxColorThemeProvider);
    final chromeExt = CruxThemeExtension(theme: cruxColorTheme);
    final themeMode = themeModeFromBrightness(cruxColorTheme);
    final lightTheme = applyChromeTokens(
      LintcruxTheme.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[chromeExt],
      ),
      chromeExt,
    );
    final darkTheme = applyChromeTokens(
      LintcruxTheme.dark().copyWith(
        extensions: <ThemeExtension<dynamic>>[chromeExt],
      ),
      chromeExt,
    );
    // High-contrast variants, applied by MaterialApp when the OS
    // "increase contrast" accessibility setting is on. Mirrors WaveCrux's
    // app.dart wiring so LintCrux has accessibility parity.
    final hcLightTheme = applyChromeTokens(
      LintcruxTheme.highContrastLight().copyWith(
        extensions: <ThemeExtension<dynamic>>[chromeExt],
      ),
      chromeExt,
    );
    final hcDarkTheme = applyChromeTokens(
      LintcruxTheme.highContrastDark().copyWith(
        extensions: <ThemeExtension<dynamic>>[chromeExt],
      ),
      chromeExt,
    );
    // Pro overlay contributes its own localization delegates (e.g.
    // `L10NPro.delegate`) through `extraLocalizationsDelegatesProvider`.
    // The open-core default is an empty list so the open-core build
    // does not depend on any Pro-only ARB output.
    final extraDelegates = ref.watch(extraLocalizationsDelegatesProvider);
    // Apply the persisted UI language (Appearance → Language). Without this
    // watch CoreSettings.locale is persisted but never applied, and the four
    // shipped translations are unreachable except via the OS language.
    final localeTag = ref.watch(
      appSettingsProvider.select((s) => s.core.locale),
    );
    // Shared with the telemetry consent surfaces, which resolve their copy
    // from a root-scope provider rather than a BuildContext and must land on
    // the same language this MaterialApp is about to draw.
    final locale = localeForSettingsTag(localeTag);
    return MaterialApp.router(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      onGenerateTitle: (context) => L10N.of(context).appTitle,
      theme: lightTheme,
      darkTheme: darkTheme,
      highContrastTheme: hcLightTheme,
      highContrastDarkTheme: hcDarkTheme,
      themeMode: themeMode,
      localizationsDelegates: <LocalizationsDelegate<Object?>>[
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        ...extraDelegates,
      ],
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      routerConfig: router,
      // Wraps the routed subtree in the workspace root (which owns
      // the per-tab and per-pane `ProviderContainer` managers plus
      // the `WorkspaceLifecycleObserver`) and the shortcut manager.
      // Web mode skips the WorkspaceRoot — the web build is the
      // read-only SARIF viewer and doesn't host multi-tab workspaces.
      builder: (context, child) {
        // Single source of truth: every LintcruxAction with a default
        // keyboard binding gets a handlers-map entry that delegates to
        // `_dispatchPaletteAction`. The menu bar dispatches through
        // the same function (line below) and the command palette also
        // dispatches through it — so keyboard, menu, and palette stay
        // in lockstep by construction. New actions only need a
        // `_dispatchPaletteAction` case to light up across all three
        // surfaces. Replaces the prior 6-entry partial map which left
        // most shortcuts silently no-op'ing.
        final shortcuts = ShortcutManagerWidget(
          handlers: <LintcruxAction, VoidCallback>{
            for (final action in LintcruxAction.values)
              action: () => _dispatchPaletteAction(action),
          },
          child: _EagerStartupGate(
            child: child ?? const SizedBox.shrink(),
          ),
        );
        // Wrap the shortcut/workspace subtree in the native platform
        // menu bar so every user-facing action is reachable via the
        // browsable categorized menu in addition to the keyboard and
        // command palette. The menu bar is a no-op on web and mobile.
        final withMenuBar = DesktopMenuBar(
          onAction: _dispatchPaletteAction,
          child: shortcuts,
        );
        final routed = isWebMode
            ? withMenuBar
            : WorkspaceRoot(key: _workspaceRootKey, child: withMenuBar);
        // Nesting order is deliberate, outermost first:
        //
        //  * `RepaintBoundary` — the beta issue reporter's screenshot source.
        //    It wraps everything so a report captures the app as the user
        //    sees it, banners included.
        //  * `BetaExpiryGate` — the per-release hard build expiry. Outside
        //    the update banner so an expired-beta modal covers it. A no-op in
        //    every build with no `BETA_EXPIRY` injected.
        //  * `UpdateBanner` — the "a newer LintCrux is available" strip.
        //    Renders nothing on web, where the app self-updates on deploy.
        final Widget app = RepaintBoundary(
          key: ref.watch(cruxAppScreenshotBoundaryKeyProvider),
          child: BetaExpiryGate(
            // The one-time telemetry disclosure. Inside BetaExpiryGate so
            // an expired-beta blocking modal covers it (an expired build has
            // nothing to collect and nothing the user can do about it), and
            // above UpdateBanner so the disclosure is not competing for the
            // top of the window with an update prompt.
            //
            // Renders its child untouched for the whole beta — during the beta
            // with no dev flag `telemetryConsentPromptVisibleProvider` is
            // false and this widget is a pass-through, so a beta build's UI is
            // byte-for-byte what it was before telemetry existed.
            //
            // `isPhoneLayout` is deliberately left at its default `false`:
            // LintCrux has no phone layout (it is desktop-only), so the disclosure
            // is the centred dialog card on every host it can run on. The
            // metrics are `BetaExpiryMetrics`, the same constants the two
            // beta strips use, so all three surfaces are sized identically.
            //
            // The package's touch-target floor (44 dp) and body size (13 pt)
            // already equal `BetaExpiryMetrics`; only the icon differs, so
            // only the icon is restated.
            child: CruxEulaGate(
              // OUTSIDE the telemetry disclosure, and that ordering is not a
              // preference. The disclosure asks for consent to a term the EULA
              // itself defines (EULA 8), so collecting it first would have the
              // user answering a question about a contract they had not been
              // shown. It is also the only ordering under which the
              // EEA/UK/CH/KR opt-in default is defensible.
              //
              // Inside the expiry gate, on the same rule that puts the
              // disclosure there: an expired build has nothing to license.
              //
              // Not localized — see CruxEulaStrings. The agreement is executed
              // in English, so its chrome stays English rather than implying a
              // translated contract exists.
              metrics: const CruxEulaMetrics(
                iconSize: BetaExpiryMetrics.iconSize,
              ),
              child: TelemetryConsentGate(
                metrics: const CruxTelemetryConsentMetrics(
                  iconSize: BetaExpiryMetrics.iconSize,
                ),
                // The package's default metrics already match
                // `BetaExpiryMetrics` (44 dp touch target, 20 dp icon, 13 pt
                // body), so the two beta strips are sized identically without
                // restating the numbers here.
                child: UpdateBanner(child: routed),
              ),
            ),
          ),
        );
        // Windows/Linux: restore the drop shadow + drag-to-resize edges the
        // frameless window loses. No-op wrapper elsewhere.
        return useCustomWindowChrome ? buildWindowFrame(app) : app;
      },
    );
  }

  /// Dispatches a [LintcruxAction] selected from any of the three
  /// surfaces (keyboard shortcut, platform menu bar, command palette).
  ///
  /// Single source of truth — the handlers map registered with
  /// `ShortcutManagerWidget`, the `onAction:` callback handed to
  /// `DesktopMenuBar`, and the palette's selection callback all reach
  /// the same enum-driven switch. Actions whose UI surface hasn't
  /// landed yet surface a snackbar via [_snackUnimplemented] so the
  /// user sees the dispatch happened rather than a silent no-op.
  /// Pro-tier actions whose opener isn't installed (open-core build)
  /// snackbar via [_snackProGated] with the same intent.
  void _dispatchPaletteAction(LintcruxAction action) {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    switch (action) {
      // ── File ───────────────────────────────────────────────────
      case LintcruxAction.openProject:
        unawaited(_handleOpenProject());
      case LintcruxAction.openSources:
        unawaited(_handleOpenSources());
      case LintcruxAction.importVivadoFilelist:
        unawaited(_handleImportFilelist());
      case LintcruxAction.importEdam:
        unawaited(_handleImportEdam());
      case LintcruxAction.resetWorkspace:
        unawaited(_handleResetWorkspace());
      case LintcruxAction.saveSession:
        // Writes a `.lintcrux-session` snapshot of the active tab. There
        // used to be a second action, `exportTabAsSession`, dispatching to
        // this same handler and sitting three rows away in the File menu —
        // two menu items, one behaviour, so the duplicate was removed to
        // match the other suite apps' File menus.
        unawaited(_handleExportTabAsSession());
      case LintcruxAction.openSession:
        unawaited(_handleOpenSession());
      case LintcruxAction.importSarif:
        unawaited(_handleImportSarif());
      case LintcruxAction.newWorkspace:
        // Shares `_handleResetWorkspace` with `resetWorkspace`, so the
        // notifier's own override emits `workspace.reset` for both and this
        // case adds the one thing the shared handler cannot know: the user
        // asked for a *new* workspace rather than a wipe. WaveCrux's
        // new-workspace command records the same pair.
        unawaited(
          _handleResetWorkspace().then((didReset) {
            if (didReset && mounted) _record('workspace.created');
          }),
        );
      case LintcruxAction.saveWorkspaceAs:
        unawaited(_handleSaveWorkspaceAs());
      case LintcruxAction.openWorkspace:
        unawaited(_handleOpenWorkspace());
      case LintcruxAction.newTab:
        // LintCrux tabs are bound to a `.lintcrux` project file (see
        // `LintcruxTabPayload.projectPath`), so "new tab" reuses the
        // new-project save-dialog flow — pick a destination, write a
        // default `.lintcrux`, open it as a tab. Matches the Welcome
        // screen's "New Project…" button.
        unawaited(_handleNewProjectGlobal());
      case LintcruxAction.closeTab:
        unawaited(_handleCloseTab());
      case LintcruxAction.closeActiveProject:
        unawaited(_handleCloseTab());
      // ── App ────────────────────────────────────────────────────
      case LintcruxAction.quit:
        exit(0);
      case LintcruxAction.openSettings:
        if (ctx != null) {
          unawaited(_handleOpenSettings(ctx));
        }
      // ── Run ────────────────────────────────────────────────────
      case LintcruxAction.runAllEngines:
        unawaited(_handleRunAllEngines());
      case LintcruxAction.cancelRun:
        _handleCancelRun();
      // ── View ───────────────────────────────────────────────────
      case LintcruxAction.toggleTheme:
        _handleToggleTheme();
      case LintcruxAction.splitPaneRight:
        unawaited(_handleSplitPaneRight());
      case LintcruxAction.closePane:
        unawaited(_handleClosePane());
      case LintcruxAction.focusOtherPane:
        unawaited(_handleFocusOtherPane());
      case LintcruxAction.moveTabToOtherPane:
        unawaited(_handleMoveTabToOtherPane());
      case LintcruxAction.nextTab:
        unawaited(_handleSwitchTabBy(1));
      case LintcruxAction.previousTab:
        unawaited(_handleSwitchTabBy(-1));
      // ── Search / palette ──────────────────────────────────────
      case LintcruxAction.openCommandPalette:
        if (ctx != null && ctx.mounted) {
          unawaited(
            CommandPaletteDialog.show(
              ctx,
              onAction: _dispatchPaletteAction,
            ),
          );
        }
      case LintcruxAction.focusSearch:
        _handleFindInViolations();
      case LintcruxAction.searchAcrossProjects:
        unawaited(_handleOpener(action, searchAcrossProjectsOpenerProvider));
      // ── Tools / Help ──────────────────────────────────────────
      case LintcruxAction.exportSarif:
        unawaited(_handleExport(ExportFormat.sarif));
      case LintcruxAction.exportJson:
        unawaited(_handleExport(ExportFormat.json));
      case LintcruxAction.exportCsv:
        unawaited(_handleExport(ExportFormat.csv));
      case LintcruxAction.exportHtml:
        unawaited(_handleExport(ExportFormat.html));
      case LintcruxAction.openTabDiagnostics:
        unawaited(_handleOpenTabDiagnostics());
      case LintcruxAction.openAppDiagnostics:
        unawaited(_handleOpenAppDiagnostics());
      case LintcruxAction.openAbout:
        _handleOpenAbout();
      case LintcruxAction.checkForUpdates:
        unawaited(_handleCheckForUpdates());
      case LintcruxAction.submitIssue:
        unawaited(_handleSubmitIssue());
      case LintcruxAction.openDocumentation:
        unawaited(lintcruxLaunchUrl(Uri.parse(HelpUrls.docs)));
      case LintcruxAction.openCrossProbePanel:
        _handleOpenCrossProbePanel();
      // saveFilterPreset / manageFilterPresets are open-core aliases
      // for the Pro savePresetFromCurrentFilter / openFilterPresetManager
      // actions. Open-core has no save/manage UI of its own (preset
      // authoring is a Pro feature); the aliases dispatch through the
      // Pro openers so the menu / palette entries always reach the
      // intended surface.
      case LintcruxAction.saveFilterPreset:
        unawaited(_handleOpener(action, saveFilterPresetOpenerProvider));
      case LintcruxAction.manageFilterPresets:
        unawaited(_handleOpener(action, filterPresetManagerOpenerProvider));
      // ── Pro-tier openers ────────────────────────────
      case LintcruxAction.openWaiverReview:
        unawaited(_handleOpener(action, waiverReviewOpenerProvider));
      case LintcruxAction.setBaseline:
        unawaited(_handleOpener(action, setBaselineOpenerProvider));
      case LintcruxAction.clearBaseline:
        unawaited(_handleOpener(action, clearBaselineOpenerProvider));
      case LintcruxAction.openBaselineComparison:
        unawaited(_handleOpener(action, baselineComparisonOpenerProvider));
      case LintcruxAction.showRuleTrendChart:
        unawaited(_handleOpener(action, showRuleTrendChartOpenerProvider));
      case LintcruxAction.showSeverityClassDriftChart:
        unawaited(
          _handleOpener(action, showSeverityClassDriftChartOpenerProvider),
        );
      case LintcruxAction.showProjectTrendChart:
        unawaited(_handleOpener(action, showProjectTrendChartOpenerProvider));
      case LintcruxAction.showCalendarHeatmap:
        unawaited(_handleOpener(action, showCalendarHeatmapOpenerProvider));
      case LintcruxAction.configureTrendRetention:
        unawaited(_handleOpener(action, configureTrendRetentionOpenerProvider));
      case LintcruxAction.openBookmarksManager:
        unawaited(_handleOpener(action, bookmarkPanelOpenerProvider));
      case LintcruxAction.toggleBookmarkForCurrentViolation:
        unawaited(_handleOpener(action, toggleBookmarkOpenerProvider));
      case LintcruxAction.runVeribleDryRun:
        unawaited(_handleOpener(action, runVeribleDryRunOpenerProvider));
      case LintcruxAction.applyVeribleFixes:
        unawaited(_handleOpener(action, applyVeribleFixesOpenerProvider));
      case LintcruxAction.configureVeribleBinary:
        unawaited(_handleOpener(action, configureVeribleBinaryOpenerProvider));
      case LintcruxAction.clearLintCache:
        unawaited(_handleOpener(action, clearLintCacheOpenerProvider));
      case LintcruxAction.openLintCacheStats:
        unawaited(_handleOpener(action, openLintCacheStatsOpenerProvider));
      case LintcruxAction.forceLintRunWithoutCache:
        unawaited(
          _handleOpener(action, forceLintRunWithoutCacheOpenerProvider),
        );
      // The switcher, recents and cross-project search are Pro-tier
      // views onto the Pro multi-project registry. Open core binds the
      // no-op registry and leaves these openers null, so the Pro-gated
      // snack is the true statement — unlike the earlier state, where
      // the actions were Pro-badged but unimplemented in every tier and
      // the honest message had to be the neutral one.
      case LintcruxAction.switchProject:
        unawaited(_handleOpener(action, switchProjectOpenerProvider));
      case LintcruxAction.reopenRecentProject:
        unawaited(_handleOpener(action, reopenRecentProjectOpenerProvider));
      case LintcruxAction.pinActiveProject:
        unawaited(_handleOpener(action, pinActiveProjectOpenerProvider));
      case LintcruxAction.closeAllProjects:
        unawaited(_handleOpener(action, closeAllProjectsOpenerProvider));
      case LintcruxAction.closeAllTabs:
        unawaited(_handleCloseAllTabs());
    }
  }

  /// Records one telemetry counter from the event catalog.
  ///
  /// A thin wrapper so the dispatch handlers below read as one line each. The
  /// event name stays a single-quoted literal at every call site: the catalog
  /// conformance test finds recorded events by scanning for exactly that, and
  /// a shared constant would make its "every recorded name is in the catalog"
  /// rule vacuous.
  ///
  /// Every caller records after an await — a picker, a write, a project open —
  /// and the app can be torn down inside that gap. `ref` throws once this
  /// state is unmounted, so an event whose tree is gone is dropped here rather
  /// than thrown out of an unawaited handler.
  void _record(String name, [Map<String, Object?>? properties]) {
    if (!mounted) return;
    ref
        .read(telemetryServiceProvider)
        .record(TelemetryEvent(name, properties: properties));
  }

  /// Resolves [opener] from the active context and runs it.
  ///
  /// A null opener means no implementation is installed in this build —
  /// the open-core case for every Pro seam. Rather than returning
  /// silently (which renders the menu / palette entry a dead item), the
  /// user gets localized feedback chosen by [action]'s `requiredTier`,
  /// so the snack can never contradict the tier badge the surface
  /// rendered next to the entry: a Pro/Enterprise action says "requires
  /// LintCrux Pro", an open-core action says "not available yet".
  Future<void> _handleOpener(
    LintcruxAction action,
    Provider<ProActionOpener?> opener,
  ) async {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    final resolved = ref.read(opener);
    if (resolved == null) {
      _snackOpenerMissing(ctx, action);
      return;
    }
    await resolved(ctx);
  }

  /// Feedback for an action whose opener seam is unpopulated. Routes to
  /// the Pro-upsell snack or the neutral "not available yet" snack based
  /// on the action's declared tier.
  void _snackOpenerMissing(BuildContext? context, LintcruxAction action) {
    if (context == null || !context.mounted) return;
    final label = action.label(L10N.of(context));
    if (action.requiredTier == LicenseTier.openCore) {
      _snackUnimplemented(context, (_) => label);
    } else {
      _snackProGated(context, (_) => label);
    }
  }

  Future<void> _handleOpenTabDiagnostics() async {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    if (!_diagnosticsAvailable(ctx)) return;
    // Non-modal WaveCrux-style overlay drawer (suite UI-consistency
    // pass) — the chrome outside the drawer stays interactive.
    await TabDiagnosticsDrawer.open(ctx);
  }

  Future<void> _handleOpenAppDiagnostics() async {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    if (!_diagnosticsAvailable(ctx)) return;
    await AppDiagnosticsDialog.show(ctx);
  }

  /// The release-build diagnostics gate, checked by both diagnostics entry
  /// points. When it is closed the user is told where the switch is, rather
  /// than getting a menu command that does nothing.
  bool _diagnosticsAvailable(BuildContext ctx) {
    if (ref.read(diagnosticsEnabledProvider)) return true;
    final l10n = L10N.of(ctx);
    showCruxInfoSnack(
      ctx,
      l10n.diagnosticsDisabledSnack(l10n.settingsGeneralSection),
    );
    return false;
  }

  /// Drives the four `LintcruxAction.exportX` handlers through one
  /// path: pull the active tab's visible violations, encode in the
  /// requested format via [ViolationExporters], pick a destination,
  /// write the file. Open-core feature — no Pro override required.
  Future<void> _handleExport(ExportFormat format) async {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    final active = _activeTabContainer();
    if (active == null) {
      showCruxInfoSnack(ctx, L10N.of(ctx).runEnginesNoActiveProject);
      return;
    }
    final violations = active.container.read(visibleViolationsProvider);
    const exporter = ViolationExporters();
    final (String content, String ext, String label) = switch (format) {
      ExportFormat.sarif => (exporter.toSarif(violations), 'sarif', 'SARIF'),
      ExportFormat.json => (exporter.toJson(violations), 'json', 'JSON'),
      ExportFormat.csv => (exporter.toCsv(violations), 'csv', 'CSV'),
      ExportFormat.html => (exporter.toHtml(violations), 'html', 'HTML'),
    };
    final picker = ref.read(projectPickerProvider);
    String? path;
    try {
      path = await picker.pickSaveExportFile(
        confirmButtonText: L10N.of(ctx).filePickerExportButton,
        extension: ext,
        label: label,
      );
    } on Object catch (e) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, L10N.of(ctx).filePickerFailed('$e'));
      return;
    }
    if (path == null) return;
    try {
      await File(path).writeAsString(content);
    } on Object catch (e) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, L10N.of(ctx).exportFailed('$e'));
      return;
    }
    // Past the cancelled-picker and failed-write returns, so the counter means
    // "an artifact exists on disk" rather than "a menu item was clicked".
    // The violation count is deliberately NOT a property: it is a measure of
    // the user's design, not of their use of LintCrux.
    _record('export.completed', <String, Object?>{
      'format': telemetryEnumToken(format),
    });
    if (!ctx.mounted) return;
    showCruxInfoSnack(ctx, L10N.of(ctx).exportSuccess(violations.length, path));
  }

  // ── Helper handlers added by the menu/palette/shortcut wiring ───

  Future<void> _handleCloseTab() async {
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null) return;
    final activeTabId = workspace.activeTabId;
    if (activeTabId == null) return;
    await ref.read(workspaceProvider.notifier).closeTab(activeTabId);
  }

  /// Empties the workspace behind a single confirmation dialog, per the
  /// [LintcruxAction.resetWorkspace] / [LintcruxAction.newWorkspace]
  /// contract. Both actions perform the same destructive operation —
  /// closing every open tab — and share one confirmation.
  ///
  /// Dismissing the dialog, or activating with no navigator mounted,
  /// leaves the workspace untouched.
  ///
  /// Returns whether the reset actually happened. The `newWorkspace` case
  /// needs that answer: it records the `workspace.created` counter on
  /// top of the `workspace.reset` the notifier emits, and a dismissed dialog
  /// created nothing.
  Future<bool> _handleResetWorkspace() async {
    final confirmed = await _confirmDestructiveWorkspaceAction(
      dialogKey: 'workspaceResetConfirmDialog',
      cancelKey: 'workspaceResetConfirmCancel',
      confirmKey: 'workspaceResetConfirmAction',
      title: (l10n) => l10n.workspaceResetConfirmTitle,
      body: (l10n) => l10n.workspaceResetConfirmBody,
      confirmLabel: (l10n) => l10n.workspaceResetConfirmAction,
    );
    if (!confirmed) return false;
    await ref.read(workspaceProvider.notifier).resetWorkspace();
    return true;
  }

  /// File → Close All Tabs — confirms, then closes every open workspace
  /// tab through the per-tab close path.
  ///
  /// The open-core tab-closing capability: no project registry, no
  /// pinning, no recents. Unlike [_handleResetWorkspace] this preserves
  /// the workspace `extras` map (panel visibility and other ambient
  /// layout flags), so the user's layout survives. The action is
  /// destructive and reachable from the menu bar and command palette,
  /// so it confirms first.
  Future<void> _handleCloseAllTabs() async {
    // Nothing to close — don't prompt a destructive confirmation over an
    // empty workspace. Checked before the dialog so an empty workspace is
    // a silent no-op rather than a confirm-then-close-nothing.
    final current = ref.read(workspaceProvider).value;
    if (current == null || current.tabs.isEmpty) return;
    final confirmed = await _confirmDestructiveWorkspaceAction(
      dialogKey: 'closeAllTabsConfirmDialog',
      cancelKey: 'closeAllTabsConfirmCancel',
      confirmKey: 'closeAllTabsConfirmAction',
      title: (l10n) => l10n.closeAllTabsConfirmTitle,
      body: (l10n) => l10n.closeAllTabsConfirmBody,
      confirmLabel: (l10n) => l10n.closeAllTabsConfirmConfirm,
    );
    if (!confirmed) return;
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null) return;
    final notifier = ref.read(workspaceProvider.notifier);
    for (final tab in workspace.tabs) {
      await notifier.closeTab(tab.id);
    }
  }

  /// Mounts a two-button confirmation dialog for a destructive
  /// workspace action and reports whether the user confirmed.
  ///
  /// Returns `false` when the dialog is dismissed, when the confirm
  /// button is not pressed, or when no navigator is mounted — in every
  /// one of those cases the caller must leave the workspace untouched.
  Future<bool> _confirmDestructiveWorkspaceAction({
    required String dialogKey,
    required String cancelKey,
    required String confirmKey,
    required String Function(L10N l10n) title,
    required String Function(L10N l10n) body,
    required String Function(L10N l10n) confirmLabel,
  }) async {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return false;
    final l10n = L10N.of(ctx);
    // The suite-standard destructive confirm (error-colored, verb-labeled)
    // — this was previously a hand-rolled dialog with a plain FilledButton.
    return await confirmCruxDestructiveAction(
      ctx,
      title: title(l10n),
      body: body(l10n),
      confirmLabel: confirmLabel(l10n),
      cancelLabel: l10n.dialogCancel,
      dialogKey: Key(dialogKey),
      cancelKey: Key(cancelKey),
      confirmKey: Key(confirmKey),
    );
  }

  Future<void> _handleOpenSession() async {
    final picker = ref.read(projectPickerProvider);
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    if (ctx == null || !ctx.mounted) return;
    final l10n = L10N.of(ctx);
    final path = await picker.pickSessionFile(
      confirmButtonText: l10n.filePickerOpenSessionButton,
      typeLabel: l10n.filePickerTypeSessionLabel,
    );
    if (path == null) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(tabsForId);
    // The welcome screen's Open Session reports a failure; this one, reached
    // from the menu, the palette and the shortcut, dropped it.
    final result = await opener.openSession(path);
    if (ctx.mounted) showOpenProjectOutcome(ctx, result);
  }

  Future<void> _handleOpenWorkspace() async {
    final picker = ref.read(projectPickerProvider);
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    if (ctx == null || !ctx.mounted) return;
    final l10n = L10N.of(ctx);
    final path = await picker.pickWorkspaceFile(
      confirmButtonText: l10n.filePickerOpenWorkspaceButton,
      typeLabel: l10n.filePickerTypeWorkspaceLabel,
    );
    if (path == null) return;
    final opener = ref.read(openProjectInWorkspaceProvider)(tabsForId);
    // As the welcome screen's Open Workspace does: a corrupt or newer-version
    // workspace document otherwise did nothing, with no word why.
    final error = await opener.openWorkspace(path);
    if (error != null && ctx.mounted) {
      showCruxErrorSnack(ctx, l10n.workspaceLoadFailed(error));
    }
  }

  Future<void> _handleNewProjectGlobal() async {
    final picker = ref.read(projectPickerProvider);
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    if (ctx == null || !ctx.mounted) return;
    final l10n = L10N.of(ctx);
    final String? path;
    try {
      path = await picker.pickSaveProjectFile(
        confirmButtonText: l10n.filePickerCreateProjectButton,
        typeLabel: l10n.filePickerTypeProjectLabel,
      );
    } on Object catch (error) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, l10n.filePickerFailed('$error'));
      return;
    }
    if (path == null) return;
    final normalizedPath = path.endsWith('.lintcrux') ? path : '$path.lintcrux';
    final project = LintProject(
      name: p.basenameWithoutExtension(normalizedPath),
      rootPath: p.dirname(normalizedPath),
    );
    const service = ProjectFileService();
    try {
      await service.write(normalizedPath, project);
    } on ProjectFileException catch (e) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, e.message);
      return;
    }
    final opener = ref.read(openProjectInWorkspaceProvider)(tabsForId);
    await opener.openProject(normalizedPath);
  }

  Future<void> _handleSaveWorkspaceAs() async {
    final picker = ref.read(projectPickerProvider);
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    if (ctx == null || !ctx.mounted) return;
    final l10n = L10N.of(ctx);
    final String? path;
    try {
      path = await picker.pickSaveWorkspaceFile(
        confirmButtonText: l10n.filePickerSaveWorkspaceButton,
        typeLabel: l10n.filePickerTypeWorkspaceLabel,
      );
    } on Object catch (error) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, l10n.filePickerFailed('$error'));
      return;
    }
    if (path == null) return;
    final normalizedPath = path.endsWith('.lintcrux-workspace')
        ? path
        : '$path.lintcrux-workspace';
    try {
      await ref.read(workspaceProvider.notifier).saveAs(normalizedPath);
    } on Object catch (e) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, l10n.saveWorkspaceFailed('$e'));
      return;
    }
    if (!ctx.mounted) return;
    showCruxInfoSnack(ctx, l10n.workspaceSaved(normalizedPath));
  }

  Future<void> _handleExportTabAsSession() async {
    final picker = ref.read(projectPickerProvider);
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    if (ctx == null || !ctx.mounted) return;
    final l10n = L10N.of(ctx);
    final workspace = ref.read(workspaceProvider).value;
    final activeTabId = workspace?.activeTabId;
    final activeTab = (workspace == null || activeTabId == null)
        ? null
        : workspace.tabs.where((t) => t.id == activeTabId).firstOrNull;
    if (activeTab == null) {
      showCruxInfoSnack(ctx, l10n.exportSessionNoActiveTab);
      return;
    }
    final payload = activeTab.payload;
    final tabContainer = tabsForId(activeTab.id);
    final tableState = tabContainer.read(violationTableStateProvider);
    final session = LintcruxSession(
      projectPath: payload.projectPath,
      selectedRuleId: payload.selectedRuleId,
      activeSeverities: tableState.severities,
      activeEngineIds: tableState.engineIds,
      ruleSubstring: tableState.ruleSubstring,
      fileGlob: tableState.fileGlob,
      sortColumn: tableState.sortColumn,
      sortAscending: tableState.sortAscending,
      savedFilterPresetName: payload.savedFilterPresetName,
      viewMode: payload.viewMode,
    );
    final String? path;
    try {
      path = await picker.pickExportSessionFile(
        confirmButtonText: l10n.filePickerExportSessionButton,
        typeLabel: l10n.filePickerTypeSessionLabel,
        defaultFileName:
            '${p.basenameWithoutExtension(payload.projectPath)}'
            '.lintcrux-session',
      );
    } on Object catch (error) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, l10n.filePickerFailed('$error'));
      return;
    }
    if (path == null) return;
    final normalizedPath = path.endsWith('.lintcrux-session')
        ? path
        : '$path.lintcrux-session';
    const service = SessionService();
    try {
      await service.save(normalizedPath, session);
    } on Object catch (e) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, l10n.saveSessionFailed('$e'));
      return;
    }
    if (!ctx.mounted) return;
    showCruxInfoSnack(ctx, l10n.sessionSaved(normalizedPath));
  }

  Future<void> _handleOpenSources() async {
    final picker = ref.read(projectPickerProvider);
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    if (ctx == null || !ctx.mounted) return;
    final l10n = L10N.of(ctx);
    final workspace = ref.read(workspaceProvider).value;
    final activeTabId = workspace?.activeTabId;
    final activeTab = (workspace == null || activeTabId == null)
        ? null
        : workspace.tabs.where((t) => t.id == activeTabId).firstOrNull;
    if (activeTab == null) {
      showCruxInfoSnack(ctx, l10n.openSourcesNoActiveProject);
      return;
    }
    final tabContainer = tabsForId(activeTab.id);
    final currentProject = tabContainer.read(currentProjectProvider);
    if (currentProject == null) {
      showCruxInfoSnack(ctx, l10n.openSourcesNoActiveProject);
      return;
    }
    final List<String> picked;
    try {
      picked = await picker.pickSourceFiles(
        confirmButtonText: l10n.filePickerOpenSourcesButton,
        typeLabel: l10n.filePickerTypeSourcesLabel,
      );
    } on Object catch (error) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, l10n.filePickerFailed('$error'));
      return;
    }
    if (picked.isEmpty) return;
    if (!ctx.mounted) return;
    await _addSourcesToActiveProject(ctx, picked);
  }

  /// Appends [picked] source files to the active tab's project, rewrites
  /// its `.lintcrux`, and re-runs the engines. Reached from File > Open
  /// Source Files after the picker, and from a source file macOS opened the
  /// app with. Without an active project it says one is needed.
  Future<void> _addSourcesToActiveProject(
    BuildContext ctx,
    List<String> picked,
  ) async {
    final l10n = L10N.of(ctx);
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final workspace = ref.read(workspaceProvider).value;
    final activeTabId = workspace?.activeTabId;
    final activeTab = (workspace == null || activeTabId == null)
        ? null
        : workspace.tabs.where((t) => t.id == activeTabId).firstOrNull;
    if (activeTab == null) {
      showCruxInfoSnack(ctx, l10n.openSourcesNoActiveProject);
      return;
    }
    final tabContainer = tabsForId(activeTab.id);
    if (tabContainer.read(currentProjectProvider) == null) {
      showCruxInfoSnack(ctx, l10n.openSourcesNoActiveProject);
      return;
    }
    // `currentProject` is the run/engine-facing form with paths already
    // resolved to absolute. Persist against the AUTHORED (relative) form on
    // disk so a committed `.lintcrux` keeps its portable relative rootPath
    // and sources — re-read the file to recover what was authored, append
    // the picked sources *relative to the project directory*, and write that
    // back. The tab then loads and runs the absolute-resolved form.
    final projectPath = activeTab.payload.projectPath;
    final projectDir = p.dirname(projectPath);
    const service = ProjectFileService();
    final LintProject authored;
    try {
      authored = await service.read(projectPath);
    } on ProjectFileException catch (e) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, e.message);
      return;
    }
    final pickedRelative = <String>[
      for (final path in picked) p.relative(path, from: projectDir),
    ];
    final mergedAuthored = <String>[
      ...authored.sourceFiles,
      for (final rel in pickedRelative)
        if (!authored.sourceFiles.contains(rel)) rel,
    ];
    final toWrite = authored.copyWith(sourceFiles: mergedAuthored);
    try {
      await service.write(projectPath, toWrite);
    } on ProjectFileException catch (e) {
      if (!ctx.mounted) return;
      showCruxErrorSnack(ctx, e.message);
      return;
    }
    final resolved = resolveProjectPaths(toWrite, projectDir);
    tabContainer
        .read(currentProjectProvider.notifier)
        .load(resolved, projectFilePath: projectPath);
    unawaited(
      tabContainer.read(lintRunProvider.notifier).runAll(resolved),
    );
    if (!ctx.mounted) return;
    showCruxInfoSnack(ctx, l10n.openSourcesAdded(picked.length, resolved.name));
  }

  /// Desktop "Import SARIF report" dispatch. Delegates to the
  /// shared [runSarifImportFlow] (pick → load → navigate to the
  /// read-only imported-report viewer) so the toolbar, welcome screen,
  /// File menu, and command palette all reach the one implementation.
  Future<void> _handleImportSarif() async {
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    if (ctx == null || !ctx.mounted) return;
    await runSarifImportFlow(ctx, ref);
  }

  Future<void> _handleSplitPaneRight() async {
    await ref.read(workspaceProvider.notifier).splitPaneRight();
  }

  Future<void> _handleClosePane() async {
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null || workspace.panes.length < 2) return;
    await ref
        .read(workspaceProvider.notifier)
        .closePane(workspace.activePaneId);
  }

  Future<void> _handleFocusOtherPane() async {
    await ref.read(workspaceProvider.notifier).focusOtherPane();
  }

  /// Flips between Crux Light and Crux Dark. The active preset decides
  /// brightness, so the stored `AppThemeMode` would change nothing on screen;
  /// see [toggleThemeBrightness].
  void _handleToggleTheme() {
    toggleThemeBrightness(
      ref.read(cruxColorThemeProvider.notifier),
      ref.read(cruxColorThemeProvider),
    );
  }

  /// Runs a manual update check. Never gated on the Settings → General
  /// auto-check toggle — a user who turned automatic checks off can still ask.
  ///
  /// [ModalGuard]-wrapped at this dispatch site (the helper lives in the
  /// shared `crux_updates` package): the flow can surface a modal download
  /// dialog, and a repeated gesture must not run two overlapping checks.
  Future<void> _handleCheckForUpdates() async {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    await ModalGuard.run(
      'checkForUpdates',
      () => runManualUpdateCheck(ctx, ref),
    );
  }

  /// Opens the beta issue reporter over the active tab's scope.
  Future<void> _handleSubmitIssue() async {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    await LintcruxIssueReporter.open(ctx);
  }

  void _handleOpenAbout() {
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    unawaited(LintcruxAboutDialog.openAdaptive(ctx, ref));
  }

  void _snackProGated(BuildContext? context, String Function(L10N) feature) {
    if (context == null || !context.mounted) return;
    final l10n = L10N.of(context);
    showCruxInfoSnack(context, l10n.snackFeatureRequiresPro(feature(l10n)));
  }

  /// Placeholder feedback for an action whose UI surface hasn't shipped in
  /// **any** tier (distinct from [_snackProGated], which is for Pro-tier
  /// actions whose implementation exists but is withheld from this build).
  ///
  /// Used for an open-core action whose opener seam is unpopulated: no tier
  /// can activate it, so a Pro-upsell message would be false to a paying
  /// user. This snack states honestly that the feature has not arrived.
  void _snackUnimplemented(
    BuildContext? context,
    String Function(L10N) feature,
  ) {
    if (context == null || !context.mounted) return;
    final l10n = L10N.of(context);
    showCruxInfoSnack(context, l10n.snackFeatureNotAvailableYet(feature(l10n)));
  }

  Future<void> _handleOpenSettings(BuildContext context) async {
    // On desktop Settings opens as a modal dialog so the workspace stays
    // visible behind it (standard Cmd+, / Ctrl+, behavior). On mobile it
    // pushes as a full-screen route. [SettingsScreen.openAdaptive]
    // encapsulates the platform branch.
    await SettingsScreen.openAdaptive(context);
  }

  /// Resolves the active tab's `(tabId, container)` pair, or null when
  /// no tab is active or the workspace root hasn't mounted yet.
  ({crux.TabId id, ProviderContainer container})? _activeTabContainer() {
    final workspace = ref.read(workspaceProvider).value;
    final activeTabId = workspace?.activeTabId;
    if (workspace == null || activeTabId == null) return null;
    final activeTab = workspace.tabs
        .where((t) => t.id == activeTabId)
        .firstOrNull;
    if (activeTab == null) return null;
    final tabsForId = _tabsForId();
    if (tabsForId == null) return null;
    return (id: activeTab.id, container: tabsForId(activeTab.id));
  }

  Future<void> _handleRunAllEngines() async {
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    final l10n = (ctx != null && ctx.mounted) ? L10N.of(ctx) : null;
    final active = _activeTabContainer();
    if (active == null) {
      if (ctx != null && l10n != null) {
        showCruxInfoSnack(ctx, l10n.runEnginesNoActiveProject);
      }
      return;
    }
    final project = active.container.read(currentProjectProvider);
    if (project == null) {
      if (ctx != null && l10n != null) {
        showCruxInfoSnack(ctx, l10n.runEnginesNoActiveProject);
      }
      return;
    }
    final runner = active.container.read(lintRunProvider.notifier);
    if (active.container.read(lintRunProvider).isRunning) {
      if (ctx != null && l10n != null) {
        showCruxInfoSnack(ctx, l10n.runEnginesAlreadyRunning);
      }
      return;
    }
    await runner.runAll(project);
  }

  void _handleCancelRun() {
    final ctx = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentState
        ?.context;
    final l10n = (ctx != null && ctx.mounted) ? L10N.of(ctx) : null;
    final active = _activeTabContainer();
    if (active == null || !active.container.read(lintRunProvider).isRunning) {
      if (ctx != null && l10n != null) {
        showCruxInfoSnack(ctx, l10n.cancelRunNoActiveRun);
      }
      return;
    }
    active.container.read(lintRunProvider.notifier).cancel();
  }

  /// Opens the Find-in-Violations search dialog over the active tab's
  /// violation store (substring / glob / regex over rule id + message;
  /// picking a result selects the violation). The inline filter chip in
  /// the violations panel stays available for quick rule-id filtering;
  /// this is the richer modal find surface. Cmd/Ctrl+F.
  ///
  /// In the browser viewer it searches the loaded report instead: there is no
  /// workspace there, so the active-tab check below would always come back
  /// empty and the shortcut would silently do nothing.
  void _handleFindInViolations() {
    final router = ref.read(appRouterProvider);
    if (isWebMode) {
      // The SARIF loader fills the root scope's violation store, which is
      // what the viewer screen renders. Only that screen has a report on it;
      // on the landing screen there is nothing to search — the same silent
      // no-op as an empty desktop workspace.
      if (router.state.name != kWebViewerRouteName) return;
      final ctx = router.routerDelegate.navigatorKey.currentState?.context;
      if (ctx == null || !ctx.mounted) return;
      unawaited(showViolationSearchDialog(ctx, activeTab: false));
      return;
    }
    // Nothing to search with no project open — silent no-op, matching the
    // other empty-workspace actions.
    if (_activeTabContainer() == null) return;
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    unawaited(showViolationSearchDialog(ctx));
  }

  Future<void> _handleImportFilelist() async {
    final picker = ref.read(projectPickerProvider);
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final filelistPath = await picker.pickFilelistFile(
      confirmButtonText: L10N.of(ctx).filePickerImportFilelistButton,
      typeLabel: L10N.of(ctx).filePickerTypeFilelistLabel,
    );
    if (filelistPath == null) return;
    await _importFilelist(filelistPath, tabsForId);
  }

  /// Turns the Vivado filelist at [filelistPath] into a project and opens
  /// it. Reached from File > Import Vivado Filelist after the picker, and from a
  /// filelist macOS opened the app with.
  Future<void> _importFilelist(
    String filelistPath,
    ProviderContainer Function(crux.TabId) tabsForId,
  ) async {
    final router = ref.read(appRouterProvider);
    try {
      const service = FilelistImportService();
      final result = service.importFilelist(filelistPath: filelistPath);
      // Open the generated `.lintcrux` through the workspace opener —
      // the same seam as File → Open — so the project lands in a new
      // tab's per-tab providers (where the per-project stores live)
      // rather than the root container.
      final opener = ref.read(openProjectInWorkspaceProvider)(tabsForId);
      final open = await opener.openProject(result.projectFilePath);
      if (open is OpenProjectSuccess) {
        _record('project.opened', <String, Object?>{
          'source': telemetryEnumToken(ProjectOpenSource.filelist),
        });
        router.go('/viewer');
      }
    } on FilelistImportException catch (e) {
      // Surface the error via the router's current navigator if any —
      // fall back to stderr in headless contexts (tests).
      final navigator = router.routerDelegate.navigatorKey.currentState;
      final ctx = navigator?.context;
      if (ctx != null && ctx.mounted) {
        final l10n = L10N.of(ctx);
        showCruxErrorSnack(ctx, l10n.filelistImportError(e.message));
      } else {
        stderr.writeln('lintcrux: filelist import failed: ${e.message}');
      }
    }
  }

  Future<void> _handleImportEdam() async {
    final picker = ref.read(projectPickerProvider);
    final router = ref.read(appRouterProvider);
    final ctx = router.routerDelegate.navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) return;
    final tabsForId = _tabsForId();
    if (tabsForId == null) return;
    final edamPath = await picker.pickEdamFile(
      confirmButtonText: L10N.of(ctx).filePickerImportEdamButton,
      typeLabel: L10N.of(ctx).filePickerTypeEdamLabel,
    );
    if (edamPath == null) return;
    try {
      const service = EdamImportService();
      final result = service.importEdam(edamPath: edamPath);
      // The reader's non-fatal warnings (skipped file types, ignored
      // tool options, version drift) go to stdout — the GUI has no
      // diagnostics surface for import advisories yet, and swallowing
      // them silently would hide exactly the information a FuseSoC
      // user needs when a file did not make it across.
      for (final warning in result.warnings) {
        stdout.writeln('lintcrux: warning: $warning');
      }
      // Same seam as the filelist import: open the generated
      // `.lintcrux` through the workspace opener so the project lands
      // in a new tab's per-tab providers.
      final opener = ref.read(openProjectInWorkspaceProvider)(tabsForId);
      final open = await opener.openProject(result.projectFilePath);
      if (open is OpenProjectSuccess) {
        _record('project.opened', <String, Object?>{
          'source': telemetryEnumToken(ProjectOpenSource.edam),
        });
        router.go('/viewer');
      }
    } on EdamImportException catch (e) {
      final navigator = router.routerDelegate.navigatorKey.currentState;
      final ctx = navigator?.context;
      if (ctx != null && ctx.mounted) {
        final l10n = L10N.of(ctx);
        showCruxErrorSnack(ctx, l10n.edamImportError(e.message));
      } else {
        stderr.writeln('lintcrux: EDAM import failed: ${e.message}');
      }
    }
  }

  /// Toggles the docked cross-probe side-panel (retiring the old modal dialog).
  /// Drives the same `crossProbeVisible` flag the toolbar toggle button reads,
  /// so the menu bar, command palette, ⌘/Ctrl+Shift+X shortcut, and toolbar
  /// button all show/hide the one docked panel.
  void _handleOpenCrossProbePanel() {
    // The CXP panel is a right-dock tab now. Toggle the feature; turning it
    // on reveals its tab (opening the right region if hidden).
    final willShow = !ref.read(panelLayoutProvider).crossProbeVisible;
    ref.read(panelLayoutProvider.notifier).toggleCrossProbe();
    if (willShow) {
      ref.read(rightDockTabProvider.notifier).reveal(kRightDockTabCrossProbe);
    }
  }

  /// Cycles the active tab within the active pane by [delta]
  /// positions (negative for previous, positive for next). Wraps at
  /// the ends. No-op when the active pane holds fewer than two tabs.
  Future<void> _handleSwitchTabBy(int delta) async {
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null) return;
    final activePane = workspace.activePaneId;
    final paneTabs = workspace.tabsForPane(activePane);
    if (paneTabs.length < 2) return;
    final activeTabId = workspace.activeTabId;
    final currentIdx = activeTabId == null
        ? -1
        : paneTabs.indexWhere((t) => t.id == activeTabId);
    if (currentIdx < 0) {
      await ref
          .read(workspaceProvider.notifier)
          .setActiveTab(paneTabs.first.id);
      return;
    }
    final nextIdx = (currentIdx + delta) % paneTabs.length;
    final wrappedIdx = nextIdx < 0 ? nextIdx + paneTabs.length : nextIdx;
    await ref
        .read(workspaceProvider.notifier)
        .setActiveTab(paneTabs[wrappedIdx].id);
  }

  /// Moves the active tab to the other pane, splitting first if the
  /// workspace currently has only one pane.
  Future<void> _handleMoveTabToOtherPane() async {
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null) return;
    final activeTabId = workspace.activeTabId;
    if (activeTabId == null) return;
    final notifier = ref.read(workspaceProvider.notifier);
    final crux.PaneId target;
    if (workspace.panes.length < 2) {
      target = await notifier.splitPaneRight();
    } else {
      final activePane = workspace.activePaneId;
      target = workspace.panes
          .firstWhere(
            (p) => p.id != activePane,
            orElse: () => workspace.panes.first,
          )
          .id;
    }
    await notifier.moveTabToPane(activeTabId, target);
  }
}

/// Holds a live subscription to every provider named by
/// [eagerStartupProvidersProvider], realizing overlay-contributed
/// side-effecting providers (e.g. the Pro trend-store ingestion
/// listener) and keeping them alive for the whole app session.
///
/// The subscriptions are taken against the ROOT [ProviderContainer], not
/// through this widget's `ref`. Two reasons:
///
///   * A one-shot `read` is not enough. Riverpod disposes a provider
///     with no listener, so a `read`-realized listener can be torn down
///     again — dropping the `ref.listen` it installed in its constructor
///     — and the side effect then depends on some other widget happening
///     to watch the same provider. Trend ingestion silently stopping is
///     exactly that failure.
///   * Container-owned subscriptions are unaffected by widget lifecycle:
///     route changes, `deactivate`, and rebuild churn cannot pause them.
///
/// The hook list itself is `watch`ed, so a test (or a future runtime
/// re-registration) that swaps the list re-syncs the subscription set;
/// in production the override is applied once at boot and the list is
/// constant.
class _EagerStartupGate extends ConsumerStatefulWidget {
  const _EagerStartupGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_EagerStartupGate> createState() => _EagerStartupGateState();
}

class _EagerStartupGateState extends ConsumerState<_EagerStartupGate> {
  /// Live keep-alive subscriptions, one per entry of the hook list.
  final List<ProviderSubscription<Object?>> _subscriptions =
      <ProviderSubscription<Object?>>[];

  /// One-shot, because the report describes this launch's policy load.
  bool _policyReported = false;

  /// The hook list the current [_subscriptions] were built from, so a
  /// rebuild with an unchanged list is a no-op.
  List<EagerStartupHook>? _boundHooks;

  bool _sameAsBound(List<EagerStartupHook> hooks) {
    final bound = _boundHooks;
    if (bound == null || bound.length != hooks.length) return false;
    for (var i = 0; i < bound.length; i++) {
      if (!identical(bound[i], hooks[i])) return false;
    }
    return true;
  }

  void _bind(List<EagerStartupHook> hooks) {
    if (_sameAsBound(hooks)) return;
    for (final sub in _subscriptions) {
      sub.close();
    }
    _subscriptions.clear();
    final container = ProviderScope.containerOf(context, listen: false);
    for (final hook in hooks) {
      // The callback body is intentionally empty: the subscription
      // exists for its keep-alive effect, not to observe values.
      _subscriptions.add(container.listen<Object?>(hook, (_, _) {}));
    }
    _boundHooks = List<EagerStartupHook>.unmodifiable(hooks);
  }

  /// Say which policy file won, or that one was refused
  /// (<https://edacrux.app/policy-reference#failures>). Without this a file
  /// whose signature fails is refused **silently**: from inside a running app
  /// a refused policy and an absent one are indistinguishable, and telling
  /// those two apart is the whole point of the distinction. A refusal means
  /// the administrator's policy is not in force, so saying nothing is
  /// fail-open with no signal.
  ///
  /// The two halves land in different places and `reportPolicyLoad` decides
  /// which — a refusal CANNOT reach the audit sink, because the sink's path
  /// comes from `suite.audit.path`, which comes from the file that was just
  /// refused. See `crux_license`'s `PolicyReportDestination`.
  ///
  /// **Here rather than in `runLintcrux`**, unlike WaveCrux/NetCrux/SimCrux:
  /// LintCrux hands `ProviderScope` its overrides and never owns a container
  /// before `runApp`, so there is nothing to `read` at that point. This gate
  /// is the first place inside the scope that already holds a `ref` for
  /// startup work, and a one-shot `read` is the right shape for a side effect
  /// that describes a load which has already happened.
  ///
  /// Open core rather than the Pro overlay: the policy file is honoured at
  /// every tier for the day-one keys, so an open-core seat pointed at a bad
  /// file has to be told too.
  void _reportPolicyOnce() {
    if (_policyReported) return;
    _policyReported = true;
    reportPolicyLoad(
      result: ref.read(cruxPolicyProvider),
      // Names any key the administrator set that this build does not act on.
      productId: LintCruxPolicyKeys.productId,
      recorder: ref.read(cruxAuditRecorderProvider),
    );
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.close();
    }
    _subscriptions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bind(ref.watch(eagerStartupProvidersProvider));
    _reportPolicyOnce();
    return widget.child;
  }
}
