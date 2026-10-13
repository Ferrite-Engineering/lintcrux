// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_bookmark_store.dart';
import 'package:lintcrux/domain/models/bookmarked_violation.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/bookmarks/bookmark_freshness.dart';
import 'package:lintcrux/services/bookmarks/json_file_violation_bookmark_store.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_lookup_provider.dart';
import 'package:lintcrux/services/bookmarks/violation_bookmark_store_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/run/lint_run_lifecycle.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late JsonFileViolationBookmarkStore store;
  late InMemoryViolationStore violations;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lintcrux_bookmark_fresh_');
    store = JsonFileViolationBookmarkStore(
      File(p.join(tmp.path, kViolationBookmarksFileName)),
      projectRoot: tmp.path,
    );
    await store.load();
    violations = InMemoryViolationStore();
  });

  tearDown(() async {
    await violations.dispose();
    await store.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Violation violation({Waiver? suppression}) => Violation(
    engineId: 'verilator',
    ruleId: 'verilator/UNUSEDSIGNAL',
    severity: Severity.warning,
    message: 'unused signal foo',
    location: SourceLocation(
      file: p.join(tmp.path, 'rtl', 'a.sv'),
      line: 10,
      column: 1,
    ),
    suppression: suppression,
  );

  BookmarkedViolation bookmark(String id, String fingerprint) =>
      BookmarkedViolation(
        id: id,
        fingerprint: fingerprint,
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: p.join(tmp.path, 'rtl', 'a.sv'),
        lineNumber: 10,
        snippet: 'unused signal foo',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );

  String firingFingerprint() =>
      computeBookmarkFingerprint(violation(), projectRoot: tmp.path);

  /// A container modelling a workspace tab with the temp project open,
  /// [store] as its bookmark store and [violations] as its run output.
  /// The freshness notifier is kept alive for the container's lifetime.
  ProviderContainer tab() {
    final container = ProviderContainer(
      overrides: [
        violationBookmarkStoreProvider.overrideWithValue(store),
        violationStoreProvider.overrideWithValue(violations),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(currentProjectProvider.notifier)
        .load(LintProject(name: 'x', rootPath: tmp.path));
    final sub = container.listen(bookmarkFreshnessProvider, (_, _) {});
    addTearDown(sub.close);
    return container;
  }

  Future<void> completeRun(ProviderContainer container) async {
    final bus = container.read(lintRunLifecycleBusProvider)
      ..emit(const LintRunLifecycleEvent(isRunning: true));
    await pumpEventQueue();
    bus.emit(
      LintRunLifecycleEvent(
        isRunning: false,
        finishedAt: DateTime.utc(2026, 3, 4, 5, 6, 7),
      ),
    );
    await pumpEventQueue();
  }

  Future<Map<String, BookmarkedViolation>> byId() async => {
    for (final b in await store.listAll()) b.id: b,
  };

  test('is null before any run completes', () {
    final container = tab();
    expect(container.read(bookmarkFreshnessProvider), isNull);
  });

  test('a completed run publishes its id and refreshes only the bookmarks '
      'it fired', () async {
    await store.addOrUpdate(bookmark('bm-firing', firingFingerprint()));
    await store.addOrUpdate(bookmark('bm-quiet', 'fp-never-fires'));
    violations.replaceFromEngine('verilator', [violation()]);
    final container = tab();

    final wrote = store.changed.first;
    await completeRun(container);
    await wrote.timeout(const Duration(seconds: 5));

    final runId = container.read(bookmarkFreshnessProvider);
    expect(runId, isNotNull);
    final all = await byId();
    expect(all['bm-firing']?.lastSeenRunId, runId);
    expect(all['bm-quiet']?.lastSeenRunId, isNull);
  });

  test('a suppressed violation does not refresh its bookmark', () async {
    await store.addOrUpdate(bookmark('bm-1', firingFingerprint()));
    violations.replaceFromEngine('verilator', [
      violation(
        suppression: Waiver(
          id: 'w1',
          ruleId: 'verilator/UNUSEDSIGNAL',
          filePath: p.join(tmp.path, 'rtl', 'a.sv'),
          reason: 'reset-only signal',
          author: 'tester',
          createdAt: DateTime.utc(2026),
        ),
      ),
    ]);
    final container = tab();

    await completeRun(container);

    expect(container.read(bookmarkFreshnessProvider), isNotNull);
    expect((await byId())['bm-1']?.lastSeenRunId, isNull);
  });

  test('an idle event not preceded by a running one does nothing', () async {
    await store.addOrUpdate(bookmark('bm-1', firingFingerprint()));
    violations.replaceFromEngine('verilator', [violation()]);
    final container = tab();

    container
        .read(lintRunLifecycleBusProvider)
        .emit(
          LintRunLifecycleEvent(
            isRunning: false,
            finishedAt: DateTime.utc(2026, 3, 4),
          ),
        );
    await pumpEventQueue();

    expect(container.read(bookmarkFreshnessProvider), isNull);
    expect((await byId())['bm-1']?.lastSeenRunId, isNull);
  });

  test('with no project (the no-op store) recordRun still publishes the '
      'run id', () {
    final container = ProviderContainer(
      overrides: [violationStoreProvider.overrideWithValue(violations)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(bookmarkFreshnessProvider, (_, _) {});
    addTearDown(sub.close);
    expect(
      container.read(violationBookmarkStoreProvider),
      isA<NoopViolationBookmarkStore>(),
    );

    container.read(bookmarkFreshnessProvider.notifier).recordRun('run-1');

    expect(container.read(bookmarkFreshnessProvider), 'run-1');
  });
}
