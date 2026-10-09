// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/features/violations/providers/saved_filter_presets_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/workspace/services/active_tab_scope.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';

/// Dropdown rendered above the violation table that exposes the
/// user's saved filter presets.
///
/// The dropdown carries:
///
/// - **(None)** at the top — deactivates the preset selection. The
///   table filters keep whatever the user has manually applied; the
///   preset selection just stops claiming to "be" any particular preset.
/// - **Each saved preset** by name, in the order returned by
///   `savedFilterPresetsProvider`.
/// - **Save current filters as preset…** — opens [FilterPresetSaveDialog]
///   so the user can name the current filter state as a preset.
/// - **Manage presets…** — opens [FilterPresetManageDialog] which lists
///   every preset with a delete affordance.
///
/// All persistence is mediated through `savedFilterPresetsProvider`.
class FilterPresetDropdown extends ConsumerWidget {
  /// Creates a [FilterPresetDropdown].
  const FilterPresetDropdown({super.key});

  static const String _saveSentinel = '__save__';
  static const String _manageSentinel = '__manage__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(savedFilterPresetsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Capped + ellipsized so a squeezed pane crops the label
          // instead of overflowing the Row. The cap is far above the
          // label's intrinsic width in every supported locale, so at
          // normal pane widths this renders identically to the old
          // bare Text — and the dropdown stays the sole flex child,
          // keeping its isExpanded share of the row unchanged.
          //
          // The visible label is excluded from semantics and given to the
          // dropdown instead: on its own the dropdown was announced only by
          // its current value ("None button collapsed"), with the name it
          // controls sitting on a separate node focus never reaches.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: ExcludeSemantics(
              child: Text(
                l10n.filterPresetDropdownLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Semantics(
              label: l10n.filterPresetDropdownLabel,
              child: DropdownButton<String?>(
                key: const ValueKey('filterPresetDropdown'),
                value: state.activePresetName,
                isExpanded: true,
                hint: Text(l10n.filterPresetNoneLabel),
                onChanged: (next) async {
                  if (next == _saveSentinel) {
                    await _showSaveDialog(context, ref);
                    return;
                  }
                  if (next == _manageSentinel) {
                    await _showManageDialog(context, ref);
                    return;
                  }
                  ref.read(savedFilterPresetsProvider.notifier).activate(next);
                  // The fifth `filter.used` kind. Recorded at the dropdown
                  // rather than on `SavedFilterPresetsNotifier.activate`, which
                  // session restore also drives — see the note on
                  // `ViolationFilterChips._recordFilterUsed`.
                  ref
                      .read(telemetryServiceProvider)
                      .record(
                        TelemetryEvent(
                          'filter.used',
                          properties: <String, Object?>{
                            'kind': telemetryEnumToken(
                              LintcruxFilterKind.preset,
                            ),
                          },
                        ),
                      );
                },
                items: [
                  DropdownMenuItem<String?>(
                    child: Text(l10n.filterPresetNoneLabel),
                  ),
                  for (final p in state.presets)
                    DropdownMenuItem<String?>(
                      value: p.name,
                      child: Text(p.name),
                    ),
                  DropdownMenuItem<String?>(
                    value: _saveSentinel,
                    child: Text(l10n.filterPresetSaveAction),
                  ),
                  DropdownMenuItem<String?>(
                    value: _manageSentinel,
                    child: Text(l10n.filterPresetManageAction),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSaveDialog(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _FilterPresetSaveDialog(),
    );
    if (name == null || name.isEmpty) return;
    final preset = ref.read(violationTableStateProvider).toPreset(name);
    final notifier = ref.read(savedFilterPresetsProvider.notifier)
      ..save(preset)
      ..activate(name);
    if (!context.mounted) return;
    await reportPresetWriteFailure(context, notifier.persisted);
  }

  Future<void> _showManageDialog(BuildContext context, WidgetRef ref) =>
      showProjectFilterPresetManageDialog(context);
}

/// Opens the dialog that lists and deletes the project's saved filter
/// presets (`savedFilterPresetsProvider`). Public so an overlay that
/// replaces [FilterPresetDropdown] (see `filterPresetDropdownVisibleProvider`)
/// can still offer it. [context] must be inside the tab's scope.
Future<void> showProjectFilterPresetManageDialog(BuildContext context) async {
  // `wrapInActiveTabScope`, unlike the dropdown's save dialog: the manage
  // dialog READS `savedFilterPresetsProvider` (and deletes through it)
  // with its own `ref`, and a dialog route is a child of the Navigator,
  // which sits ABOVE the per-tab `UncontrolledProviderScope`. Without the
  // wrapper its reads resolve the ROOT container, whose presets list is
  // always empty — the dialog rendered "No saved presets" over a dropdown
  // that was visibly listing several, and Delete wrote to the root
  // notifier so nothing disappeared. The save dialog needs no wrapper
  // because it reads nothing: it returns a name by `pop` and the caller
  // above (still inside the tab scope) does the per-tab write.
  await showDialog<void>(
    context: context,
    builder: (_) => wrapInActiveTabScope(
      context,
      const _FilterPresetManageDialog(),
    ),
  );
}

class _FilterPresetSaveDialog extends StatefulWidget {
  const _FilterPresetSaveDialog();

  @override
  State<_FilterPresetSaveDialog> createState() =>
      _FilterPresetSaveDialogState();
}

class _FilterPresetSaveDialogState extends State<_FilterPresetSaveDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return AlertDialog(
      title: Text(l10n.filterPresetSaveDialogTitle),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: l10n.filterPresetNameLabel,
          border: const OutlineInputBorder(),
        ),
        autofocus: true,
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.filterPresetCancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.filterPresetSaveButton),
        ),
      ],
    );
  }
}

class _FilterPresetManageDialog extends ConsumerWidget {
  const _FilterPresetManageDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(savedFilterPresetsProvider);
    return AlertDialog(
      title: Text(l10n.filterPresetManageDialogTitle),
      content: SizedBox(
        width: 360,
        child: state.presets.isEmpty
            ? Text(l10n.filterPresetEmptyState)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final p in state.presets) _PresetRow(preset: p),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.filterPresetDoneButton),
        ),
      ],
    );
  }
}

class _PresetRow extends ConsumerWidget {
  const _PresetRow({required this.preset});

  final NamedFilterPreset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    return ListTile(
      title: Text(preset.name),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.filterPresetDeleteTooltip,
        onPressed: () {
          final notifier = ref.read(savedFilterPresetsProvider.notifier)
            ..delete(preset.name);
          unawaited(reportPresetWriteFailure(context, notifier.persisted));
        },
      ),
    );
  }
}

/// Awaits [persisted] and shows its [ProjectFileException] in an error
/// snackbar, so a preset that could not be written to the project file is
/// reported rather than silently kept only for this session.
Future<void> reportPresetWriteFailure(
  BuildContext context,
  Future<void> persisted,
) async {
  try {
    await persisted;
  } on ProjectFileException catch (e) {
    if (!context.mounted) return;
    showCruxErrorSnack(context, e.message);
  }
}
