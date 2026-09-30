// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One Pro-contributed widget rendered in the violation table's top
/// action row (above the filter chips).
///
/// The violation table renders the contributions returned by
/// [violationTableTopActionsProvider] as a horizontal `Row` between
/// the filter-preset dropdown and the filter chips. Each entry is a
/// pre-built widget (typically a `ConsumerWidget` that reads its own
/// providers and renders its own tier badge), so the open-core table
/// does not need to know what each contribution does.
///
/// Use this seam for tier-gated controls that visually belong with
/// the violation table but require Pro/Enterprise functionality:
/// baseline set/clear buttons, the baseline view-mode toggle, the
/// active baseline status chip, future trend chart entry points,
/// etc. Each contribution is responsible for its own tier badging
/// and feature-gate check.
typedef ViolationTableTopActionBuilder =
    Widget Function(
      BuildContext context,
      WidgetRef ref,
    );

/// Open-core extension point through which the Pro overlay
/// contributes additional widgets to the violation table's top action
/// row.
///
/// Default returns an empty list so the open-core build's violation
/// table renders exactly the open-core chrome (filter preset
/// dropdown, filter chips, header, list, status bar). The Pro overlay
/// overrides this provider via `proOverrides` with a list of three
/// contributions: the set/clear baseline toolbar, the view-mode
/// toggle, and the active baseline status chip.
///
/// Consumers (the `ViolationTable` widget) call each builder inside
/// its own `Builder` so the contributions can watch providers
/// without forcing the table to rebuild on every Pro-side
/// state change.
final Provider<List<ViolationTableTopActionBuilder>>
violationTableTopActionsProvider =
    Provider<List<ViolationTableTopActionBuilder>>(
      (_) => const <ViolationTableTopActionBuilder>[],
    );
