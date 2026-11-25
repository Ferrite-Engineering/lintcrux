// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The paths of the projects being opened right now, oldest first.
///
/// `OpenProjectInWorkspace.openProject` adds a path before it reads anything
/// and removes it when the open ends, however it ends. The start screen shows
/// a progress banner for the first entry, so a project on a slow share
/// acknowledges the click at once instead of looking like a hang.
final NotifierProvider<OpeningProjectsNotifier, List<String>>
openingProjectsProvider =
    NotifierProvider<OpeningProjectsNotifier, List<String>>(
      OpeningProjectsNotifier.new,
      name: 'openingProjectsProvider',
    );

/// Holds [openingProjectsProvider]'s list.
class OpeningProjectsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const <String>[];

  /// Marks [path] as being opened.
  void begin(String path) => state = List<String>.unmodifiable([...state, path]);

  /// Marks one open of [path] as finished.
  void end(String path) {
    final next = [...state];
    if (!next.remove(path)) return;
    state = List<String>.unmodifiable(next);
  }
}
