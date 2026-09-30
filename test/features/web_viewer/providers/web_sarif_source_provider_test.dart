// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/web_viewer/providers/web_sarif_source_provider.dart';

void main() {
  group('WebSarifSourceNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('starts in the idle state', () {
      final state = container.read(webSarifSourceProvider);
      expect(state.source, isA<WebSarifSourceEmpty>());
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.violationCount, 0);
    });

    test('markLoading flips isLoading and clears any prior error', () {
      container
          .read(webSarifSourceProvider.notifier)
          .markFailed('previous failure');
      expect(
        container.read(webSarifSourceProvider).errorMessage,
        'previous failure',
      );

      container.read(webSarifSourceProvider.notifier).markLoading();
      final s = container.read(webSarifSourceProvider);
      expect(s.isLoading, isTrue);
      expect(s.errorMessage, isNull);
    });

    test('markLoaded records source + count and exits loading', () {
      container.read(webSarifSourceProvider.notifier)
        ..markLoading()
        ..markLoaded(
          const WebSarifSourceFile('report.sarif.json'),
          violationCount: 42,
        );
      final s = container.read(webSarifSourceProvider);
      expect(s.source, isA<WebSarifSourceFile>());
      expect((s.source as WebSarifSourceFile).name, 'report.sarif.json');
      expect(s.violationCount, 42);
      expect(s.isLoading, isFalse);
      expect(s.errorMessage, isNull);
    });

    test('markFailed sets the message and exits loading', () {
      container.read(webSarifSourceProvider.notifier)
        ..markLoading()
        ..markFailed('HTTP 404');
      final s = container.read(webSarifSourceProvider);
      expect(s.isLoading, isFalse);
      expect(s.errorMessage, 'HTTP 404');
    });

    test('URL source round-trips', () {
      container
          .read(webSarifSourceProvider.notifier)
          .markLoaded(
            WebSarifSourceUrl(Uri.parse('https://example.com/r.sarif')),
            violationCount: 7,
          );
      final s = container.read(webSarifSourceProvider);
      expect(s.source, isA<WebSarifSourceUrl>());
      expect(
        (s.source as WebSarifSourceUrl).url.toString(),
        'https://example.com/r.sarif',
      );
      expect(s.violationCount, 7);
    });
  });

  group('readSarifQueryParam', () {
    // The function returns null on non-web targets; this exercises
    // the contract on the desktop test runner.
    test('returns null on non-web targets', () {
      expect(readSarifQueryParam(), isNull);
    });
  });
}
