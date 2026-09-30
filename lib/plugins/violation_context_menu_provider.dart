// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// One context-menu entry shown on right-click / long-press of a row in
/// the violation table.
///
/// The Pro overlay contributes entries (e.g. "Waive…") via the
/// `violationContextMenuEntriesProvider` extension point; open-core
/// ships the seam with a default empty list so right-clicking a
/// violation in the open-core build does nothing visible.
///
/// Activation runs inside the row widget's `BuildContext`, with a live
/// `WidgetRef` and the right-clicked [Violation] in hand — so handlers
/// can read providers, push routes, show dialogs, etc.
@immutable
class ViolationContextMenuEntry {
  /// Creates a context-menu entry.
  ///
  /// [id] is a stable identifier used as the popup-menu item's value
  /// (so multiple Pro features can register entries that survive
  /// hot-reload without colliding).
  ///
  /// [requiredTier] paints a tier badge alongside the label. Use
  /// [LicenseTier.openCore] (the default) to suppress the badge.
  const ViolationContextMenuEntry({
    required this.id,
    required this.labelBuilder,
    required this.onActivate,
    this.requiredTier = LicenseTier.openCore,
  });

  /// Stable identifier; used as the `PopupMenuItem.value`.
  final String id;

  /// Builds the user-facing menu-item label inside the row widget's
  /// `BuildContext`. Pro entries typically resolve a `L10NPro.of(context)`
  /// getter here so the menu item picks up the active locale without
  /// the provider needing access to a BuildContext at construction time.
  final String Function(BuildContext context) labelBuilder;

  /// Tier badge to render next to the label. `LicenseTier.openCore`
  /// renders nothing (matches the standard `FeatureTierBadge` behavior).
  final LicenseTier requiredTier;

  /// Activation callback. Runs inside the row widget's `BuildContext`
  /// with access to the live `WidgetRef` and the right-clicked
  /// [Violation]. Returning a `Future` lets the caller `await`
  /// completion if it wants to, but the row widget does not block on
  /// the future.
  final FutureOr<void> Function(
    BuildContext context,
    WidgetRef ref,
    Violation violation,
  )
  onActivate;
}

/// Open-core extension point through which the Pro overlay
/// contributes entries to the violation table row's right-click /
/// long-press context menu.
///
/// Default returns an empty list so the open-core build's violation
/// rows have no context menu (matches today's behavior). The Pro
/// overlay's `proOverrides` replaces this provider with one that
/// returns the "Waive…" entry plus future Pro context actions.
///
/// Consumers (the row widget) iterate the list, build a popup-menu
/// item per entry — with a [LintCruxFeatureTierBadge] next to the label
/// derived from [ViolationContextMenuEntry.requiredTier] — and route
/// activation through [ViolationContextMenuEntry.onActivate].
final violationContextMenuEntriesProvider =
    Provider<List<ViolationContextMenuEntry>>((_) => const []);
