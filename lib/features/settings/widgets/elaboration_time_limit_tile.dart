// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/elaboration_time_limit.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';

/// Settings → Engines → Yosys time limit.
///
/// Automatic scales the time an engine that elaborates the design with Yosys
/// (`yosys`, `cdc`, `constraints`) may take with the size of the sources,
/// Extended allows four times that, and No limit lets it run until it
/// finishes or the user cancels. Applies to the next run; the other engines
/// keep the fixed engine watchdog.
class ElaborationTimeLimitTile extends ConsumerWidget {
  /// Creates the tile.
  const ElaborationTimeLimitTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final current = ref.watch(
      appSettingsProvider.select((s) => s.elaborationTimeLimit),
    );
    return CruxFormRow(
      label: l10n.settingsElaborationTimeLimitLabel,
      help: l10n.settingsElaborationTimeLimitDescription,
      mergeSemantics: false,
      child: CruxSegmentedControl<ElaborationTimeLimit>(
        segments: <CruxSegment<ElaborationTimeLimit>>[
          CruxSegment<ElaborationTimeLimit>(
            value: ElaborationTimeLimit.automatic,
            label: l10n.settingsElaborationTimeLimitAutomatic,
          ),
          CruxSegment<ElaborationTimeLimit>(
            value: ElaborationTimeLimit.extended,
            label: l10n.settingsElaborationTimeLimitExtended,
          ),
          CruxSegment<ElaborationTimeLimit>(
            value: ElaborationTimeLimit.none,
            label: l10n.settingsElaborationTimeLimitNone,
          ),
        ],
        selected: current,
        semanticLabel: l10n.settingsElaborationTimeLimitLabel,
        onChanged: ref
            .read(appSettingsProvider.notifier)
            .setElaborationTimeLimit,
      ),
    );
  }
}
