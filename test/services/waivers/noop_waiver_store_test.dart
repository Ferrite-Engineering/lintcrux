// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/waiver_store.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/domain/models/waiver.dart';
import 'package:lintcrux/services/waivers/noop_waiver_store.dart';

void main() {
  group('NoopWaiverStore', () {
    test('all is permanently empty', () {
      final store = NoopWaiverStore();
      addTearDown(store.dispose);
      expect(store.all, isEmpty);
    });

    test('match always returns null', () {
      final store = NoopWaiverStore();
      addTearDown(store.dispose);
      const v = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'unused',
        location: SourceLocation(file: '/x.v', line: 1, column: 1),
      );
      expect(store.match(v), isNull);
    });

    test('add/update/delete throw UnsupportedError', () async {
      final store = NoopWaiverStore();
      addTearDown(store.dispose);
      final waiver = Waiver(
        id: 'id-1',
        ruleId: 'verilator/UNUSEDSIGNAL',
        filePath: '/x.v',
        reason: 'noisy',
        author: 'mfink',
        createdAt: DateTime.utc(2026, 5, 2),
      );
      expect(() => store.add(waiver), throwsA(isA<UnsupportedError>()));
      expect(() => store.update(waiver), throwsA(isA<UnsupportedError>()));
      expect(() => store.delete('id-1'), throwsA(isA<UnsupportedError>()));
    });

    test('loadFrom emits a WaiversReloaded(0) event', () async {
      final store = NoopWaiverStore();
      addTearDown(store.dispose);
      final events = <WaiverStoreEvent>[];
      final sub = store.events.listen(events.add);
      addTearDown(sub.cancel);
      await store.loadFrom(const <String>['/anywhere/.lintcrux-waivers.json']);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single, isA<WaiversReloaded>());
      expect((events.single as WaiversReloaded).count, 0);
    });

    test('save is a no-op', () async {
      final store = NoopWaiverStore();
      addTearDown(store.dispose);
      await expectLater(store.save(), completes);
    });
  });
}
