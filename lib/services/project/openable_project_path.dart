// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_project/crux_project.dart';

/// Whether [path] names something LintCrux opens as a project: a
/// `.lintcrux` project file, or a `<design>.crux-project` design manifest
/// (which `CruxProjectResolver` swaps for the lint project it names).
///
/// The manifest test is [CruxProjectParser.isManifestPath]: the
/// `crux-project` extension, compared case-insensitively, after a non-empty
/// name — or the legacy bare `.crux-project`, which still opens.
///
/// One rule, read from two places: the workspace's open paths, and the CXP
/// workspace link's `accepts` filter. Several products publish the shared
/// workspace kind `source` (an HDL file, a lint project, a simulation
/// configuration), and without the filter the newest record won, so LintCrux
/// could have been handed another product's file to open.
bool isOpenableProjectPath(String path) =>
    path.endsWith('.lintcrux') || CruxProjectParser.isManifestPath(path);
