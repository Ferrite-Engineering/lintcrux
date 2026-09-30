// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/plugins/extra_localizations_delegates_provider.dart';

class _FakeDelegate extends LocalizationsDelegate<Object> {
  const _FakeDelegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<Object> load(Locale locale) async => const Object();
  @override
  bool shouldReload(covariant LocalizationsDelegate<Object> old) => false;
}

void main() {
  group('extraLocalizationsDelegatesProvider', () {
    test('open-core default is empty list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final delegates = container.read(extraLocalizationsDelegatesProvider);
      expect(delegates, isEmpty);
    });

    test('Pro overlay-style override is honored', () {
      const fake = _FakeDelegate();
      final container = ProviderContainer(
        overrides: [
          extraLocalizationsDelegatesProvider.overrideWithValue(
            const <LocalizationsDelegate<Object?>>[fake],
          ),
        ],
      );
      addTearDown(container.dispose);

      final delegates = container.read(extraLocalizationsDelegatesProvider);
      expect(delegates, hasLength(1));
      expect(delegates.single, same(fake));
    });
  });
}
