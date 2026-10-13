// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Answers whether the project file behind a Recent projects entry is still
/// on disk.
typedef RecentProjectExists = bool Function(String path);

/// The check the welcome screen greys a Recent projects row with.
///
/// Synchronous on purpose: the list holds a handful of paths, and a row that
/// renders first and greys a frame later reads as a flicker. A path whose
/// check throws (a permission error on a parent directory) counts as present,
/// so the row stays as it was and opening it reports the real error. A browser
/// has no file system to ask, so on the web every path answers present.
/// Tests override it with a fixed answer.
final Provider<RecentProjectExists> recentProjectExistsProvider =
    Provider<RecentProjectExists>(
      (_) => defaultRecentProjectExists,
      name: 'recentProjectExistsProvider',
    );

/// The default [RecentProjectExists]: a file-system check.
bool defaultRecentProjectExists(String path) {
  if (kIsWeb) return true;
  try {
    return File(path).existsSync();
  } on Object {
    return true;
  }
}
