// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/help_urls.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Optional override for the `.crux-theme.json` install directory used
/// by the embedded [ThemePackBrowser]. Defaults to `{appSupportDir}/themes`.
typedef PackDirectoryResolver = Future<Directory> Function();

/// Settings → Appearance: drops `crux_theme`'s [ThemeAppearanceSection]
/// composer into LintCrux. Mirrors the WaveCrux / NetCrux adopter
/// pattern — activation flows through `cruxColorThemeProvider`, whose
/// LintCrux notifier override writes preset / token changes back to
/// `AppSettings.core.activeThemeName` + `core.themeOverrides`.
///
/// Tests may inject [packDirectoryResolver] / [pickPackDocument] /
/// [savePackDocument] to keep `path_provider` and the desktop file
/// picker out of the widget tree.
///
/// `crux_theme`'s [ThemePackBrowser] takes a [ThemePackStore] rather
/// than a `Directory`, and exchanges pack *document text* rather than
/// `dart:io` file handles, so the browser itself stays web-safe. This
/// adopter supplies the desktop-only halves: a [DirectoryThemePackStore]
/// rooted at `{appSupportDir}/themes` and `file_picker`-backed
/// read/write closures.
class ColorThemeSection extends ConsumerStatefulWidget {
  /// Creates the Settings → Appearance section.
  const ColorThemeSection({
    this.packDirectoryResolver,
    this.pickPackDocument,
    this.savePackDocument,
    super.key,
  });

  /// Resolves the directory backing the [DirectoryThemePackStore] handed
  /// to [ThemePackBrowser] for installed theme packs.
  final PackDirectoryResolver? packDirectoryResolver;

  /// Optional override for the import picker. Defaults to a desktop
  /// `file_picker` invocation accepting `.json` files, returning the
  /// picked document's text.
  final PickPackDocument? pickPackDocument;

  /// Optional override for the exporter. Defaults to a `file_picker`
  /// save dialog suggesting a `.crux-theme.json` name; returns the
  /// written path for display.
  final SavePackDocument? savePackDocument;

  @override
  ConsumerState<ColorThemeSection> createState() => _ColorThemeSectionState();
}

class _ColorThemeSectionState extends ConsumerState<ColorThemeSection> {
  Directory? _packDirectory;

  @override
  void initState() {
    super.initState();
    unawaited(_resolvePackDirectory());
  }

  Future<void> _resolvePackDirectory() async {
    final resolver = widget.packDirectoryResolver ?? _defaultPackDirectory;
    try {
      final dir = await resolver();
      if (!mounted) return;
      setState(() => _packDirectory = dir);
    } on Object {
      if (!mounted) return;
      setState(() => _packDirectory = Directory.systemTemp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dir = _packDirectory;
    if (dir == null) {
      return const SizedBox(height: 24);
    }
    final theme = Theme.of(context);
    // KNOWN GAP (no-hardcoded-strings): `crux_theme`'s bundled widgets take
    // an English-only `ThemeAppearanceStrings` today. A localized adapter
    // needs ~30 new ARB keys × 5 locales, CJK-glossary-reviewed, so it is
    // deferred rather than done partially.
    const strings = ThemeAppearanceStringsEn();
    final categories = ThemeRegistry.instance.registeredCategories;

    // Composed from the individual `crux_theme` widgets rather than the
    // bundled ThemeAppearanceSection composer, whose "Appearance" heading
    // would duplicate the Settings → Appearance section's own heading. Preset
    // cards, token swatches, and pack rows are *data*, pinned to the value
    // surface (surfaceContainerHighest) to read distinctly from a section card.
    final dataSurface = theme.copyWith(
      cardTheme: theme.cardTheme.copyWith(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
    );

    return Theme(
      data: dataSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SubsectionLabel(strings.presetSectionHeading),
              const SizedBox(width: 4),
              CruxHelpLink(
                url: HelpUrls.themePresets,
                tooltip: L10N.of(context).helpLinkLearnMore,
              ),
            ],
          ),
          const SizedBox(height: 8),
          PresetPicker(presets: builtinPresets().values.toList()),
          const SizedBox(height: 20),
          _SubsectionLabel(strings.tokenOverridesSectionHeading),
          const SizedBox(height: 8),
          for (final category in categories)
            TokenCategorySection(category: category),
          const SizedBox(height: 20),
          _SubsectionLabel(strings.themePackBrowserSectionHeading),
          const SizedBox(height: 8),
          ThemePackBrowser(
            store: DirectoryThemePackStore(directory: dir),
            pickPackDocument:
                widget.pickPackDocument ?? _defaultPickPackDocument,
            savePackDocument:
                widget.savePackDocument ?? _defaultSavePackDocument,
          ),
        ],
      ),
    );
  }

  static Future<Directory> _defaultPackDirectory() async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final dir = Directory(p.join(appSupport.path, 'themes'));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    } on Object {
      return Directory.systemTemp;
    }
  }

  static Future<String?> _defaultPickPackDocument() async {
    final result = await FilePicker.pickFiles(
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return await File(path).readAsString();
  }

  static Future<String?> _defaultSavePackDocument(String document) async {
    // file_picker 12 writes the bytes itself, so handing it the encoded
    // document does the whole export in one step — no follow-up write.
    return await FilePicker.saveFile(
      bytes: Uint8List.fromList(utf8.encode(document)),
      fileName: 'lintcrux-theme.crux-theme.json',
      allowedExtensions: ['json'],
      type: FileType.custom,
    );
  }
}

/// Label for a subsection inside Settings → Appearance (Presets / Color
/// overrides / Theme packs). Lighter than the section heading so the hierarchy
/// reads section → subsection → data.
class _SubsectionLabel extends StatelessWidget {
  const _SubsectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
