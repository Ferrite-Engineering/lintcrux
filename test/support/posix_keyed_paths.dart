// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:path/path.dart' as p;

/// The posix form of [path], whatever host produced it: separators are `/`,
/// `.` and `..` segments are folded, and a drive prefix is dropped, so
/// `D:\proj\sw`, `D:/proj/./sw` and `/proj/sw` all become `/proj/sw`.
///
/// Code that joins or normalises a path through `package:path` spells the
/// result in the host's own style, so `\p\sw` on Windows and `/p/sw`
/// elsewhere. A test that compares through this form keeps its expectations
/// readable and host-independent.
///
/// Windows-style splitting is used on purpose: it understands both separators
/// on every host, where the posix context would treat `D:\proj\sw` as one
/// file name. A relative path stays relative.
String posixKey(String path) {
  final segments = p.windows.split(path);
  if (segments.isEmpty) return path;
  final absolute = p.windows.isAbsolute(path);
  final rest = absolute ? segments.skip(1) : segments;
  final joined = p.posix.joinAll(rest);
  return p.posix.normalize(absolute ? p.posix.join('/', joined) : joined);
}

/// The separator between the entries of a `PATH` value on the host running
/// the test.
String get hostSearchPathSeparator => Platform.isWindows ? ';' : ':';

/// [dirs] joined as a `PATH` value, with [separator] (the host's by default).
String joinSearchPath(Iterable<String> dirs, {String? separator}) =>
    dirs.join(separator ?? hostSearchPathSeparator);

/// The entries of the `PATH` value [path], split on [separator] (the host's
/// by default).
List<String> splitSearchPath(String path, {String? separator}) =>
    path.split(separator ?? hostSearchPathSeparator);
