// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Two ways to tell a widget test "this installation has already accepted the
/// current EULA". Pick by whether the test spreads the production overrides.
///
/// Without one of them `CruxEulaGate` mounts a blocking modal over everything,
/// which is exactly right in production and wrong for a test of anything else.
/// Its `ModalBarrier` swallows taps, so the symptom is usually a confirm dialog
/// that will not dismiss rather than an obvious "the agreement is in the way".
///
/// Seeding acceptance is honest here because the gate is not what these tests
/// are about — the agreement has its own tests in `crux_eula`, and
/// `test/static/eula_gate_reachability_test.dart` is what stops these seeds
/// quietly hiding an un-mounted gate.
library;

import 'package:crux_eula/crux_eula.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// For a test that **does** spread `lintcruxAppOverrides` (which already binds
/// `cruxEulaStorageProvider`, and Riverpod rejects a second override of the
/// same provider in one container). Merge into the preference mock:
///
/// ```dart
/// SharedPreferences.setMockInitialValues(<String, Object>{
///   ...kEulaAcceptedPrefs,
/// });
/// ```
///
/// Going through the preference also exercises the real `LintcruxEulaStorage`,
/// so a broken adapter still shows up.
const Map<String, Object> kEulaAcceptedPrefs = <String, Object>{
  kCruxEulaAcceptedVersionKey: kCruxEulaVersion,
};

/// For a test that mounts the app **without** the production overrides, where
/// `cruxEulaStorageProvider` is still the package's in-memory default. Add it
/// to the scope's own `overrides` list.
Override eulaAcceptedOverride() => cruxEulaStorageProvider.overrideWithValue(
  InMemoryCruxEulaStorage(kEulaAcceptedPrefs.cast<String, String>()),
);
