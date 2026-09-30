// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Signature shared by every open-core → Pro action-opener seam.
///
/// An opener mounts a screen, dialog, or Pro-only side effect for one
/// [LintcruxAction]. The providers that carry it are declared nullable
/// (`Provider<ProActionOpener?>`) and default to `null` in open-core:
/// `null` means "no implementation is installed in this build".
///
/// The null default is load-bearing, not a convenience. A no-op default
/// is indistinguishable at the call site from an opener that ran and
/// chose to do nothing, so the dispatcher cannot tell the two apart and
/// the menu / palette entry becomes a silent dead item. With `null` the
/// dispatcher detects the missing implementation and gives the user
/// localized feedback keyed off the action's `requiredTier`
/// (see `_runOpener` in `app.dart`).
///
/// Tier semantics are the action's, not the opener's: an opener that is
/// null because the Pro overlay isn't installed produces the "requires
/// LintCrux Pro" snack for a Pro-tier action, and the neutral "not
/// available yet" snack for an action whose `requiredTier` is
/// open-core.
typedef ProActionOpener = FutureOr<void> Function(BuildContext context);
