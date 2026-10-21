// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/widgets/settings_section_card.dart';
import 'package:lintcrux/features/violations/providers/saved_filter_presets_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Settings → General page.
///
/// Hosts the cross-cutting non-visual preferences:
///
/// - **Auto-reload mode** — read from / written to
///   `appSettingsProvider.autoReloadMode` (consumed by the
///   `AutoReloadController` via `crux_settings`).
/// - **Default sort column** — initial sort the violation table uses on
///   project load.
/// - **Default filter preset** — preset (from `savedFilterPresetsProvider`)
///   applied when a project opens; "None" means no preset.
/// - **Enable diagnostics** — release builds only; the opt-in for the Tab
///   Diagnostics drawer and the App Diagnostics dialog.
class SettingsGeneralSection extends ConsumerWidget {
  /// Creates a [SettingsGeneralSection].
  const SettingsGeneralSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final tableState = ref.watch(violationTableStateProvider);
    final tableNotifier = ref.read(violationTableStateProvider.notifier);
    final presets = ref.watch(savedFilterPresetsProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsSectionCard(
          children: [
            // The suite-shared control: segmented prompt / auto / off in
            // canonical order (this app previously led with auto).
            CruxAutoReloadSettingTile(
              label: l10n.settingsAutoReloadLabel,
              description: l10n.settingsAutoReloadDescription,
              value: settings.autoReloadMode,
              onChanged: notifier.setAutoReloadMode,
              promptLabel: l10n.settingsAutoReloadPrompt,
              autoLabel: l10n.settingsAutoReloadAuto,
              offLabel: l10n.settingsAutoReloadOff,
            ),
            const SizedBox(height: 24),
            CruxFormRow(
              label: l10n.settingsGeneralDefaultSortLabel,
              child: CruxPopUpButton<ViolationTableColumn>(
                value: tableState.sortColumn,
                expand: true,
                onChanged: tableNotifier.setSortColumn,
                items: [
                  CruxPopUpItem(
                    value: ViolationTableColumn.severity,
                    label: l10n.settingsGeneralDefaultSortSeverity,
                  ),
                  CruxPopUpItem(
                    value: ViolationTableColumn.engine,
                    label: l10n.settingsGeneralDefaultSortEngine,
                  ),
                  CruxPopUpItem(
                    value: ViolationTableColumn.rule,
                    label: l10n.settingsGeneralDefaultSortRule,
                  ),
                  CruxPopUpItem(
                    value: ViolationTableColumn.file,
                    label: l10n.settingsGeneralDefaultSortFile,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            CruxFormRow(
              label: l10n.settingsGeneralDefaultFilterLabel,
              child: CruxPopUpButton<String?>(
                value: presets.activePresetName,
                expand: true,
                placeholder: l10n.settingsGeneralDefaultFilterNone,
                // A null value is "None".
                onChanged: (next) => ref
                    .read(savedFilterPresetsProvider.notifier)
                    .activate(next),
                items: [
                  CruxPopUpItem<String?>(
                    value: null,
                    label: l10n.settingsGeneralDefaultFilterNone,
                  ),
                  for (final p in presets.presets)
                    CruxPopUpItem<String?>(value: p.name, label: p.name),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Gates whether the persisted workspace document is rehydrated at
            // launch. Read at launch — before the document is loaded — by
            // `LintcruxWorkspaceNotifier.shouldRestoreOnLaunch`, so a change
            // here takes effect on the *next* launch. Turning it off leaves
            // the document on disk, so turning it back on restores the
            // session that was there.
            Row(
              children: [
                Expanded(
                  child: CruxFormRow.toggle(
                    key: const Key('settings.restoreTabsOnLaunch'),
                    label: l10n.settingsRestoreTabsOnLaunchLabel,
                    help: l10n.settingsRestoreTabsOnLaunchDescription,
                    value: settings.restoreTabsOnLaunch,
                    onChanged: (enabled) =>
                        notifier.setRestoreTabsOnLaunch(enabled: enabled),
                  ),
                ),
                const SizedBox(width: 4),
                CruxHelpLink(
                  url: HelpUrls.workspaces,
                  tooltip: l10n.helpLinkLearnMore,
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Gates the automatic (launch / periodic / on-resume)
            // update check. The manual "Check for Updates" action ignores it,
            // so turning this off never makes the check unreachable. Persisted
            // through `autoUpdateCheckSettingsServiceProvider`; read back by
            // `crux_updates`' `autoUpdateCheckEnabledProvider`.
            CruxFormRow.toggle(
              key: const Key('settings.autoCheckForUpdates'),
              label: l10n.settingsAutoCheckUpdatesLabel,
              help: l10n.settingsAutoCheckUpdatesDescription,
              value: settings.autoCheckForUpdates,
              onChanged: (enabled) =>
                  notifier.setAutoCheckForUpdates(enabled: enabled),
            ),
            // The release-build opt-in for Tab Diagnostics and App
            // Diagnostics (`diagnosticsEnabledProvider`). Debug and profile
            // builds turn both on regardless, so the switch would be inert
            // there and is shown only in release builds.
            if (!ref.watch(diagnosticsForcedByBuildModeProvider)) ...[
              const SizedBox(height: 24),
              CruxFormRow.toggle(
                key: const Key('settings.diagnosticsEnabled'),
                label: l10n.settingsDiagnosticsEnabledLabel,
                help: l10n.settingsDiagnosticsEnabledDescription,
                value: settings.diagnosticsEnabled,
                onChanged: (enabled) =>
                    notifier.setDiagnosticsEnabled(enabled: enabled),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
