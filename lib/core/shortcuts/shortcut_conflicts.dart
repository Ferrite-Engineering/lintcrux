// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_keybindings/crux_keybindings.dart' as kb;
import 'package:flutter/widgets.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings.dart';

/// Activator combinations more than one [LintcruxAction] is *intentionally*
/// allowed to share, so conflict resolution doesn't flag them. LintCrux
/// has no by-design keyboard shadows today; the set exists so the wrapper has
/// the same shape as the other products if one is ever introduced.
const Set<Set<LintcruxAction>> kIntentionalShadows = {};

/// LintCrux-flavored conflict *resolution*: delegates to the cross-suite
/// `resolveShortcutConflicts`, injecting [defaultBindings], [LintcruxAction]
/// declaration order (for the deterministic tiebreak), and
/// [kIntentionalShadows].
///
/// Returns both the deterministic runtime activator map
/// ([kb.ShortcutConflictResolution.effectiveBindings] — fed to
/// `ShortcutManagerWidget` so a user-remapped binding wins its chord instead of
/// the enum-declaration-order accident) and the editor's owner/shadowed view.
kb.ShortcutConflictResolution<LintcruxAction> resolveShortcutConflicts(
  Map<LintcruxAction, ShortcutActivator> bindings,
) => kb.resolveShortcutConflicts(
  bindings,
  defaultBindings(),
  order: LintcruxAction.values,
  intentionalShadows: kIntentionalShadows,
);
