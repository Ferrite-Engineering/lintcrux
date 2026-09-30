// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// User-configurable shell-out template for click-to-source.
///
/// The template uses `{file}`, `{line}`, and `{column}` placeholders.
/// At launch time, [render] substitutes the placeholders against a
/// concrete [Uri] / line / column and produces the argv that
/// `Process.run` receives.
///
/// Presets cover the most common editor invocations; the `custom`
/// variant lets users plug in any other editor (Helix, Kakoune, IntelliJ
/// CLI launcher, an internal company tool, etc.). The persisted form is
/// a stable JSON payload (see [toJson] / [fromJson]) suitable for
/// round-tripping through `crux_settings`.
@immutable
class EditorCommand {
  /// Creates an [EditorCommand].
  const EditorCommand({
    required this.preset,
    required this.executable,
    required this.argsTemplate,
  });

  /// Deserializes from a JSON map. Returns [defaultPreset] if [map] is
  /// shaped unexpectedly.
  factory EditorCommand.fromJson(Map<String, Object?> map) {
    final preset = EditorPreset.values.firstWhere(
      (p) => p.name == map['preset'],
      orElse: () => EditorPreset.vsCode,
    );
    final exe = map['executable'];
    final args = map['argsTemplate'];
    if (exe is! String || args is! List) return defaultPreset;
    final argList = args.whereType<String>().toList(growable: false);
    if (argList.isEmpty) return defaultPreset;
    return EditorCommand(
      preset: preset,
      executable: exe,
      argsTemplate: argList,
    );
  }

  /// The VS Code preset: `code -g {file}:{line}:{column}`.
  static const EditorCommand vsCode = EditorCommand(
    preset: EditorPreset.vsCode,
    executable: 'code',
    argsTemplate: ['-g', '{file}:{line}:{column}'],
  );

  /// The Sublime Text preset: `subl {file}:{line}:{column}`.
  static const EditorCommand sublime = EditorCommand(
    preset: EditorPreset.sublime,
    executable: 'subl',
    argsTemplate: ['{file}:{line}:{column}'],
  );

  /// The Vim (or Neovim) preset: `vim +{line} {file}`.
  static const EditorCommand vim = EditorCommand(
    preset: EditorPreset.vim,
    executable: 'vim',
    argsTemplate: ['+{line}', '{file}'],
  );

  /// The Emacs preset: `emacs +{line} {file}`.
  static const EditorCommand emacs = EditorCommand(
    preset: EditorPreset.emacs,
    executable: 'emacs',
    argsTemplate: ['+{line}', '{file}'],
  );

  /// The default LintCrux editor command. VS Code is the most widely
  /// installed editor in the target population; if VS Code is not on
  /// the user's `PATH`, the click-to-source action surfaces an
  /// actionable "couldn't launch" snackbar instead of silently
  /// failing.
  static const EditorCommand defaultPreset = vsCode;

  /// Identifies which preset (or the custom escape hatch) the user
  /// chose. Tests use the value, and the settings UI uses it to render
  /// the radio group.
  final EditorPreset preset;

  /// Executable to invoke (resolved against `PATH` by `Process.run`).
  final String executable;

  /// Argument template — each entry is a single argv element with
  /// `{file}`, `{line}`, `{column}` placeholders. The template
  /// `['-g', '{file}:{line}:{column}']` is what `code -g foo.sv:42:13`
  /// produces.
  final List<String> argsTemplate;

  /// Materializes [argsTemplate] for [file] / [line] / [column].
  List<String> render({
    required String file,
    required int line,
    required int column,
  }) {
    return argsTemplate
        .map(
          (arg) => arg
              .replaceAll('{file}', file)
              .replaceAll('{line}', '$line')
              .replaceAll('{column}', '$column'),
        )
        .toList(growable: false);
  }

  /// Returns a copy with overridden fields.
  EditorCommand copyWith({
    EditorPreset? preset,
    String? executable,
    List<String>? argsTemplate,
  }) {
    return EditorCommand(
      preset: preset ?? this.preset,
      executable: executable ?? this.executable,
      argsTemplate: argsTemplate ?? this.argsTemplate,
    );
  }

  /// Serializes to a stable JSON map. Used by the settings codec.
  Map<String, Object?> toJson() => {
    'preset': preset.name,
    'executable': executable,
    'argsTemplate': argsTemplate,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EditorCommand) return false;
    if (other.preset != preset) return false;
    if (other.executable != executable) return false;
    if (other.argsTemplate.length != argsTemplate.length) return false;
    for (var i = 0; i < argsTemplate.length; i++) {
      if (other.argsTemplate[i] != argsTemplate[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(preset, executable, Object.hashAll(argsTemplate));

  @override
  String toString() =>
      'EditorCommand($preset, $executable ${argsTemplate.join(' ')})';
}

/// Editor preset choices surfaced in the Settings → Editors UI.
enum EditorPreset {
  /// VS Code: `code -g {file}:{line}:{column}`.
  vsCode,

  /// Sublime Text: `subl {file}:{line}:{column}`.
  sublime,

  /// Vim / Neovim: `vim +{line} {file}`.
  vim,

  /// Emacs: `emacs +{line} {file}`.
  emacs,

  /// Custom (user-supplied) executable + arg template.
  custom,
}
