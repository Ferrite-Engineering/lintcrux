// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/features/engine_config/providers/engine_versions_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_view_mode_provider.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/filter_presets/active_filter_preset_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:lintcrux/services/waivers/waiver_store_provider.dart';
import 'package:meta/meta.dart';

/// Builds the privacy-scrubbed Session State snapshot the beta issue reporter
/// attaches to a GitHub issue.
///
/// **THE PRIVACY CONTRACT IS THE POINT OF THIS FILE.** LintCrux's domain is
/// unusually hostile to it: a `Violation` carries `location.file` and a line
/// number natively, a `LintProject` carries `rootPath` and a source-file list,
/// a filter preset carries a user-typed name, and a rule-id filter carries
/// whatever the user typed into the search box. None of that may reach a
/// public issue tracker. What goes in is **counts, engine ids, engine
/// versions and enum names** — nothing else. Every field below is either a
/// number, a fixed enum name, an engine id from the registry, or a version
/// string put through [_versionLabel], which strips any path-shaped token.
///
/// The assertion that this holds lives in
/// `test/features/issue_reporter/providers/issue_session_context_test.dart`,
/// driven from a realistically populated session (a project rooted at a real
/// on-disk path, with violations carrying real file locations). Adding a field
/// here without extending that test is the defect this arrangement exists to
/// prevent.
///
/// Field labels are deliberately English: the issue body is authored for the
/// maintainers reading it in the GitHub repository, and `crux_issue_reporter`
/// documents the body as un-localized for exactly that reason. Only the dialog
/// chrome is localized (see [LintcruxIssueReporterStrings]).
///
/// Bound to `crux_issue_reporter`'s `cruxIssueSessionContextProvider` in
/// `lintcruxPhase5Overrides`, and top-level so `lintcruxTabOverridesFactory`
/// can re-bind that provider per tab with the identical body: the snapshot
/// must read the ACTIVE tab's
/// `currentProjectProvider` / `violationStoreProvider` / table state, not the
/// empty root-scope instances. The reporter is opened inside the active tab's
/// scope for the same reason.
CruxIssueSessionContext buildLintcruxIssueSessionContext(Ref ref) {
  final project = ref.watch(currentProjectProvider);
  final registry = ref.watch(engineRegistryProvider);
  final store = ref.watch(violationStoreProvider);
  final table = ref.watch(violationTableStateProvider);
  final viewMode = ref.watch(violationViewModeProvider);
  final activePreset = ref.watch(activeFilterPresetProvider);
  final waivers = ref.watch(waiverStoreProvider);
  // Already-resolved probe result, or an empty map when nothing warmed it.
  // The reporter's opener awaits `engineVersionsProvider` before showing the
  // dialog, so in practice this is populated; a synchronous read keeps this
  // provider free of any await.
  final versions =
      ref.watch(engineVersionsProvider).value ?? const <String, String>{};

  final bySeverity = store.bySeverity;
  int severityCount(Severity severity) => bySeverity[severity]?.length ?? 0;

  final enabledEngineIds = project == null
      ? const <String>[]
      : (project.enabledEngineIds.isEmpty
            ? registry.engineIds
            : project.enabledEngineIds);

  // Labels and attribute keys below are byte-identical to what this file
  // emitted before it moved onto the shared builder — an issue body is read
  // by a human diffing four products' reports, so the wording is part of the
  // contract. The two placeholders are the exception, and deliberately so:
  // they now come from `CruxIssueFallback`, which is what makes the
  // vocabulary the same in all four products.
  return (CruxIssueSessionContextBuilder()
        ..addFlag(
          'Project loaded',
          value: project != null,
          attributeKey: 'projectLoaded',
        )
        ..addText('Project language', project?.language.name)
        ..addCount('Source files', project?.sourceFiles.length ?? 0)
        ..addList('Engines enabled', _engineSummary(enabledEngineIds, versions))
        ..addCount('Engines registered', registry.length)
        ..addCount(
          'Violations total',
          store.count,
          attributeKey: 'violationCount',
        )
        ..addList('Violations by severity', <String>[
          for (final severity in Severity.values)
            '${severity.name} ${severityCount(severity)}',
        ])
        ..addCount('Distinct rules firing', store.byRule.length)
        ..addCount(
          'Active waivers',
          waivers.all.length,
          attributeKey: 'waiverCount',
        )
        ..addText('Table view mode', viewMode.name)
        ..addFlag('Filter preset active', value: activePreset != null)
        ..addList(
          'Severity filter',
          Severity.values
              .where(table.severities.contains)
              .map((s) => s.name)
              .toList(),
          fallback: CruxIssueFallback.all,
        )
        ..addList(
          'Engine filter',
          registry.engineIds.where(table.engineIds.contains).toList(),
          fallback: CruxIssueFallback.all,
        )
        // Only whether a text filter is set — never the text, which is
        // user-typed and could name a module, a signal or a path.
        ..addFlag('Rule text filter set', value: table.ruleSubstring.isNotEmpty)
        ..addFlag('File glob filter set', value: table.fileGlob.isNotEmpty)
        ..addCount('Selected rows', table.selectedRuleIds.length)
        // Structured extra the Pro overlay's
        // `CruxIssueReporterDataProvider` reads when building its own "Pro
        // State" category; the other three ride along on their fields above.
        // Same privacy rules apply.
        ..attribute('enabledEngineCount', enabledEngineIds.length))
      .build();
}

/// The enabled engines as `id version` entries, using `(not detected)` for an
/// engine whose binary could not be probed.
///
/// Returned as a list rather than a joined string so the builder owns both the
/// `, ` separator and the empty-case placeholder.
List<String> _engineSummary(
  List<String> engineIds,
  Map<String, String> versions,
) => <String>[
  for (final id in engineIds)
    if (versions[id] case final version?)
      '$id ${_versionLabel(version)}'
    else
      '$id (not detected)',
];

/// The engine-reported version string, reduced to something provably free of
/// filesystem paths.
///
/// `<binary> --version` output is normally a single clean line
/// (`Verilator 5.022 2024-07-01 rev v5.022`), but nothing in the
/// [LintEngine] contract forbids an engine from printing its own install
/// prefix, and a user-supplied custom binary can print anything at all. So the
/// value is reduced to its first line and every whitespace-separated token
/// containing a path separator is dropped, which is what makes the session
/// snapshot's no-paths property a property of the code rather than of the
/// engines that happen to be installed.
String _versionLabel(String raw) {
  final firstLine = raw.split('\n').first.trim();
  final safe = firstLine
      .split(RegExp(r'\s+'))
      .where((token) => !token.contains('/') && !token.contains(r'\'))
      .join(' ');
  // `CruxIssueFallback.unavailable` — "we could not determine this", as
  // distinct from "there are zero of them". Was the LintCrux-only spelling
  // `(version unavailable)` until the shared vocabulary landed.
  if (safe.isEmpty) return CruxIssueFallback.unavailable;
  return safe.length <= 80 ? safe : '${safe.substring(0, 80)}…';
}

/// Scrubs a raw engine version string for inclusion in an issue report.
///
/// Exposed for the privacy test, which asserts the scrub over adversarial
/// input rather than only over whatever the local machine's engines print.
@visibleForTesting
String scrubEngineVersionForReport(String raw) => _versionLabel(raw);
