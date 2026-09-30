// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

Violation _v({
  required String engineId,
  required String localRule,
  required Severity severity,
  required String file,
  int line = 1,
  String message = 'msg',
}) {
  return Violation(
    engineId: engineId,
    ruleId: '$engineId/$localRule',
    severity: severity,
    message: message,
    location: SourceLocation(file: file, line: line, column: 1),
  );
}

void main() {
  group('InMemoryViolationStore', () {
    late InMemoryViolationStore store;

    setUp(() {
      store = InMemoryViolationStore();
    });

    tearDown(() async {
      await store.dispose();
    });

    test('starts empty', () {
      expect(store.all, isEmpty);
      expect(store.count, 0);
      expect(store.isEmpty, isTrue);
      expect(store.byEngineOf('verilator'), isEmpty);
      expect(store.bySeverity, isEmpty);
      expect(store.byEngine, isEmpty);
      expect(store.byRule, isEmpty);
      expect(store.byFile, isEmpty);
    });

    test('count / isEmpty / byEngineOf are O(1) views over the live set', () {
      final a = _v(
        engineId: 'verilator',
        localRule: 'UNUSEDSIGNAL',
        severity: Severity.warning,
        file: '/abs/proj/foo.v',
      );
      final b = _v(
        engineId: 'verilator',
        localRule: 'WIDTHTRUNC',
        severity: Severity.warning,
        file: '/abs/proj/bar.v',
      );
      final c = _v(
        engineId: 'verible',
        localRule: 'STYLE',
        severity: Severity.note,
        file: '/abs/proj/foo.v',
      );
      store
        ..replaceFromEngine('verilator', [a, b])
        ..replaceFromEngine('verible', [c]);

      // Agree with the copying getters they replace, without materializing.
      expect(store.count, store.all.length);
      expect(store.count, 3);
      expect(store.isEmpty, isFalse);
      expect(store.byEngineOf('verilator'), store.byEngine['verilator']);
      expect(store.byEngineOf('verilator'), hasLength(2));
      // Unknown engine → empty (not null).
      expect(store.byEngineOf('nope'), isEmpty);
      // The returned view is unmodifiable.
      expect(
        () => store.byEngineOf('verilator').add(c),
        throwsUnsupportedError,
      );
    });

    test('replaceFromEngine inserts and indices reflect every dimension', () {
      final a = _v(
        engineId: 'verilator',
        localRule: 'UNUSEDSIGNAL',
        severity: Severity.warning,
        file: '/abs/proj/foo.v',
      );
      final b = _v(
        engineId: 'verilator',
        localRule: 'WIDTHTRUNC',
        severity: Severity.warning,
        file: '/abs/proj/bar.v',
      );
      final c = _v(
        engineId: 'verible',
        localRule: 'STYLE',
        severity: Severity.note,
        file: '/abs/proj/foo.v',
      );

      store
        ..replaceFromEngine('verilator', [a, b])
        ..replaceFromEngine('verible', [c]);

      expect(store.all, hasLength(3));
      expect(store.bySeverity[Severity.warning], hasLength(2));
      expect(store.bySeverity[Severity.note], hasLength(1));
      expect(store.byEngine['verilator'], hasLength(2));
      expect(store.byEngine['verible'], hasLength(1));
      expect(store.byRule['verilator/UNUSEDSIGNAL'], hasLength(1));
      expect(store.byRule['verible/STYLE'], hasLength(1));
      expect(store.byFile['/abs/proj/foo.v'], hasLength(2));
      expect(store.byFile['/abs/proj/bar.v'], hasLength(1));
    });

    test('replaceFromEngine wipes only the affected engine', () {
      final a = _v(
        engineId: 'verilator',
        localRule: 'X',
        severity: Severity.error,
        file: '/a.v',
      );
      final b = _v(
        engineId: 'verible',
        localRule: 'Y',
        severity: Severity.warning,
        file: '/b.v',
      );

      store
        ..replaceFromEngine('verilator', [a])
        ..replaceFromEngine('verible', [b])
        ..replaceFromEngine('verilator', <Violation>[]); // wipe verilator

      expect(store.all, [b]);
      expect(store.byEngine.containsKey('verilator'), isFalse);
      expect(store.byEngine['verible'], hasLength(1));
      expect(store.byRule.containsKey('verilator/X'), isFalse);
      expect(store.byFile.containsKey('/a.v'), isFalse);
    });

    test("replaceFromEngine swaps an engine's violation set in place", () {
      final v1 = _v(
        engineId: 'slang',
        localRule: 'A',
        severity: Severity.warning,
        file: '/a.sv',
      );
      final v2 = _v(
        engineId: 'slang',
        localRule: 'B',
        severity: Severity.error,
        file: '/b.sv',
      );

      store
        ..replaceFromEngine('slang', [v1])
        ..replaceFromEngine('slang', [v2]);

      expect(store.all, [v2]);
      expect(store.byEngine['slang'], [v2]);
      expect(store.byRule.containsKey('slang/A'), isFalse);
      expect(store.byRule['slang/B'], [v2]);
    });

    test('addStreaming + completeStreaming emit ordered events', () async {
      final v1 = _v(
        engineId: 'verilator',
        localRule: 'X',
        severity: Severity.warning,
        file: '/x.v',
      );
      final v2 = _v(
        engineId: 'verilator',
        localRule: 'Y',
        severity: Severity.warning,
        file: '/y.v',
      );

      final collected = <ViolationStoreEvent>[];
      final sub = store.events.listen(collected.add);

      store
        ..addStreaming(v1)
        ..addStreaming(v2)
        ..completeStreaming('verilator');

      // Let the broadcast controller deliver.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(collected, hasLength(3));
      expect(collected[0], isA<ViolationAdded>());
      expect(collected[1], isA<ViolationAdded>());
      expect(collected[2], isA<RunCompleted>());
      expect((collected[2] as RunCompleted).engineId, 'verilator');

      // Both streamed violations should be visible across every index.
      expect(store.all, [v1, v2]);
      expect(store.byEngine['verilator'], hasLength(2));
    });

    test('filter — empty filter returns all by default', () {
      final a = _v(
        engineId: 'verilator',
        localRule: 'X',
        severity: Severity.warning,
        file: '/a.v',
      );
      final b = _v(
        engineId: 'verible',
        localRule: 'Y',
        severity: Severity.note,
        file: '/b.v',
      );
      store
        ..replaceFromEngine('verilator', [a])
        ..replaceFromEngine('verible', [b]);

      final out = store.filter(ViolationFilter.empty);
      expect(out, containsAll([a, b]));
      expect(out, hasLength(2));
    });

    test('filter — narrows by severity, engine, rule substring, glob', () {
      final hits = [
        _v(
          engineId: 'verilator',
          localRule: 'UNUSEDSIGNAL',
          severity: Severity.warning,
          file: '/proj/rtl/foo.v',
        ),
        _v(
          engineId: 'verilator',
          localRule: 'WIDTHTRUNC',
          severity: Severity.warning,
          file: '/proj/rtl/bar.v',
        ),
        _v(
          engineId: 'verible',
          localRule: 'STYLE_X',
          severity: Severity.note,
          file: '/proj/tb/baz.sv',
        ),
        _v(
          engineId: 'verilator',
          localRule: 'PINMISSING',
          severity: Severity.error,
          file: '/proj/rtl/qux.v',
        ),
      ];
      store
        ..replaceFromEngine('verilator', [hits[0], hits[1], hits[3]])
        ..replaceFromEngine('verible', [hits[2]]);

      // Severity filter.
      expect(
        store.filter(const ViolationFilter(severities: {Severity.error})),
        [hits[3]],
      );

      // Engine filter.
      final ver = store.filter(
        const ViolationFilter(engineIds: {'verible'}),
      );
      expect(ver, [hits[2]]);

      // Rule substring (case-insensitive, matches rule id and message).
      final unused = store.filter(
        const ViolationFilter(ruleSubstring: 'unused'),
      );
      expect(unused, [hits[0]]);

      // File glob — `/proj/rtl/*.v` should hit three verilator files.
      final rtl = store.filter(
        const ViolationFilter(fileGlob: '/proj/rtl/*.v'),
      );
      expect(rtl, hasLength(3));
      expect(rtl, containsAll([hits[0], hits[1], hits[3]]));

      // `**` matches multiple segments.
      final allV = store.filter(
        const ViolationFilter(fileGlob: '/proj/**.v'),
      );
      expect(allV, hasLength(3));
    });

    test(
      'filter — suppressed violations excluded by default, included on opt-in',
      () {
        final raw = _v(
          engineId: 'verilator',
          localRule: 'WIDTHTRUNC',
          severity: Severity.warning,
          file: '/a.v',
        );
        // Build a copy that is suppressed via a real Waiver. The store
        // only checks `isSuppressed`; the waiver's shape is irrelevant to
        // the store's behavior.
        final suppressed = raw.copyWith(
          suppression: Waiver(
            id: 'w1',
            ruleId: raw.ruleId,
            filePath: raw.location.file,
            reason: 'irrelevant for store',
            author: 'test',
            createdAt: DateTime(2026),
          ),
        );
        store.replaceFromEngine('verilator', [raw, suppressed]);

        final activeOnly = store.filter(ViolationFilter.empty);
        expect(activeOnly, [raw]);

        final withSuppressed = store.filter(
          const ViolationFilter(includeSuppressed: true),
        );
        expect(withSuppressed, containsAll([raw, suppressed]));
      },
    );

    test(
      'lastRemovalScans instrumentation resets and counts removal visits',
      () {
        final a = _v(
          engineId: 'verilator',
          localRule: 'X',
          severity: Severity.error,
          file: '/a.v',
        );
        final b = _v(
          engineId: 'verilator',
          localRule: 'Y',
          severity: Severity.warning,
          file: '/a.v',
        );

        // First load has nothing to remove: the counter stays zero.
        store.replaceFromEngine('verilator', [a, b]);
        expect(store.lastRemovalScans, 0);

        // Wholesale replacement removes the two prior rows. Removal visits
        // `_all` (2) + one bucket per distinct severity/rule/file. Here:
        // 2 severities (1+1), 2 rules (1+1), 1 file (2) => 2 + 2 + 2 + 2 = 8.
        store.replaceFromEngine('verilator', [
          _v(
            engineId: 'verilator',
            localRule: 'Z',
            severity: Severity.note,
            file: '/b.v',
          ),
        ]);
        expect(store.lastRemovalScans, 8);

        // The counter is reset per call, not accumulated across calls.
        store.replaceFromEngine('slang', const []);
        expect(store.lastRemovalScans, 0);

        // The partial path instruments removal the same way.
        store.replacePartialFromEngine('verilator', {'/b.v'}, const []);
        expect(store.lastRemovalScans, greaterThan(0));
      },
    );

    test('exposed index maps are unmodifiable views', () {
      final a = _v(
        engineId: 'verilator',
        localRule: 'X',
        severity: Severity.error,
        file: '/a.v',
      );
      store.replaceFromEngine('verilator', [a]);

      expect(
        () => store.bySeverity[Severity.error] = const [],
        throwsUnsupportedError,
      );
      expect(
        () => store.byEngine['verilator']!.add(a),
        throwsUnsupportedError,
      );
      expect(
        () => store.all.add(a),
        throwsUnsupportedError,
      );
    });
  });
}
