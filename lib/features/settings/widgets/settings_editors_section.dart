// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/features/settings/widgets/settings_section_card.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';

/// Settings → Editors page.
///
/// Plugs into the existing [editorCommandProvider] from
/// `lib/services/editor/`. The shell-out template `{file}`, `{line}`,
/// and `{column}` placeholders are exactly the ones consumed by
/// `EditorCommand.render` — there is no duplicate substitution logic.
///
/// **Preset radios** select between VS Code / Sublime Text / Vim /
/// Emacs / Custom. Selecting a non-custom preset overwrites both the
/// executable and the arg template with the matching baked-in preset
/// (the user can immediately switch back). Selecting **Custom** reveals
/// editable executable + args template fields and a live preview line.
class SettingsEditorsSection extends ConsumerStatefulWidget {
  /// Creates a [SettingsEditorsSection].
  const SettingsEditorsSection({super.key});

  @override
  ConsumerState<SettingsEditorsSection> createState() =>
      _SettingsEditorsSectionState();
}

class _SettingsEditorsSectionState
    extends ConsumerState<SettingsEditorsSection> {
  late final TextEditingController _executableController;
  late final TextEditingController _argsTemplateController;

  @override
  void initState() {
    super.initState();
    final current = ref.read(editorCommandProvider);
    _executableController = TextEditingController(text: current.executable);
    _argsTemplateController = TextEditingController(
      text: current.argsTemplate.join(' '),
    );
  }

  @override
  void dispose() {
    _executableController.dispose();
    _argsTemplateController.dispose();
    super.dispose();
  }

  void _selectPreset(EditorPreset preset) {
    final next = _commandFor(preset);
    ref.read(editorCommandProvider.notifier).value = next;
    setState(() {
      _executableController.text = next.executable;
      _argsTemplateController.text = next.argsTemplate.join(' ');
    });
  }

  EditorCommand _commandFor(EditorPreset preset) {
    switch (preset) {
      case EditorPreset.vsCode:
        return EditorCommand.vsCode;
      case EditorPreset.sublime:
        return EditorCommand.sublime;
      case EditorPreset.vim:
        return EditorCommand.vim;
      case EditorPreset.emacs:
        return EditorCommand.emacs;
      case EditorPreset.custom:
        // Custom seeds itself from whatever's currently in the input
        // fields so the user keeps their edits across radio toggles.
        return EditorCommand(
          preset: EditorPreset.custom,
          executable: _executableController.text,
          argsTemplate: _argsTemplateController.text.split(RegExp(r'\s+'))
            ..removeWhere((s) => s.isEmpty),
        );
    }
  }

  void _onCustomFieldChanged() {
    final current = ref.read(editorCommandProvider);
    if (current.preset != EditorPreset.custom) return;
    final argsList = _argsTemplateController.text
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (argsList.isEmpty) return;
    ref.read(editorCommandProvider.notifier).value = EditorCommand(
      preset: EditorPreset.custom,
      executable: _executableController.text,
      argsTemplate: argsList,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final current = ref.watch(editorCommandProvider);
    final isCustom = current.preset == EditorPreset.custom;

    // Live preview: render against a fixed sample file/line/column so
    // users see exactly what `Process.run` will receive.
    final sampleArgs = current.render(
      file: 'src/example.sv',
      line: 42,
      column: 13,
    );
    final previewText = '${current.executable} ${sampleArgs.join(' ')}';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SettingsSectionCard(
          children: [
            Text(
              l10n.settingsEditorsHeader,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            RadioGroup<EditorPreset>(
              groupValue: current.preset,
              onChanged: (p) {
                if (p != null) _selectPreset(p);
              },
              child: Column(
                children: [
                  RadioListTile<EditorPreset>(
                    value: EditorPreset.vsCode,
                    title: Text(l10n.settingsEditorPresetVsCode),
                  ),
                  RadioListTile<EditorPreset>(
                    value: EditorPreset.sublime,
                    title: Text(l10n.settingsEditorPresetSublime),
                  ),
                  RadioListTile<EditorPreset>(
                    value: EditorPreset.vim,
                    title: Text(l10n.settingsEditorPresetVim),
                  ),
                  RadioListTile<EditorPreset>(
                    value: EditorPreset.emacs,
                    title: Text(l10n.settingsEditorPresetEmacs),
                  ),
                  RadioListTile<EditorPreset>(
                    value: EditorPreset.custom,
                    title: Text(l10n.settingsEditorPresetCustom),
                  ),
                ],
              ),
            ),
            if (isCustom) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _executableController,
                decoration: InputDecoration(
                  labelText: l10n.settingsEditorExecutableLabel,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _onCustomFieldChanged(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _argsTemplateController,
                decoration: InputDecoration(
                  labelText: l10n.settingsEditorArgsTemplateLabel,
                  helperText: l10n.settingsEditorTemplateHelp(
                    '{file}',
                    '{line}',
                    '{column}',
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _onCustomFieldChanged(),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              l10n.settingsEditorsLivePreviewLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settingsEditorsLivePreviewSample,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                previewText,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                onPressed: () => _selectPreset(EditorPreset.vsCode),
                child: Text(l10n.settingsEditorsResetButton),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
