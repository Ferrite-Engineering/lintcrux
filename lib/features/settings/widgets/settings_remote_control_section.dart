// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/features/settings/widgets/settings_section_card.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Settings → CXP Cross-Probe page.
///
/// Drives the `AppSettings` fields that gate the CXP cross-probe server:
/// `cxpServerEnabled` (boot-time toggle), `cxpServerPort` (TCP port on
/// `127.0.0.1`), `requestAttentionOnCrossProbe`, and
/// `broadcastSelectionOnCrossProbe`.
///
/// The lifecycle provider (`cxpServerLifecycleProvider`) watches
/// `cxpServerConfigProvider` (which derives from `appSettingsProvider`)
/// so changes made here take effect immediately — toggling the switch
/// off stops the server; changing the port restarts it.
///
/// The controls themselves are the suite-shared [CruxCxpSettingsControls]
/// (crux_cxp_ui) — this widget supplies LintCrux's provider wiring,
/// localized strings, and the sensors-icon status tile.
class SettingsRemoteControlSection extends ConsumerWidget {
  /// Creates a [SettingsRemoteControlSection].
  const SettingsRemoteControlSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsSectionCard(
          children: [
            CruxCxpSettingsControls(
              strings: CruxCxpSettingsStrings(
                enableLabel: l10n.settingsCxpEnabledLabel,
                enableHelp: l10n.settingsCxpEnabledDescription,
                portLabel: l10n.settingsCxpPortLabel,
                portHelp: l10n.settingsCxpPortDescription,
                portError: l10n.settingsCxpPortError,
                attentionLabel: l10n.settingsRequestAttentionOnCrossProbeLabel,
                attentionHelp:
                    l10n.settingsRequestAttentionOnCrossProbeDescription,
                broadcastLabel:
                    l10n.settingsBroadcastSelectionOnCrossProbeLabel,
                broadcastHelp:
                    l10n.settingsBroadcastSelectionOnCrossProbeDescription,
              ),
              enabled: settings.cxpServerEnabled,
              port: settings.cxpServerPort,
              requestAttention: settings.requestAttentionOnCrossProbe,
              broadcastSelection: settings.broadcastSelectionOnCrossProbe,
              onEnabledChanged: (enabled) =>
                  notifier.setCxpServerEnabled(enabled: enabled),
              onPortSubmitted: notifier.setCxpServerPort,
              onRequestAttentionChanged: (enabled) =>
                  notifier.setRequestAttentionOnCrossProbe(enabled: enabled),
              onBroadcastSelectionChanged: (enabled) =>
                  notifier.setBroadcastSelectionOnCrossProbe(enabled: enabled),
              statusTile: const _CxpStatusTile(),
            ),
          ],
        ),
      ],
    );
  }
}

/// CXP Status line — the running-state + connected-peer readout that closes
/// the Cross-Probe section (matching WaveCrux's canonical layout).
///
/// Reads the same providers the docked cross-probe panel does:
/// [cxpServerLifecycleProvider] for the running flag and bound port, and
/// [cxpPeersProvider] for the connected-peer count. When the server is off
/// (or still binding), it shows "Stopped".
class _CxpStatusTile extends ConsumerWidget {
  const _CxpStatusTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final lifecycle = ref.watch(cxpServerLifecycleProvider);
    final running = lifecycle.value?.running ?? false;
    final boundPort = lifecycle.value?.boundPort;
    final peerCount = ref.watch(cxpPeersProvider).length;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        running ? Icons.sensors : Icons.sensors_off,
        color: running ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              l10n.settingsCxpStatus,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          CruxHelpLink(
            url: HelpUrls.crossProbe,
            tooltip: l10n.helpLinkLearnMore,
          ),
        ],
      ),
      subtitle: Text(
        running
            ? l10n.settingsCxpStatusRunning(
                (boundPort ?? '').toString(),
              )
            : l10n.settingsCxpStatusStopped,
      ),
      trailing: running
          ? Text(
              l10n.settingsCxpPeersConnected(peerCount),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : null,
    );
  }
}
