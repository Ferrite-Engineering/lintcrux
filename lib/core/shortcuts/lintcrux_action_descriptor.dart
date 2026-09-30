// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/core/shortcuts/lintcrux_action_context.dart';
import 'package:meta/meta.dart';

/// The surfaces an action can be discovered from.
enum LintcruxActionSurface {
  /// The viewer toolbar's icon buttons.
  toolbar,

  /// The desktop menu bar (and, on mobile, the overflow menu).
  menu,

  /// The command palette's searchable list.
  palette,
}

/// Where an action appears and when it is usable.
///
/// One descriptor per action, resolved by an exhaustive switch in
/// `lintcrux_action_descriptors.dart`, so adding an enum value fails to
/// compile until its placement and gating are declared. Never re-introduce a
/// per-surface "hidden actions" set or a per-surface enablement copy — that
/// architecture is exactly what drifted apart across the four products.
@immutable
class LintcruxActionDescriptor {
  /// Creates a descriptor. The default is invisible-everywhere and
  /// always-enabled, so a surface-less action must opt in explicitly.
  const LintcruxActionDescriptor({
    this.surfaces = const <LintcruxActionSurface>{},
    this.isEnabled = _alwaysTrue,
  });

  /// The surfaces this action structurally appears in.
  final Set<LintcruxActionSurface> surfaces;

  /// Whether the action is currently invocable.
  ///
  /// A visible-but-disabled action renders greyed rather than vanishing, so
  /// the menu keeps a stable shape and the user can see the command exists
  /// and infer why it is unavailable. The command palette is the exception —
  /// it has no greyed state, so it omits disabled entries.
  final bool Function(LintcruxActionContext) isEnabled;

  static bool _alwaysTrue(LintcruxActionContext _) => true;
}
