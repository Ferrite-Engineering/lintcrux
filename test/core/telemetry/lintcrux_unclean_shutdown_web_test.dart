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
/// `telemetryServiceProvider` builds the package's default detector on the
/// first recorded event, so a detector that touched `dart:io` when built
/// failed the web viewer's first event (opening a search result, for one)
/// with a ProviderException. The default is inert in a browser, and LintCrux
/// binds no detector of its own. Runs under `tool/run_web_tests.sh`: only a
/// real browser has no `pid`.
void main() {
  test('the web build reads the default detector, inert', () async {
    final container = ProviderContainer(overrides: lintcruxTelemetryOverrides);
    addTearDown(container.dispose);

    final detector = container.read(telemetryUncleanShutdownDetectorProvider);
    expect(detector, same(TelemetryUncleanShutdownDetector.instance));
    expect(detector.supported, isFalse);
    expect(await detector.start(), isFalse);
    expect(detector.marker, isNull);
  });
}
