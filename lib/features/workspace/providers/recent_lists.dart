// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';

/// The Recent projects list: absolute `.lintcrux` paths, most recent first.
///
/// Every project that opens is recorded with
/// `ref.read(recentProjects.provider.notifier).markOpened(path)`
/// (`OpenProjectInWorkspace` does it, after the open succeeded). The welcome
/// screen shows it, File > Clear Recent Projects empties it, and the CXP
/// containment rule reads it, so a peer's cross-probe can land on a design
/// whose tab was closed.
final CruxRecentList recentProjects = CruxRecentList(
  name: 'recentProjects',
  store: (_) => const CruxPrefsRecentStore('settings.lintcrux.recentProjects'),
);
