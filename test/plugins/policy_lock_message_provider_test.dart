// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/policy_lock_message_provider.dart';

void main() {
  group('policyLockMessageProvider', () {
    test('open core resolves no sentence, leaving the shared default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(policyLockMessageProvider), isNull);
    });

    test('an overlay override is what the app reads', () {
      String resolve(BuildContext context) => 'locked by policy';
      final container = ProviderContainer(
        overrides: [policyLockMessageProvider.overrideWithValue(resolve)],
      );
      addTearDown(container.dispose);
      expect(container.read(policyLockMessageProvider), same(resolve));
    });
  });
}
