// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show ProcessInfo;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/diagnostics/diagnostics_report.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/features/engine_config/providers/engine_versions_provider.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/engine_binary_ids.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// Whether the build mode alone turns the diagnostics surfaces on: true in
/// debug and profile builds, false in release.
///
/// A provider rather than a bare `kReleaseMode` check so a test, which
/// always runs in debug mode, can take the release path.
final Provider<bool> diagnosticsForcedByBuildModeProvider = Provider<bool>(
  (_) => !kReleaseMode,
  name: 'diagnosticsForcedByBuildModeProvider',
);

/// Whether the Tab Diagnostics drawer and the App Diagnostics dialog are
/// available.
///
/// Always in debug and profile builds, where someone is investigating the
/// app itself. In a release build, only once the user turns on Settings >
/// General > Enable diagnostics, which is off by default: the same
/// release-build opt-in NetCrux, SimCrux and WaveCrux have.
///
/// Read by both entry points (the Tools menu, the command palette and any
/// shortcut all dispatch through them) and by both surfaces, which close
/// themselves if the setting is turned off while they are open.
final Provider<bool> diagnosticsEnabledProvider = Provider<bool>((ref) {
  if (ref.watch(diagnosticsForcedByBuildModeProvider)) return true;
  return ref.watch(appSettingsProvider.select((s) => s.diagnosticsEnabled));
}, name: 'diagnosticsEnabledProvider');

/// Reads the process's resident set size in bytes, or `null` where the
/// platform cannot report it.
typedef ResidentMemoryReader = int? Function();

int? _readResidentMemory() {
  if (kIsWeb) return null;
  try {
    final rss = ProcessInfo.currentRss;
    return rss > 0 ? rss : null;
  } on Object {
    return null;
  }
}

/// The resident-memory reader the App Diagnostics report uses. Overridable
/// so a test can supply a known figure.
final Provider<ResidentMemoryReader> residentMemoryReaderProvider =
    Provider<ResidentMemoryReader>(
      (_) => _readResidentMemory,
      name: 'residentMemoryReaderProvider',
    );

/// Where [engineId]'s executable comes from under [config], for the
/// diagnostics report.
///
/// Follows the resolution every engine applies at spawn time: a Custom path
/// wins; Bundled asks [resolver] for a shipped binary and falls back to a
/// `PATH` lookup when there is none; Auto-detect is a `PATH` lookup. The
/// CDC engine runs Yosys, so it is resolved under the Yosys binary id.
String describeEngineBinary(
  String engineId,
  EngineBinaryConfig config, {
  BundledBinaryResolver resolver = const BundledBinaryResolver(),
}) {
  switch (config.source) {
    case EngineBinarySource.custom:
      final path = config.path;
      return (path == null || path.isEmpty) ? 'PATH' : 'custom: $path';
    case EngineBinarySource.bundled:
      final bundled = resolver.resolve(binaryEngineIdFor(engineId));
      return bundled == null
          ? 'PATH (no bundled binary found)'
          : 'bundled: $bundled';
    case EngineBinarySource.system:
      return 'PATH';
  }
}

/// Builds a [TabDiagnosticsReport] from the live per-tab providers.
/// `null` when no project is loaded.
///
/// Top-level so `lintcruxTabOverridesFactory` can re-bind the provider
/// per tab with the identical body — the report must read the tab's own
/// `currentProjectProvider` / `lintRunProvider` / `violationStoreProvider`
/// instances, not the empty root-scope ones.
///
/// Every engine line is measured or absent:
///
/// - **binary** comes from the user's Settings > Engines choice, resolved
///   the way the engine resolves it ([describeEngineBinary]);
/// - **version** is what `engineVersionsProvider`'s probe got back from the
///   binary, or [kEngineNotDetected] when the probe got nothing. Watching
///   the probe starts it; the drawer fills the line in when it resolves;
/// - **duration** only for an engine that started in this tab.
///
/// In the browser no engine runs, so there is neither a binary nor a
/// version to report.
TabDiagnosticsReport? buildTabDiagnosticsReport(Ref ref) {
  final project = ref.watch(currentProjectProvider);
  if (project == null) return null;
  final registry = ref.watch(engineRegistryProvider);
  final runState = ref.watch(lintRunProvider);
  final store = ref.watch(violationStoreProvider);
  final enginesRun = ref.watch(engineVersionProbingSupportedProvider);
  final settings = enginesRun ? ref.watch(appSettingsProvider) : null;
  final versions = enginesRun ? ref.watch(engineVersionsProvider).value : null;

  final engines = <EngineDiagnostics>[];
  int? maxWallMs;
  for (final id in registry.engineIds) {
    int? durationMs;
    final status = runState.statusFor(id);
    final startedAt = status?.startedAt;
    if (startedAt != null) {
      final endedAt = status!.completedAt ?? DateTime.now();
      durationMs = endedAt.difference(startedAt).inMilliseconds;
      if (maxWallMs == null || durationMs > maxWallMs) maxWallMs = durationMs;
    }
    final counts = <Severity, int>{};
    for (final v in store.byEngineOf(id)) {
      counts[v.severity] = (counts[v.severity] ?? 0) + 1;
    }
    engines.add(
      EngineDiagnostics(
        engineId: id,
        binary: settings == null
            ? null
            : describeEngineBinary(
                id,
                settings
                    .engineBinaryOverrideFor(binaryEngineIdFor(id))
                    .toEngineBinaryConfig(),
              ),
        version: versions == null ? null : (versions[id] ?? kEngineNotDetected),
        durationMs: durationMs,
        severityCounts: Map<Severity, int>.unmodifiable(counts),
      ),
    );
  }

  return TabDiagnosticsReport(
    projectPath: project.rootPath,
    sourceFileCount: project.sourceFiles.length,
    lastRunWallMs: maxWallMs,
    engines: List<EngineDiagnostics>.unmodifiable(engines),
  );
}

/// Builds a [TabDiagnosticsReport] from the live providers backing the
/// active tab.
///
/// Per-tab: re-bound in `lintcruxTabOverridesFactory` (with the same
/// [buildTabDiagnosticsReport] body) so the report reflects the tab the
/// diagnostics drawer was opened over. The drawer itself is mounted
/// inside the active tab's scope (`wrapInActiveTabScope`), so its
/// `ref.watch` resolves the per-tab instance.
final Provider<TabDiagnosticsReport?> tabDiagnosticsReportProvider =
    Provider<TabDiagnosticsReport?>(buildTabDiagnosticsReport);

/// Builds an [AppDiagnosticsReport].
///
/// Top-level so `lintcruxTabOverridesFactory` can re-bind the provider
/// per tab with the identical body.
///
/// The memory figure is read once, when the report is built. The App
/// Diagnostics dialog invalidates this provider as it opens, so each
/// opening reads it afresh rather than showing the figure from the first
/// time the dialog was opened.
AppDiagnosticsReport buildAppDiagnosticsReport(Ref ref) {
  final store = ref.watch(violationStoreProvider);
  return AppDiagnosticsReport(
    residentMemoryBytes: ref.watch(residentMemoryReaderProvider)(),
    activeTabViolationCount: store.count,
  );
}

/// Builds an [AppDiagnosticsReport] from process-wide state and the active
/// tab.
///
/// The violation count reads `violationStoreProvider`, which is per-tab
/// state — so this provider is re-bound per tab in
/// `lintcruxTabOverridesFactory` and the dialog is mounted inside the
/// active tab's scope. The count therefore reflects the ACTIVE tab's
/// store, and the report says so.
final Provider<AppDiagnosticsReport> appDiagnosticsReportProvider =
    Provider<AppDiagnosticsReport>(buildAppDiagnosticsReport);
