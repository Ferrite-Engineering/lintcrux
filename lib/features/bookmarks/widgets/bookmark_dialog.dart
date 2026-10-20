// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';

/// Add / edit dialog for a [BookmarkedViolation].
///
/// Two modes:
/// - **Create** — invoked with a [violation] and no [existing]
///   bookmark. The dialog persists a freshly-constructed
///   [BookmarkedViolation] via the store's `addOrUpdate` on Save.
/// - **Edit** — invoked with an [existing] bookmark to mutate. The
///   dialog persists the edited bookmark (note + color tag); other
///   fields are preserved.
///
/// Form fields:
///   - **Note** (multiline) — markdown-friendly free text. Hint
///     guides the user toward jotting *why* they're keeping this for
///     later.
///   - **Preview pane** — renders the note in monospace with
///     line-break-preserving layout. Plain visual feedback rather
///     than full markdown rendering (we don't want a heavy external
///     dep on the critical path).
///   - **Color tag picker** — one row of 8 preset colors + "none".
///     Palette mirrors NetCrux's bookmark palette for cross-suite
///     consistency.
///
/// Cancel triggers a confirmation dialog when the form is dirty.
class BookmarkDialog extends ConsumerStatefulWidget {
  /// Creates the dialog. Exactly one of [existing] / [violation]
  /// must be supplied. Edit mode is keyed on [existing] being
  /// non-null; create mode otherwise consumes [violation] to
  /// synthesize the bookmark on Save.
  const BookmarkDialog({
    this.existing,
    this.violation,
    super.key,
  });

  /// Existing bookmark when the dialog is opened in edit mode.
  final BookmarkedViolation? existing;

  /// Live violation when the dialog is opened in create mode.
  final Violation? violation;

  @override
  ConsumerState<BookmarkDialog> createState() => _BookmarkDialogState();
}

/// Preset color palette used by the bookmark dialog's color picker.
/// CSS hex format `#RRGGBB`. Order is stable for visual consistency.
const List<String> kBookmarkPaletteHexes = [
  '#F44336', // Red
  '#FF9800', // Orange
  '#FFC107', // Amber
  '#4CAF50', // Green
  '#00BCD4', // Cyan
  '#2196F3', // Blue
  '#9C27B0', // Purple
  '#607D8B', // Blue-grey
];

class _BookmarkDialogState extends ConsumerState<BookmarkDialog> {
  late final TextEditingController _noteController;
  String? _colorHex;
  late final String _initialNote;
  late final String? _initialColor;

  bool get _isEditMode => widget.existing != null;

  bool get _isDirty {
    if (_noteController.text != _initialNote) return true;
    if (_colorHex != _initialColor) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    final initialNote = widget.existing?.note ?? '';
    _noteController = TextEditingController(text: initialNote);
    _initialNote = initialNote;
    _colorHex = widget.existing?.color;
    _initialColor = widget.existing?.color;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final violationOrExisting = widget.existing != null
        ? _ContextPreviewData(
            ruleId: widget.existing!.ruleId,
            filePath: widget.existing!.filePath,
            lineNumber: widget.existing!.lineNumber,
            message: widget.existing!.snippet,
          )
        : _ContextPreviewData(
            ruleId: widget.violation!.ruleId,
            filePath: widget.violation!.location.file,
            lineNumber: widget.violation!.location.line,
            message: widget.violation!.message,
          );

    return CruxDialog(
      title: _isEditMode
          ? l10n.bookmarkDialogTitleEdit
          : l10n.bookmarkDialogTitleCreate,
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ContextPreview(data: violationOrExisting, l10n: l10n),
          const SizedBox(height: 16),
          Text(
            l10n.bookmarkDialogNoteLabel,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('bookmarkDialogNoteField'),
            controller: _noteController,
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: l10n.bookmarkDialogNoteHint,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.bookmarkDialogNotePreviewLabel,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          _NotePreview(text: _noteController.text),
          const SizedBox(height: 16),
          Text(
            l10n.bookmarkDialogColorLabel,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          _ColorPickerRow(
            selectedHex: _colorHex,
            onSelect: (next) => setState(() => _colorHex = next),
            noneLabel: l10n.bookmarkDialogColorNoneLabel,
          ),
        ],
      ),
      actions: [
        CruxDialogAction(
          key: const ValueKey('bookmarkDialogCancel'),
          label: l10n.bookmarkDialogCancelAction,
          onPressed: () => _onCancel(context, l10n),
        ),
        CruxDialogAction(
          key: const ValueKey('bookmarkDialogSave'),
          label: l10n.bookmarkDialogSaveAction,
          role: CruxDialogActionRole.primary,
          onPressed: () => _onSave(context),
        ),
      ],
    );
  }

  Future<void> _onCancel(BuildContext context, L10N l10n) async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    // Suite-standard destructive confirm: "Keep editing" in the cancel
    // slot, error-colored "Discard" verb — mirrors NetCrux's symbol
    // editor unsaved-changes prompt. Any non-button dismissal (scrim,
    // Escape) resolves false, i.e. keeps editing, so in-progress user
    // input is never lost by a stray click.
    final confirmed = await confirmCruxDestructiveAction(
      context,
      title: l10n.bookmarkDialogDiscardConfirmTitle,
      body: l10n.bookmarkDialogDiscardConfirmBody,
      confirmLabel: l10n.bookmarkDialogDiscardConfirmYes,
      cancelLabel: l10n.bookmarkDialogDiscardConfirmNo,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _onSave(BuildContext context) async {
    final store = ref.read(violationBookmarkStoreProvider);
    // Taken before the write's await: the dialog can be dismissed while the
    // bookmark is written, and `ref` throws from then on.
    final telemetry = ref.read(telemetryServiceProvider);
    final noteText = _noteController.text.trim();
    final BookmarkedViolation toSave;
    if (_isEditMode) {
      toSave = widget.existing!.copyWith(
        note: noteText.isEmpty ? null : noteText,
        color: _colorHex,
        updatedAt: DateTime.now().toUtc(),
        clearNote: noteText.isEmpty,
        clearColor: _colorHex == null,
      );
    } else {
      final now = DateTime.now().toUtc();
      toSave = BookmarkedViolation.fromViolation(
        id: _newId(),
        violation: widget.violation!,
        createdAt: now,
        projectRoot: ref.read(currentProjectProvider)?.rootPath ?? '',
        note: noteText.isEmpty ? null : noteText,
        color: _colorHex,
      );
    }
    await store.addOrUpdate(toSave);
    // Past the store write, so the counter means a bookmark exists on disk
    // rather than a dialog was opened.
    //
    // `edit` separates "I made a bookmark" from "I came back to one", which is
    // the difference between a bookmark being a click-once flag and being a
    // working triage queue — the question that decides whether the panel earns
    // further investment. `note` says whether the free-text field was used at
    // all; the note's *text* is the user's own words about their own design and
    // never leaves the process, so a bool is the most this may carry.
    telemetry.record(
      TelemetryEvent(
        'bookmark.saved',
        properties: <String, Object?>{
          'edit': _isEditMode,
          'note': noteText.isNotEmpty,
        },
      ),
    );
    if (!context.mounted) return;
    Navigator.of(context).pop(toSave);
  }

  /// Generates a stable id for new bookmarks. Uses a millisecond
  /// timestamp + a short random hex tail so collisions across
  /// concurrent inserts are vanishingly unlikely without dragging in
  /// the `uuid` package.
  String _newId() {
    final ms = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = (DateTime.now().microsecondsSinceEpoch & 0xFFFFFF)
        .toRadixString(36)
        .padLeft(5, '0');
    return 'bm-$ms-$rand';
  }
}

class _ContextPreviewData {
  const _ContextPreviewData({
    required this.ruleId,
    required this.filePath,
    required this.lineNumber,
    required this.message,
  });
  final String ruleId;
  final String filePath;
  final int lineNumber;
  final String message;
}

class _ContextPreview extends StatelessWidget {
  const _ContextPreview({required this.data, required this.l10n});
  final _ContextPreviewData data;
  final L10N l10n;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final valueStyle = Theme.of(context).textTheme.bodySmall;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(
            l10n.bookmarkDialogContextRuleLabel,
            data.ruleId,
            labelStyle,
            valueStyle,
          ),
          const SizedBox(height: 4),
          _kv(
            l10n.bookmarkDialogContextFileLabel,
            '${data.filePath}:${data.lineNumber}',
            labelStyle,
            valueStyle,
          ),
          const SizedBox(height: 4),
          _kv(
            l10n.bookmarkDialogContextMessageLabel,
            data.message,
            labelStyle,
            valueStyle,
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, TextStyle? l, TextStyle? v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: Text(label, style: l)),
        Expanded(child: Text(value, style: v)),
      ],
    );
  }
}

class _NotePreview extends StatelessWidget {
  const _NotePreview({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final display = text.trim().isEmpty ? '—' : text;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        display,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          color: text.trim().isEmpty
              ? scheme.onSurfaceVariant.withAlpha(140)
              : scheme.onSurface,
        ),
      ),
    );
  }
}

class _ColorPickerRow extends StatelessWidget {
  const _ColorPickerRow({
    required this.selectedHex,
    required this.onSelect,
    required this.noneLabel,
  });
  final String? selectedHex;
  final ValueChanged<String?> onSelect;
  final String noneLabel;
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // "None" chip.
        _NoneSwatch(
          isSelected: selectedHex == null,
          label: noneLabel,
          onTap: () => onSelect(null),
        ),
        for (final hex in kBookmarkPaletteHexes)
          _Swatch(
            hex: hex,
            isSelected: selectedHex == hex,
            onTap: () => onSelect(hex),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.hex,
    required this.isSelected,
    required this.onTap,
  });
  final String hex;
  final bool isSelected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: hex,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoneSwatch extends StatelessWidget {
  const _NoneSwatch({
    required this.isSelected,
    required this.label,
    required this.onTap,
  });
  final bool isSelected;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}
