// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/waivers/noop_waiver_store.dart';
import 'package:lintcrux/services/waivers/waiver_store_provider.dart';

void main() {
  test('waiverStoreProvider default binding is a NoopWaiverStore', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(waiverStoreProvider), isA<NoopWaiverStore>());
  });
}
