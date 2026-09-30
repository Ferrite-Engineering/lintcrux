// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_project/crux_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';

void main() {
  group('OpenProjectResult', () {
    test('OpenProjectSuccess carries the loaded project', () {
      const project = LintProject(
        name: 'demo',
        rootPath: '/work/demo',
      );
      const result = OpenProjectSuccess(project);
      expect(result.project.name, 'demo');
      expect(result, isA<OpenProjectResult>());
    });

    test('OpenProjectFailure carries the message', () {
      const result = OpenProjectFailure('boom');
      expect(result.message, 'boom');
      expect(result, isA<OpenProjectResult>());
    });

    test('OpenProjectSuccess carries the legacy manifest rename, when any', () {
      const project = LintProject(name: 'demo', rootPath: '/work/demo');
      expect(const OpenProjectSuccess(project).legacyManifestRenameTo, isNull);
      expect(
        const OpenProjectSuccess(
          project,
          legacyManifestRenameTo: 'demo.crux-project',
        ).legacyManifestRenameTo,
        'demo.crux-project',
      );
    });

    test('OpenProjectManifestAmbiguous is a failure carrying the conflict', () {
      const error = CruxProjectAmbiguousException(
        directory: '/work/demo',
        candidates: <String>[
          '/work/demo/a.crux-project',
          '/work/demo/b.crux-project',
        ],
      );
      final result = OpenProjectManifestAmbiguous(error);
      expect(result, isA<OpenProjectFailure>());
      expect(result.error, same(error));
      expect(result.message, error.message);
    });

    test('sealed hierarchy switches exhaustively', () {
      const OpenProjectResult result = OpenProjectFailure('nope');
      final label = switch (result) {
        OpenProjectSuccess() => 'success',
        OpenProjectFailure(:final message) => message,
      };
      expect(label, 'nope');
    });
  });

  // NOTE: the project-open orchestration itself (read + parse + install
  // into a per-tab container + kick a run) lives in
  // `OpenProjectInWorkspace` and is covered by
  // `test/features/workspace/services/open_project_in_workspace_test.dart`.
  // There is deliberately no root-container project loader anymore —
  // see the note in `open_project_service.dart`.
}
