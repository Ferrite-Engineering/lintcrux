// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/rule.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';

/// List of every known rule with a dropdown for promoting / demoting
/// the default severity per project.
///
/// Reads from [ruleDatabaseProvider] for the rule universe and from
/// `currentProjectProvider.severityOverrides` for the active
/// overrides; writes back via
/// [CurrentProjectNotifier.saveSeverityOverride], which applies the
/// override to the running tab and saves it in the project's `.lintcrux`
/// file. A file that cannot be written is reported, never dropped.
///
/// The list shows a small "overridden" badge next to rules whose
/// severity has been changed so the user can spot non-default rows at
/// a glance.
class SeverityOverrideList extends ConsumerWidget {
  /// Creates a [SeverityOverrideList].
  const SeverityOverrideList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final asyncDb = ref.watch(ruleDatabaseProvider);
    final project = ref.watch(currentProjectProvider);
    return asyncDb.when(
      loading: () => const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Center(child: Text('$e')),
      data: (db) {
        final overrides =
            project?.severityOverrides ?? const <String, Severity>{};
        final rules = <Rule>[
          for (final engineId in db.engineIds) ...db.rulesFor(engineId),
        ];
        // Support hosts with opposite height constraints: a bounded
        // Scaffold body (own the scroll, virtualize) and the Settings →
        // Engines section card, which sits inside the section's vertical
        // ListView (unbounded — an Expanded here throws RenderFlex-unbounded
        // and blanks the whole section, so shrink-wrap and let the section
        // scroll). Today only the Settings host is mounted.
        return LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            final list = ListView.builder(
              shrinkWrap: !bounded,
              physics: bounded ? null : const NeverScrollableScrollPhysics(),
              itemCount: rules.length,
              itemExtent: 48,
              itemBuilder: (context, i) {
                final r = rules[i];
                final value = overrides[r.id];
                return _Row(
                  rule: r,
                  currentOverride: value,
                  onChanged: (sev) => unawaited(
                    _save(context, ref, r.id, sev),
                  ),
                );
              },
            );
            return Column(
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.engineConfigSeverityOverridesHeader,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (bounded) Expanded(child: list) else list,
              ],
            );
          },
        );
      },
    );
  }
}

Future<void> _save(
  BuildContext context,
  WidgetRef ref,
  String ruleId,
  Severity? severity,
) async {
  try {
    await ref
        .read(currentProjectProvider.notifier)
        .saveSeverityOverride(ruleId, severity);
  } on ProjectFileException catch (e) {
    if (!context.mounted) return;
    showCruxErrorSnack(context, e.message);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.rule,
    required this.currentOverride,
    required this.onChanged,
  });
  final Rule rule;
  final Severity? currentOverride;
  final ValueChanged<Severity?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final isOverridden =
        currentOverride != null && currentOverride != rule.defaultSeverity;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rule.id,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (isOverridden) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(l10n.engineConfigOverrideBadge),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: DropdownButton<Severity>(
              key: ValueKey('severityOverride-${rule.id}'),
              value: currentOverride ?? rule.defaultSeverity,
              isExpanded: true,
              onChanged: (sev) {
                if (sev == null || sev == rule.defaultSeverity) {
                  onChanged(null);
                } else {
                  onChanged(sev);
                }
              },
              items: [
                DropdownMenuItem(
                  value: Severity.error,
                  child: Text(l10n.severityError),
                ),
                DropdownMenuItem(
                  value: Severity.warning,
                  child: Text(l10n.severityWarning),
                ),
                DropdownMenuItem(
                  value: Severity.note,
                  child: Text(l10n.severityNote),
                ),
                DropdownMenuItem(
                  value: Severity.none,
                  child: Text(l10n.engineConfigSeverityOff),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
