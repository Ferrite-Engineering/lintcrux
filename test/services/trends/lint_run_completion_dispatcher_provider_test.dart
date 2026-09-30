// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/lint_run_completion_dispatcher.dart';
import 'package:lintcrux/services/trends/lint_run_completion_dispatcher_provider.dart';

class _CountingDispatcher implements LintRunCompletionDispatcher {
  int starts = 0;
  int stops = 0;

  @override
  void start() => starts++;

  @override
  void stop() => stops++;
}

void main() {
  group('lintRunCompletionDispatcherProvider', () {
    test(
      'default open-core provider returns NoopLintRunCompletionDispatcher',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final dispatcher = container.read(lintRunCompletionDispatcherProvider);
        expect(dispatcher, isA<NoopLintRunCompletionDispatcher>());
      },
    );

    test('reading the provider calls start()', () {
      final dispatcher = _CountingDispatcher();
      final container = ProviderContainer(
        overrides: [
          lintRunCompletionDispatcherProvider.overrideWith(
            (_) => dispatcher..start(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(lintRunCompletionDispatcherProvider);
      expect(dispatcher.starts, 1);
    });

    test('disposing the container calls stop()', () {
      final dispatcher = _CountingDispatcher();
      ProviderContainer(
          overrides: [
            lintRunCompletionDispatcherProvider.overrideWith((ref) {
              dispatcher.start();
              ref.onDispose(dispatcher.stop);
              return dispatcher;
            }),
          ],
        )
        ..read(lintRunCompletionDispatcherProvider)
        ..dispose();
      expect(dispatcher.stops, 1);
    });
  });

  group('NoopLintRunCompletionDispatcher', () {
    test('start and stop are no-ops', () {
      const dispatcher = NoopLintRunCompletionDispatcher();
      expect(dispatcher.start, returnsNormally);
      expect(dispatcher.stop, returnsNormally);
    });
  });
}
