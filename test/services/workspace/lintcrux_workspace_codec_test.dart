// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lintcrux_tab_payload.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LintcruxWorkspaceCodec', () {
    const codec = LintcruxWorkspaceCodec();

    test('round-trips a fully-populated payload', () {
      const original = LintcruxTabPayload(
        projectPath: '/p/release.lintcrux',
        selectedRuleId: 'verilator/UNUSED',
        activeSeverities: {Severity.error, Severity.warning},
        activeEngineIds: {'verilator', 'slang'},
        ruleSubstring: 'unused',
        fileGlob: 'src/**.sv',
        sortColumn: ViolationTableColumn.rule,
        sortAscending: false,
        savedFilterPresetName: 'release-readiness',
        viewMode: ViewMode.detailFocused,
        sessionExportPath: '/exports/release.lintcrux-session',
      );
      final j = codec.payloadToJson(original);
      final restored = codec.payloadFromJson(j);
      expect(restored, equals(original));
    });

    test('round-trips a minimal payload with constructor defaults', () {
      const original = LintcruxTabPayload(projectPath: '/p/min.lintcrux');
      final j = codec.payloadToJson(original);
      final restored = codec.payloadFromJson(j);
      expect(restored, equals(original));
    });

    test('payloadToJson omits null optional fields', () {
      const payload = LintcruxTabPayload(projectPath: '/p/a.lintcrux');
      final j = codec.payloadToJson(payload);
      expect(j.containsKey('selectedRuleId'), isFalse);
      expect(j.containsKey('savedFilterPresetName'), isFalse);
      expect(j.containsKey('sessionExportPath'), isFalse);
      expect(j['projectPath'], '/p/a.lintcrux');
    });

    test('payloadFromJson rejects missing projectPath', () {
      expect(
        () => codec.payloadFromJson(<String, Object?>{}),
        throwsA(isA<WorkspaceInvariantException>()),
      );
    });

    test('payloadFromJson rejects non-string projectPath', () {
      expect(
        () => codec.payloadFromJson(<String, Object?>{'projectPath': 42}),
        throwsA(isA<WorkspaceInvariantException>()),
      );
    });

    test('payloadFromJson rejects empty-string projectPath', () {
      expect(
        () => codec.payloadFromJson(<String, Object?>{'projectPath': ''}),
        throwsA(isA<WorkspaceInvariantException>()),
      );
    });

    test('payloadFromJson silently drops unknown severity strings', () {
      final payload = codec.payloadFromJson(<String, Object?>{
        'projectPath': '/p/a.lintcrux',
        'activeSeverities': ['error', 'not-a-severity', 'warning'],
      });
      expect(payload.activeSeverities, {Severity.error, Severity.warning});
    });

    test(
      'payloadFromJson silently drops non-string entries in list fields',
      () {
        final payload = codec.payloadFromJson(<String, Object?>{
          'projectPath': '/p/a.lintcrux',
          'activeEngineIds': ['verilator', 42, true, 'verible'],
          'activeSeverities': ['error', 99],
        });
        expect(payload.activeEngineIds, {'verilator', 'verible'});
        expect(payload.activeSeverities, {Severity.error});
      },
    );

    test('payloadFromJson silently ignores unknown top-level keys', () {
      final payload = codec.payloadFromJson(<String, Object?>{
        'projectPath': '/p/a.lintcrux',
        'futureField': 'irrelevant',
        'anotherUnknown': 42,
      });
      expect(payload.projectPath, '/p/a.lintcrux');
    });

    test('payloadFromJson falls back to defaults on wrong-typed fields', () {
      final payload = codec.payloadFromJson(<String, Object?>{
        'projectPath': '/p/a.lintcrux',
        'ruleSubstring': 42,
        'fileGlob': true,
        'sortColumn': 'not-a-column',
        'sortAscending': 'not-a-bool',
        'viewMode': 'not-a-view',
      });
      expect(payload.ruleSubstring, '');
      expect(payload.fileGlob, '');
      expect(payload.sortColumn, ViolationTableColumn.severity);
      expect(payload.sortAscending, isTrue);
      expect(payload.viewMode, ViewMode.table);
    });

    test('displayNameFor strips the .lintcrux extension', () {
      expect(
        codec.displayNameFor(
          const LintcruxTabPayload(projectPath: '/proj/cpu_core.lintcrux'),
        ),
        'cpu_core',
      );
    });

    test('displayNameFor returns basename when no extension', () {
      expect(
        codec.displayNameFor(
          const LintcruxTabPayload(projectPath: '/proj/cpu_core'),
        ),
        'cpu_core',
      );
    });

    test('schemaVersion is 1', () {
      expect(codec.schemaVersion, 1);
    });

    test(
      'Workspace document round-trips through codec via fromJson/toJson',
      () {
        // The framework's Workspace.fromJson / toJson are exercised here
        // to confirm the codec composes with the workspace-level schema.
        final pane = WorkspacePane(id: PaneId.generate());
        final tab = WorkspaceTab<LintcruxTabPayload>(
          id: TabId.generate(),
          displayName: codec.displayNameFor(
            const LintcruxTabPayload(projectPath: '/p/cpu_core.lintcrux'),
          ),
          paneId: pane.id,
          payload: const LintcruxTabPayload(
            projectPath: '/p/cpu_core.lintcrux',
            activeEngineIds: {'verilator'},
          ),
        );
        final ws = Workspace<LintcruxTabPayload>(
          tabs: [tab],
          panes: [pane],
          activePaneId: pane.id,
        );
        final encoded = ws.toJson(codec);
        final restored = Workspace<LintcruxTabPayload>.fromJson(encoded, codec);
        expect(restored, equals(ws));
      },
    );
  });

  // Tab dedupe (beta regression): CLI-opening a project already in the restored
  // workspace appended a duplicate tab per launch, unbounded (seven identical
  // `riscv-soc` tabs observed). `identityOf` is what `openTab(dedupe: true)`
  // consults; every spelling below is one a real launch produces.
  group('LintcruxWorkspaceCodec.identityOf', () {
    const codec = LintcruxWorkspaceCodec();

    late Directory tempDir;
    late String projectPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lintcrux_identity_');
      projectPath = p.join(tempDir.path, 'riscv-soc.lintcrux');
      File(projectPath).writeAsStringSync('{}');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } on FileSystemException {
          // Best-effort cleanup.
        }
      }
    });

    String? identity(String path) =>
        codec.identityOf(LintcruxTabPayload(projectPath: path));

    test('an empty project path has no identity', () {
      // The empty-canvas tab. Folding every blank payload together would
      // make a second blank tab impossible to open.
      expect(identity(''), isNull);
    });

    test('a path is its own identity', () {
      expect(identity(projectPath), isNotNull);
      expect(identity(projectPath), identity(projectPath));
    });

    test('a relative path matches the absolute one', () {
      final relative = p.relative(projectPath);
      expect(identity(relative), identity(projectPath));
    });

    test('a `..` segment collapses', () {
      final viaParent = p.join(
        tempDir.path,
        'sub',
        '..',
        'riscv-soc.lintcrux',
      );
      expect(identity(viaParent), identity(projectPath));
    });

    test('a trailing separator is stripped', () {
      // A directory-ish spelling of the same entity; the key must not carry
      // the separator into the comparison.
      final dirPath = tempDir.path;
      expect(
        identity('$dirPath${Platform.pathSeparator}'),
        identity(dirPath),
      );
    });

    test('a symlinked path matches its target', () {
      final linkDir = p.join(tempDir.path, 'link');
      Link(linkDir).createSync(tempDir.path);
      final viaLink = p.join(linkDir, 'riscv-soc.lintcrux');
      expect(identity(viaLink), identity(projectPath));
    });

    test('case folding follows the platform filesystem', () {
      final upper = projectPath.toUpperCase();
      if (Platform.isMacOS || Platform.isWindows) {
        // `identityOf` resolves symlinks, and an upper-cased path resolves on
        // a case-insensitive volume, so both sides land on the same key.
        expect(identity(upper), identity(projectPath));
      } else {
        expect(identity(upper), isNot(identity(projectPath)));
      }
    });

    test('two different projects have different identities', () {
      final other = p.join(tempDir.path, 'other.lintcrux');
      File(other).writeAsStringSync('{}');
      expect(identity(other), isNot(identity(projectPath)));
    });

    test('identity ignores mutable per-session payload fields', () {
      // The package requires identity to be stable across launches: it is
      // compared against tabs rehydrated from disk, whose filter/sort state
      // has since moved on.
      const a = LintcruxTabPayload(projectPath: '/p/a.lintcrux');
      const b = LintcruxTabPayload(
        projectPath: '/p/a.lintcrux',
        selectedRuleId: 'verilator/UNUSED',
        activeSeverities: {Severity.error},
        ruleSubstring: 'clk',
        viewMode: ViewMode.detailFocused,
      );
      expect(codec.identityOf(a), codec.identityOf(b));
    });
  });
}
