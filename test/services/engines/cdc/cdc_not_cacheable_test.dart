// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/cdc/cdc_engine.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';

/// CDC must never be served from the lint cache.
///
/// Found the hard way, during a manual walkthrough. A user ran CDC, got a
/// clean result, we shipped a change to the analysis, they rebuilt, re-ran —
/// and got the same clean result, because the cache replayed it. The run
/// reported `Completed` each time. Nothing anywhere said "this came from
/// cache".
///
/// The key is `(source fingerprints, request config, engine version)`, and for
/// CDC the engine version is *yosys's*, because that is the only binary
/// involved. The analysis is Dart in this repo, so improving it cannot
/// invalidate anything.
///
/// The second reason is worse. The Pro layer reads `cdc.yaml` from beside the
/// sources, and it is not a source file — so the key is blind to it. A user
/// edits their constraints, re-runs, and the findings do not move. The feature
/// looks broken while working exactly as designed.
///
/// Both failures are silent. Hence a test rather than a comment.
void main() {
  test('the CDC engine declares itself non-cacheable', () {
    expect(
      CdcEngine().capabilities.cacheable,
      isFalse,
      reason:
          'a cached CDC result cannot be invalidated by shipping a better '
          'analysis, nor by the user editing cdc.yaml',
    );
  });

  test('the engines that ARE cacheable are the binary-backed ones', () {
    // The complement, so the flag does not quietly spread. Every other engine
    // is a versioned external binary reading only the files it is handed,
    // which is exactly the case the cache key models correctly.
    final registry = defaultEngineRegistry();
    for (final id in registry.engineIds) {
      final cacheable = registry.get(id)!.capabilities.cacheable;
      expect(
        cacheable,
        id == 'cdc' ? isFalse : isTrue,
        reason:
            '`$id` cacheable=$cacheable — if this engine grew an input outside '
            'sourceFiles, or moved its analysis in-process, the cache key no '
            'longer describes it',
      );
    }
  });
}
