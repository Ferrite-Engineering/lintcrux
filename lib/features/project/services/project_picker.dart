// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_project/crux_project.dart';
import 'package:file_selector/file_selector.dart';

/// The extensions the Open Project dialog accepts: `.lintcrux` projects and
/// `<design>.crux-project` suite design manifests. Opening a manifest opens
/// the lint project it names.
const List<String> kProjectPickerExtensions = <String>[
  'lintcrux',
  kCruxProjectExtension,
];

/// Thin wrapper around the platform `file_selector` API for the
/// LintCrux project open/save flows.
///
/// Extracted as a class so tests can inject a fake picker without
/// pulling in the platform plugin's native code. Production callers
/// use [ProjectPicker] directly; widget tests override
/// `projectPickerProvider`.
///
/// Each method takes a required `confirmButtonText` argument so the OS
/// picker can label its action button per flow ("Open Project",
/// "Open Session", "Open Workspace", "Import Filelist", "Create
/// Project"). On macOS this is mapped to `NSOpenPanel.prompt` /
/// `NSSavePanel.prompt` — the rendered button text under the file
/// browser — which is the user-visible distinguisher that the prior
/// generic "Open" / "Save" buttons did not provide. On Linux and
/// Windows it follows whatever the platform implementation maps
/// `confirmButtonText` to.
///
/// Each method likewise takes a required `typeLabel` — the localized
/// name of the file-type filter the OS dialog shows (e.g. "LintCrux
/// project", "HDL sources"). Callers pass the `L10N.filePickerType*Label`
/// string for the flow; the service holds no `L10N` of its own.
class ProjectPicker {
  /// Creates a [ProjectPicker].
  const ProjectPicker();

  /// Open the platform file picker, restricted to `.lintcrux` project
  /// files and `<design>.crux-project` design manifests, and return the
  /// chosen path or `null` if the user cancels.
  Future<String?> pickProjectFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: typeLabel, extensions: kProjectPickerExtensions),
      ],
      confirmButtonText: confirmButtonText,
    );
    return file?.path;
  }

  /// Open the platform file picker for one or more HDL source files
  /// (`.v`, `.sv`, `.svh`, `.vh`, `.vhd`, `.vhdl`). Returns the chosen
  /// absolute paths, or an empty list when the user cancels. Backs the
  /// `File → Open Sources…` action and the `LintcruxAction.openSources`
  /// keyboard shortcut (Cmd/Ctrl+Shift+O).
  Future<List<String>> pickSourceFiles({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: typeLabel,
          extensions: const ['v', 'sv', 'svh', 'vh', 'vhd', 'vhdl'],
        ),
      ],
      confirmButtonText: confirmButtonText,
    );
    return [for (final f in files) f.path];
  }

  /// Open the platform file picker restricted to SARIF documents
  /// (`.sarif` / `.json`). Returns the chosen path or `null` when the
  /// user cancels. Backs the desktop `LintcruxAction.importSarif` flow,
  /// which streams the picked file through [SarifFileLoader] into a
  /// read-only imported-report viewer without re-running the engines.
  Future<String?> pickSarifFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: typeLabel,
          extensions: const ['sarif', 'json'],
          mimeTypes: const ['application/sarif+json', 'application/json'],
        ),
      ],
      confirmButtonText: confirmButtonText,
    );
    return file?.path;
  }

  /// Open the platform file picker restricted to `.f`
  /// (Vivado-style filelist) files. Returns the chosen path or `null`
  /// when the user cancels. Backs the
  /// `File → Import → Vivado Filelist…` menu entry.
  Future<String?> pickFilelistFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: typeLabel, extensions: const ['f']),
      ],
      confirmButtonText: confirmButtonText,
    );
    return file?.path;
  }

  /// EDAM integration — open the platform file picker for a
  /// FuseSoC/Edalize EDAM file. Returns the chosen path or `null` when
  /// the user cancels. Backs the `File → Import FuseSoC EDAM…` menu
  /// entry. EDAM files conventionally end in `.eda.yml`, but
  /// `file_selector` matches only the trailing extension, so the
  /// filter accepts any `.yml` / `.yaml`.
  Future<String?> pickEdamFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: typeLabel, extensions: const ['yml', 'yaml']),
      ],
      confirmButtonText: confirmButtonText,
    );
    return file?.path;
  }

  /// Open the platform file picker restricted to
  /// `.lintcrux-session` files. Returns the chosen path or `null` when
  /// the user cancels. Backs the `File → Open Session…` and
  /// `lintcrux --session <path>` flows.
  Future<String?> pickSessionFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: typeLabel,
          extensions: const ['lintcrux-session'],
        ),
      ],
      confirmButtonText: confirmButtonText,
    );
    return file?.path;
  }

  /// Open the platform file picker restricted to
  /// `.lintcrux-workspace` files. Returns the chosen path or `null`
  /// when the user cancels. Backs the `File → Open Workspace…` and
  /// `lintcrux --workspace <path>` flows.
  Future<String?> pickWorkspaceFile({
    required String confirmButtonText,
    required String typeLabel,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: typeLabel,
          extensions: const ['lintcrux-workspace'],
        ),
      ],
      confirmButtonText: confirmButtonText,
    );
    return file?.path;
  }

  /// Open the platform save picker restricted to
  /// `.lintcrux` files. Returns the chosen path or `null` when the
  /// user cancels. Backs the Welcome screen's New Project… button and
  /// the `LintcruxAction.newProject` / `LintcruxAction.newTab`
  /// shortcut handlers.
  Future<String?> pickSaveProjectFile({
    required String confirmButtonText,
    required String typeLabel,
    String? defaultFileName,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: typeLabel, extensions: const ['lintcrux']),
      ],
      suggestedName: defaultFileName ?? 'new_project.lintcrux',
      confirmButtonText: confirmButtonText,
    );
    return location?.path;
  }

  /// Open the platform save picker restricted to the
  /// supplied [extension] (without the leading dot, e.g. `'sarif'`,
  /// `'json'`, `'csv'`, `'html'`). Returns the chosen path or `null`
  /// when the user cancels. Backs the
  /// `LintcruxAction.exportSarif` / `exportJson` / `exportCsv` /
  /// `exportHtml` handlers. [label] is the export format acronym
  /// (SARIF / JSON / CSV / HTML), which doubles as the type-filter
  /// label; format acronyms are locale-neutral so this stays a plain
  /// string rather than a localized `typeLabel`.
  Future<String?> pickSaveExportFile({
    required String confirmButtonText,
    required String extension,
    required String label,
    String? defaultFileName,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(label: label, extensions: <String>[extension]),
      ],
      suggestedName: defaultFileName ?? 'violations.$extension',
      confirmButtonText: confirmButtonText,
    );
    return location?.path;
  }

  /// Open the platform save picker restricted to
  /// `.lintcrux-workspace` files. Returns the chosen path or `null`
  /// when the user cancels. Backs the `File → Save Workspace As…`
  /// flow.
  Future<String?> pickSaveWorkspaceFile({
    required String confirmButtonText,
    required String typeLabel,
    String? defaultFileName,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: typeLabel,
          extensions: const ['lintcrux-workspace'],
        ),
      ],
      suggestedName: defaultFileName ?? 'lint.lintcrux-workspace',
      confirmButtonText: confirmButtonText,
    );
    return location?.path;
  }

  /// Open the platform save picker restricted to
  /// `.lintcrux-session` files. Returns the chosen path or `null` when
  /// the user cancels. Backs the `File → Export Tab as Session…`
  /// flow.
  Future<String?> pickExportSessionFile({
    required String confirmButtonText,
    required String typeLabel,
    String? defaultFileName,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: typeLabel,
          extensions: const ['lintcrux-session'],
        ),
      ],
      suggestedName: defaultFileName ?? 'tab.lintcrux-session',
      confirmButtonText: confirmButtonText,
    );
    return location?.path;
  }
}
