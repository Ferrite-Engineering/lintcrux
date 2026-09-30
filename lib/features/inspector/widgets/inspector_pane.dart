// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/rule.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/widgets/severity_chip.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/rules/rule_database_provider.dart';

/// Right-pane inspector that surfaces details for the currently
/// [selectedViolationProvider] violation.
///
/// Sections (top to bottom):
///   1. Severity chip + engine-namespaced rule id.
///   2. Engine message text.
///   3. file:line:col with an "Open in editor" button.
///   4. Rule database metadata (tags + "Learn more" help URL).
///   5. Related locations (one row each, click to navigate).
///
/// When no violation is selected, renders a discoverable empty state.
class InspectorPane extends ConsumerWidget {
  /// Creates an [InspectorPane].
  const InspectorPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final selected = ref.watch(selectedViolationProvider);
    if (selected == null) {
      final runState = ref.watch(lintRunProvider);
      if (runState.statuses.isEmpty) {
        return CruxPanelEmptyState(message: l10n.inspectorEmpty);
      }
      return _EngineStatusList(
        statuses: runState.statuses.values.toList(growable: false),
      );
    }
    final ruleDbAsync = ref.watch(ruleDatabaseProvider);
    final rule = ruleDbAsync.maybeWhen(
      data: (db) => db.lookup(selected.ruleId),
      orElse: () => null,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // The way back. Selecting a row swaps this pane from engine status to
        // violation detail, and that used to be one-directional — collapsing
        // the dock hides the pane but does not restore what it was showing.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(l10n.inspectorClearSelection),
            onPressed: () =>
                ref.read(selectedViolationProvider.notifier).clear(),
          ),
        ),
        const SizedBox(height: 4),
        _RuleHeader(violation: selected),
        const SizedBox(height: 16),
        _Section(
          title: l10n.inspectorMessageHeader,
          child: SelectableText(
            selected.message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 16),
        _LocationSection(violation: selected),
        if (rule != null && (rule.tags.isNotEmpty || rule.helpUri != null)) ...[
          const SizedBox(height: 16),
          _MetadataSection(rule: rule),
        ],
        if (selected.relatedLocations.isNotEmpty) ...[
          const SizedBox(height: 16),
          _RelatedLocationsSection(violation: selected),
        ],
      ],
    );
  }
}

/// Per-engine status list rendered in the inspector when no violation
/// is selected but a lint run has produced status entries. Surfaces
/// the missing-binary condition (`unavailable`) with a remediation
/// hint pointing the user at Settings → Engines.
class _EngineStatusList extends StatelessWidget {
  const _EngineStatusList({required this.statuses});
  final List<EngineRunStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final needsHint = statuses.any(
      (s) =>
          s.phase == EngineRunPhase.unavailable ||
          s.phase == EngineRunPhase.failed,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.inspectorEngineStatusHeader,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        for (final status in statuses) _EngineStatusRow(status: status),
        if (needsHint) ...[
          const SizedBox(height: 12),
          Text(
            l10n.inspectorEngineConfigureHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _EngineStatusRow extends StatelessWidget {
  const _EngineStatusRow({required this.status});
  final EngineRunStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = _iconFor(status.phase, scheme);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status.engineId,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _phaseLabel(l10n, status.phase),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                      ),
                    ),
                  ],
                ),
                if (status.error != null && status.error!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: SelectableText(
                      status.error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color) _iconFor(
    EngineRunPhase phase,
    ColorScheme scheme,
  ) {
    switch (phase) {
      case EngineRunPhase.idle:
        return (Icons.schedule, scheme.onSurfaceVariant);
      case EngineRunPhase.running:
        return (Icons.play_arrow, scheme.primary);
      case EngineRunPhase.completed:
        return (Icons.check_circle, Colors.green);
      case EngineRunPhase.failed:
        return (Icons.error, scheme.error);
      case EngineRunPhase.unavailable:
        return (Icons.help_outline, scheme.error);
      case EngineRunPhase.cancelled:
        return (Icons.cancel, scheme.onSurfaceVariant);
    }
  }

  static String _phaseLabel(L10N l10n, EngineRunPhase phase) {
    switch (phase) {
      case EngineRunPhase.idle:
        return l10n.inspectorEnginePhaseIdle;
      case EngineRunPhase.running:
        return l10n.inspectorEnginePhaseRunning;
      case EngineRunPhase.completed:
        return l10n.inspectorEnginePhaseCompleted;
      case EngineRunPhase.failed:
        return l10n.inspectorEnginePhaseFailed;
      case EngineRunPhase.unavailable:
        return l10n.inspectorEnginePhaseUnavailable;
      case EngineRunPhase.cancelled:
        return l10n.inspectorEnginePhaseCancelled;
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _RuleHeader extends ConsumerWidget {
  const _RuleHeader({required this.violation});
  final Violation violation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return _Section(
      title: l10n.inspectorRuleHeader,
      child: Row(
        children: [
          SeverityIcon(severity: violation.severity),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              violation.ruleId,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationSection extends ConsumerWidget {
  const _LocationSection({required this.violation});
  final Violation violation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final location = violation.location;
    // A Wrap, not a Row: the Details dock can be dragged narrower than the
    // path and the button together, and a Row then overflowed — the button
    // alone is wider than a narrow dock in some locales. The button moves
    // under the path instead ("crop, don't crush").
    return _Section(
      title: l10n.inspectorLocationHeader,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SelectableText(
            '${location.file}:${location.line}:${location.column}',
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
          ),
          OutlinedButton.icon(
            onPressed: () => _openInEditor(context, ref, location),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(
              l10n.inspectorOpenInEditor,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInEditor(
    BuildContext context,
    WidgetRef ref,
    SourceLocation location,
  ) async {
    final svc = ref.read(clickToSourceServiceProvider);
    final l10n = L10N.of(context);
    final result = await svc.openInEditor(location);
    if (!context.mounted) return;
    if (!result.success) {
      showCruxErrorSnack(
        context,
        l10n.editorLaunchFailed(result.command.toString()),
      );
    }
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.rule});
  final Rule rule;
  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return _Section(
      title: l10n.inspectorMetadataHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rule.tags.isNotEmpty)
            Row(
              children: [
                Text(
                  '${l10n.inspectorTagsLabel}:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: rule.tags
                        .map(
                          (t) => Chip(
                            label: Text(t),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          if (rule.helpUri != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _copyHelpUrl(context, rule.helpUri!),
                icon: const Icon(Icons.open_in_browser, size: 16),
                label: Text(l10n.inspectorHelpUrlLabel),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copyHelpUrl(BuildContext context, Uri url) async {
    // Copy the URL to the clipboard so the user can paste it; the inspector
    // does not launch a browser itself.
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (!context.mounted) return;
    showCruxInfoSnack(context, url.toString());
  }
}

class _RelatedLocationsSection extends ConsumerWidget {
  const _RelatedLocationsSection({required this.violation});
  final Violation violation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return _Section(
      title: l10n.inspectorRelatedLocationsHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final loc in violation.relatedLocations)
            InkWell(
              onTap: () async {
                final svc = ref.read(clickToSourceServiceProvider);
                await svc.openInEditor(loc);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${loc.file}:${loc.line}:${loc.column}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
