// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Crash-safe JSON persistence shared by the per-feature state stores.
///
/// The Pro overlay keeps a JSON file per feature (waivers, filter presets,
/// baselines, bookmarks) alongside the project, and is the only importer of
/// this file. Each store validates its own `version` field on read, because
/// their rules differ; what they share is the write, which must survive a
/// crash mid-write.

/// Writes [data] (any JSON-encodable value) to [file] atomically: encode to a
/// sibling `${file.path}.tmp`, then `rename` over [file]. The parent
/// directory is created if needed.
///
/// [onBeforeRename] is a test-only seam fired after the temp file is written
/// but before the rename — a test passes a throwing callback to simulate a
/// crash at the most dangerous instant and assert the original file is
/// intact. Production callers never pass it.
Future<void> writeJsonAtomic(
  File file,
  Object? data, {
  @visibleForTesting void Function()? onBeforeRename,
}) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  if (onBeforeRename != null) onBeforeRename();
  await tmp.rename(file.path);
}
