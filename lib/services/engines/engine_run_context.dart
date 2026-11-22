// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:path/path.dart' as p;

/// The directory an engine subprocess runs in, and the root its parser
/// resolves reported paths against.
///
/// Both must be the same directory: an engine prints the paths of the files
/// it complains about relative to where it ran, and the parser turns them back
/// into absolute paths against [rootPath]. Where the two disagree a finding
/// refers to a file that is not there and is dropped.
///
/// The answer, in order:
///
/// 1. [LintRunRequest.projectRoot], the project's root. Every source file of
///    a project is somewhere under it, so a path an engine prints relative to
///    it names a file inside it. Only used when the directory exists: a
///    project file that carries an absolute `rootPath` from another machine
///    must not turn into an engine that cannot start.
/// 2. [configuredRoot], the root the engine was constructed with. Production
///    engines are built without one.
/// 3. The directory of the first source file. A request built by hand with no
///    project has nothing better, and with sources in more than one folder
///    this is the answer that loses findings, so the project root is
///    preferred whenever there is one.
String engineRootPath(LintRunRequest request, {String configuredRoot = ''}) {
  final projectRoot = request.projectRoot;
  if (projectRoot.isNotEmpty && Directory(projectRoot).existsSync()) {
    return projectRoot;
  }
  if (configuredRoot.isNotEmpty) return configuredRoot;
  if (request.sourceFiles.isEmpty) return '';
  return p.dirname(request.sourceFiles.first);
}

/// The `List<String>` option [key] from the project's per-engine options bag,
/// or an empty list when it is absent or not a list. Empty and non-string
/// entries are skipped.
///
/// This is the one reader behind every per-engine `extraOptions` and
/// `waiverFiles` key, so the keys mean the same thing for every engine.
List<String> engineStringListOption(LintRunRequest request, String key) {
  final raw = request.options[key];
  if (raw is! List) return const <String>[];
  return <String>[
    for (final entry in raw)
      if (entry is String && entry.isNotEmpty) entry,
  ];
}

/// The key under which a project passes raw command-line flags to one engine
/// (`perEngineOptions.<engine>.extraOptions`).
const String kExtraOptionsKey = 'extraOptions';
