// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/features/workspace/services/crux_project_resolution.dart';

/// What a file the operating system opened LintCrux with is, and so which
/// existing path opens it.
///
/// One value per document type the macOS runner's `Info.plist` registers.
/// Each routes into the path that already opens that kind of file, so a
/// Finder double-click behaves exactly like the equivalent command-line
/// argument or menu command, including its error reporting and the security
/// checks on the way in.
enum IncomingFileKind {
  /// A `.lintcrux` project or a `<design>.crux-project` manifest: opens in a
  /// new tab, as a positional command-line argument does.
  project,

  /// A `.lintcrux-workspace`: replaces the workspace, as `--workspace` does.
  workspace,

  /// A `.lintcrux-session`: opens its project with the saved view, as
  /// `--session` does.
  session,

  /// A Vivado `.f` filelist: becomes a project, as `--import-filelist` does.
  filelist,

  /// A `.sarif` report: opens read-only, as File > Import SARIF report does.
  sarif,

  /// An HDL source file: added to the active project, as File > Open Source
  /// Files does.
  hdlSource,
}

const Set<String> _hdlExtensions = <String>{
  '.v',
  '.vh',
  '.sv',
  '.svh',
  '.vhd',
  '.vhdl',
};

/// Classifies [path] by its extension, case-insensitively, or returns
/// `null` for a file LintCrux does not open.
IncomingFileKind? classifyIncomingFile(String path) {
  if (isOpenableProjectPath(path)) return IncomingFileKind.project;
  final lower = path.toLowerCase();
  if (lower.endsWith('.lintcrux')) return IncomingFileKind.project;
  if (lower.endsWith('.lintcrux-workspace')) return IncomingFileKind.workspace;
  if (lower.endsWith('.lintcrux-session')) return IncomingFileKind.session;
  if (lower.endsWith('.f')) return IncomingFileKind.filelist;
  if (lower.endsWith('.sarif')) return IncomingFileKind.sarif;
  final dot = lower.lastIndexOf('.');
  if (dot >= 0 && _hdlExtensions.contains(lower.substring(dot))) {
    return IncomingFileKind.hdlSource;
  }
  return null;
}
