// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/services/bookmarks/json_file_violation_bookmark_store.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// File name of a project's bookmark file, written beside the project.
/// It can be committed, so a team's curated bookmark set is shareable.
const String kViolationBookmarksFileName = '.lintcrux-bookmarks.json';

/// The tab's [ViolationBookmarkStore]: a [JsonFileViolationBookmarkStore]
/// over `<project-root>/.lintcrux-bookmarks.json`.
///
/// With no project open (and in the web viewer, which has no file system)
/// it is the [NoopViolationBookmarkStore]: no project, no bookmarks.
///
/// Watches `currentProjectProvider`, which only holds a project inside a
/// workspace tab, so `lintcruxTabOverridesFactory` re-binds this provider
/// per tab with [buildViolationBookmarkStore]. The root instance stays the
/// no-op.
final Provider<ViolationBookmarkStore> violationBookmarkStoreProvider =
    Provider<ViolationBookmarkStore>(buildViolationBookmarkStore);

/// Build body of [violationBookmarkStoreProvider]. Top-level so
/// `lintcruxTabOverridesFactory` can re-bind the provider per tab with the
/// identical body.
ViolationBookmarkStore buildViolationBookmarkStore(Ref ref) {
  final root = ref.watch(currentProjectProvider.select((p) => p?.rootPath));
  if (kIsWeb || root == null || root.isEmpty) {
    return const NoopViolationBookmarkStore();
  }
  final file = File(p.join(root, kViolationBookmarksFileName));
  final store = JsonFileViolationBookmarkStore(file, projectRoot: root);
  // listAll() returns an empty list until the load resolves, which is
  // acceptable for the first paint. A file that cannot be read leaves the
  // store refusing writes (see `JsonFileViolationBookmarkStore.loadError`);
  // the reason is logged here.
  unawaited(
    store.load().catchError((Object error, StackTrace st) {
      Logger('lintcrux.bookmarks').severe(
        'Could not read ${file.path}; its bookmarks are not shown and the '
        'file will not be written until it is repaired',
        error,
        st,
      );
    }),
  );
  ref.onDispose(store.dispose);
  return store;
}
