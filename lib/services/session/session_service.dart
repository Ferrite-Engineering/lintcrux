// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:lintcrux/domain/models/session/lintcrux_session.dart';

/// Disk I/O for `.lintcrux-session` files.
///
/// Wraps a [SessionFileReader] / [SessionFileWriter] pair so tests can
/// swap in in-memory fakes. The production implementation uses
/// `dart:io` directly, with a straightforward `writeAsString` (no
/// temp-file → rename atomic write).
class SessionService {
  /// Creates a [SessionService].
  const SessionService({
    this.reader = const _DartIoSessionReader(),
    this.writer = const _DartIoSessionWriter(),
  });

  /// File reader. Production uses dart:io.
  final SessionFileReader reader;

  /// File writer. Production uses dart:io.
  final SessionFileWriter writer;

  /// Loads [path] and returns the parsed [LintcruxSession]. Propagates
  /// [LintcruxSessionLoadException] for malformed / wrong-version
  /// files; returns `null` when the path doesn't exist.
  Future<LintcruxSession?> load(String path) async {
    final raw = await reader.readString(path);
    if (raw == null) return null;
    final dynamic decoded;
    try {
      decoded = json.decode(raw);
    } on FormatException catch (e) {
      throw LintcruxSessionLoadException(
        'Invalid JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const LintcruxSessionLoadException(
        'Session file root is not a JSON object.',
      );
    }
    return LintcruxSession.fromJson(decoded);
  }

  /// Writes [session] to [path] as pretty-printed JSON.
  Future<void> save(String path, LintcruxSession session) async {
    final body = const JsonEncoder.withIndent('  ').convert(session.toJson());
    await writer.writeString(path, body);
  }
}

/// Per-file string reader abstraction.
// ignore: one_member_abstracts
abstract class SessionFileReader {
  /// Reads the file at [path] and returns its contents, or `null` if
  /// the file doesn't exist.
  Future<String?> readString(String path);
}

/// Per-file string writer abstraction.
// ignore: one_member_abstracts
abstract class SessionFileWriter {
  /// Writes [body] to [path], overwriting any existing file.
  Future<void> writeString(String path, String body);
}

class _DartIoSessionReader implements SessionFileReader {
  const _DartIoSessionReader();
  @override
  Future<String?> readString(String path) async {
    final f = File(path);
    if (!f.existsSync()) return null;
    try {
      return await f.readAsString();
    } on FileSystemException {
      return null;
    }
  }
}

class _DartIoSessionWriter implements SessionFileWriter {
  const _DartIoSessionWriter();
  @override
  Future<void> writeString(String path, String body) async {
    await File(path).writeAsString(body);
  }
}
