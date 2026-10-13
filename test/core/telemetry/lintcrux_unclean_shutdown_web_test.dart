// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/telemetry/lintcrux_telemetry_overrides.dart';

/// The browser build's unclean-shutdown detector.
///
/// The package's default detector reads `dart:io`'s `pid` when it is built,
/// which throws in a browser; `telemetryServiceProvider` builds it on the
/// first recorded event, so the web viewer's first event (opening a search
/// result, for one) failed with a ProviderException. Runs under
/// `tool/run_web_tests.sh`: only a real browser has no `pid`.
void main() {
  test('the web overrides give an inert detector that builds', () async {
    final container = ProviderContainer(overrides: lintcruxTelemetryOverrides);
    addTearDown(container.dispose);

    final detector = container.read(telemetryUncleanShutdownDetectorProvider);
    expect(detector, same(lintcruxWebUncleanShutdownDetector));
    expect(detector.supported, isFalse);
    expect(await detector.start(), isFalse);
  });
}
