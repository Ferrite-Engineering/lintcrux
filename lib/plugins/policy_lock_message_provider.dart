// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolves, at a [BuildContext] below the app's localizations, the sentence
/// every policy-locked control shows: "your organization's policy file sets
/// this, so it can't be changed here; ask your administrator".
///
/// `app.dart` mounts `CruxPolicyLockScope` once, in `MaterialApp.builder`
/// above the root navigator, and reads this to fill it, so a locked control
/// in a dialog reads the same sentence as one in Settings. Open core ships
/// the seam as `null`, which leaves the scope on the shared English default:
/// the licence panel whose strings carry the localized sentence exists only
/// in the Pro overlay, and that overlay binds this to its strings adapter.
///
/// A function of the context rather than a string, because the sentence is
/// localized and the locale is only known below `MaterialApp`.
final Provider<String Function(BuildContext context)?>
policyLockMessageProvider = Provider<String Function(BuildContext context)?>(
  (ref) => null,
);
