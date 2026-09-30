// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/waiver_store.dart';

void main() {
  group('WaiverStoreEvent', () {
    test('sealed hierarchy admits an exhaustive switch', () {
      const WaiverStoreEvent ev1 = WaiverDeleted('w-1');
      const WaiverStoreEvent ev2 = WaiversReloaded(5);
      String describe(WaiverStoreEvent e) => switch (e) {
        WaiverAdded(:final waiver) => 'add ${waiver.id}',
        WaiverUpdated(:final waiver) => 'upd ${waiver.id}',
        WaiverDeleted(:final waiverId) => 'del $waiverId',
        WaiversReloaded(:final count) => 'rel $count',
      };
      expect(describe(ev1), 'del w-1');
      expect(describe(ev2), 'rel 5');
    });
  });
}
