// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';

/// Filesystem-backed reader/writer for `.lintcrux` project files.
///
/// Thin convenience wrapper around [ProjectFileCodec]: handles reading
/// and writing files on disk, surfacing I/O failures as
/// [ProjectFileException] so the caller has one error type to catch.
///
/// The service is stateless and side-effect-free aside from the I/O
/// itself, so tests construct it directly. To inject a fake filesystem,
/// inject an alternate [ProjectFileCodec] and call its `encode`/`decode`
/// directly (the codec is the I/O-free seam).
class ProjectFileService {
  /// Creates a [ProjectFileService] with an optional injected [codec]
  /// (defaults to the standard [ProjectFileCodec]).
  const ProjectFileService({this.codec = const ProjectFileCodec()});

  /// The codec used to translate between JSON strings and [LintProject].
  /// Public so tests can introspect; treat as immutable.
  final ProjectFileCodec codec;

  /// Read `.lintcrux` JSON from disk and return the parsed
  /// [LintProject]. Throws [ProjectFileException] for missing files,
  /// permission errors, or malformed JSON.
  Future<LintProject> read(String path) async {
    final file = File(path);
    final String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException catch (e) {
      throw ProjectFileException(
        'could not read project file at $path: ${e.message}',
        cause: e,
      );
    }
    return codec.decode(contents);
  }

  /// Write [project] to [path] as pretty-printed JSON. Overwrites any
  /// existing file at the location. Throws [ProjectFileException] on
  /// I/O errors.
  Future<void> write(String path, LintProject project) async {
    final contents = codec.encode(project);
    final file = File(path);
    try {
      await file.writeAsString(contents);
    } on FileSystemException catch (e) {
      throw ProjectFileException(
        'could not write project file at $path: ${e.message}',
        cause: e,
      );
    }
  }
}
