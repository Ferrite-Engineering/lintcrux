// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/core/platform/web_mode.dart';
import 'package:meta/meta.dart';

/// Snapshot of the source surrounding a violation, sized for the
/// source-preview pane.
///
/// The service reads a window of [contextLines] (default 10) lines
/// around the violation's `line`. Lines are 1-indexed to match every
/// engine's location reporting. [highlightLine] is the violation line
/// itself; [highlightedRelated] is the set of other lines from the
/// violation's `relatedLocations` that happen to be in the visible
/// window so the renderer can show secondary highlights.
@immutable
class SourceWindow {
  /// Creates a [SourceWindow].
  const SourceWindow({
    required this.file,
    required this.startLine,
    required this.lines,
    required this.highlightLine,
    this.highlightedRelated = const <int>{},
  });

  /// Absolute path to the source file. Surfaced in the gutter header.
  final String file;

  /// 1-indexed line number of [lines.first].
  final int startLine;

  /// Source lines in display order. Empty when the file is unreadable.
  final List<String> lines;

  /// 1-indexed line that gets the primary highlight (the violation's
  /// `location.line`).
  final int highlightLine;

  /// 1-indexed lines in [lines] that get a secondary highlight (other
  /// `relatedLocations` of the same violation that happen to fall in
  /// the same source file and window).
  final Set<int> highlightedRelated;

  /// Whether the window is empty (file unreadable / no lines).
  bool get isEmpty => lines.isEmpty;
}

/// Reads a context window from a source file for the source-preview
/// pane.
///
/// Backed by `dart:io` by default; tests inject a [SourceReader] fake
/// that serves canned content without touching the filesystem.
class SourcePreviewService {
  /// Creates a [SourcePreviewService].
  const SourcePreviewService({
    this.reader = const _DartIoSourceReader(),
    this.contextLines = 10,
  });

  /// Source-file reader. Production uses the [_DartIoSourceReader];
  /// tests inject a fake.
  final SourceReader reader;

  /// Number of lines on each side of the violation line to include.
  /// Default 10 — the preview pane defaults to a ~20-line window.
  final int contextLines;

  /// Loads a window of source lines around the violation.
  ///
  /// [relatedLineSet] — the violation's other locations that share the
  /// same file. Anything inside the resolved window gets surfaced via
  /// [SourceWindow.highlightedRelated].
  Future<SourceWindow> windowAround({
    required String file,
    required int line,
    Set<int> relatedLineSet = const <int>{},
  }) async {
    if (line < 1) {
      return SourceWindow(
        file: file,
        startLine: 1,
        lines: const <String>[],
        highlightLine: line,
      );
    }
    final all = await reader.readLines(file);
    if (all == null) {
      return SourceWindow(
        file: file,
        startLine: 1,
        lines: const <String>[],
        highlightLine: line,
      );
    }
    final start = (line - contextLines).clamp(1, all.length);
    final end = (line + contextLines).clamp(1, all.length);
    final slice = all.sublist(start - 1, end);
    final related = relatedLineSet
        .where((l) => l >= start && l <= end && l != line)
        .toSet();
    return SourceWindow(
      file: file,
      startLine: start,
      lines: List<String>.unmodifiable(slice),
      highlightLine: line,
      highlightedRelated: Set<int>.unmodifiable(related),
    );
  }
}

/// Abstraction for reading a source file as a list of lines.
// ignore: one_member_abstracts
abstract class SourceReader {
  /// Reads [file] and returns its lines, or `null` if the file is
  /// missing / unreadable. Lines are returned without trailing
  /// newlines.
  Future<List<String>?> readLines(String file);
}

/// Production source reader.
class _DartIoSourceReader implements SourceReader {
  const _DartIoSourceReader();

  @override
  Future<List<String>?> readLines(String file) async {
    // The web read-only viewer renders the source preview pane but
    // has no filesystem access — `dart:io`'s `File` throws
    // `UnsupportedError` in the browser. Short-circuit to `null` so
    // the pane shows the "file unreadable" placeholder instead of
    // tripping an error guard up the tree.
    if (isWebMode) return null;
    try {
      final f = File(file);
      if (!f.existsSync()) return null;
      final text = await f.readAsString();
      return text.split('\n');
    } on FileSystemException {
      return null;
    }
  }
}
