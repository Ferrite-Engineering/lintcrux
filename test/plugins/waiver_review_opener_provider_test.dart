// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/waiver_review_opener_provider.dart';

void main() {
  group('waiverReviewOpenerProvider', () {
    test('open-core default is null, not a no-op function', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // A null default is what lets the dispatcher tell "no
      // implementation installed" apart from "the opener ran and did
      // nothing", which is what keeps the menu entry from becoming a
      // silent dead item in open-core builds.
      expect(container.read(waiverReviewOpenerProvider), isNull);
    });

    test('Pro overlay-style override is honored', () {
      var called = 0;
      final container = ProviderContainer(
        overrides: [
          waiverReviewOpenerProvider.overrideWithValue(
            (_) => called++,
          ),
        ],
      );
      addTearDown(container.dispose);

      final opener = container.read(waiverReviewOpenerProvider);
      expect(opener, isNotNull);
      // Pass null-equivalent BuildContext; the override under test
      // ignores its argument and just bumps the counter.
      unawaited(Future.value(opener!(_AnyContext())));
      expect(called, 1);
    });
  });
}

/// Bare-bones BuildContext for the unit test of the override path.
class _AnyContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
