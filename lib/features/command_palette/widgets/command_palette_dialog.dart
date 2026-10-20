// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_keybindings/crux_keybindings.dart'
    show formatShortcutLabel;
import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/shortcuts/action_label.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action_descriptors.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:lintcrux/features/workspace/providers/lintcrux_action_context_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/shared/widgets/lintcrux_feature_tier_badge.dart';

/// Hands keyboard focus back when the palette's route leaves the tree.
///
/// The app-level shortcuts are `Shortcuts` above the root navigator, so they
/// only hear a key while some node under that navigator holds primary focus.
/// If the palette's route is removed and focus ends up on a scope above the
/// navigator (or nowhere), the next chord, Toggle Theme among them, reaches no
/// one until the user clicks into the window.
///
/// This widget wraps the palette. When it is disposed, which is when the route
/// is removed after its exit transition, it checks where focus is on the next
/// frame. Focus inside the navigator is left alone, so an action the palette
/// dispatched that opened its own dialog keeps the focus that dialog took.
/// Focus anywhere else goes back to the node that held it before the palette
/// opened, or to the navigator's own scope when that node is gone.
class _PaletteFocusReturn extends StatefulWidget {
  const _PaletteFocusReturn({required this.focusBefore, required this.child});

  /// The primary focus when the palette was opened.
  final FocusNode? focusBefore;

  final Widget child;

  @override
  State<_PaletteFocusReturn> createState() => _PaletteFocusReturnState();
}

class _PaletteFocusReturnState extends State<_PaletteFocusReturn> {
  late final NavigatorState _navigator;
  late final FocusNode? _focusBefore;

  @override
  void initState() {
    super.initState();
    _navigator = Navigator.of(context);
    _focusBefore = widget.focusBefore;
  }

  @override
  void dispose() {
    final navigator = _navigator;
    final before = _focusBefore;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      final navigatorFocus = navigator.focusNode;
      final primary = FocusManager.instance.primaryFocus;
      final inApp =
          primary != null &&
          (primary == navigatorFocus ||
              primary.ancestors.contains(navigatorFocus));
      if (inApp) return;
      if (before != null &&
          before.context?.mounted == true &&
          before.canRequestFocus &&
          before.ancestors.contains(navigatorFocus)) {
        before.requestFocus();
      } else {
        navigatorFocus.enclosingScope?.requestFocus();
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Trailing per-row widget for the command palette: a [LintCruxFeatureTierBadge] on
/// Pro / Enterprise actions, `null` (no badge) on open-core actions. Tier is
/// declared once on the action via [LintcruxActionRequiredTier.requiredTier]
/// (the single source of truth); this renders it. Mirrors WaveCrux's palette.
Widget? _tierBadgeFor(LintcruxAction action) {
  final tier = action.requiredTier;
  return tier == LicenseTier.openCore
      ? null
      : LintCruxFeatureTierBadge(requiredTier: tier);
}

/// LintCrux-specific wrapper around the cross-suite
/// [CommandPalette]<[LintcruxAction]> widget.
///
/// Responsibilities:
/// - Pick the visible action list.
/// - Resolve action labels through lintcrux's [L10N] class.
/// - Pass the active key bindings so each row can render its shortcut.
/// - Dispatch the selected action by invoking [onAction], leaving the
///   actual handler logic to the caller (typically the app-level
///   [ShortcutManagerWidget] dispatch in `lib/app.dart`).
class CommandPaletteDialog extends ConsumerWidget {
  /// Creates a lintcrux command palette wrapper.
  const CommandPaletteDialog({required this.onAction, super.key});

  /// Called when the user picks an action. The dialog has already closed
  /// itself by the time this fires.
  final ValueChanged<LintcruxAction> onAction;

  /// Shows the palette as a modal dialog over [context].
  ///
  /// Re-entrancy guarded ([ModalGuard]): Cmd/Ctrl+Shift+P auto-repeat or a
  /// double-press must not stack multiple palettes. Guarded inside the
  /// opener so every caller is covered.
  ///
  /// When the palette goes away, keyboard focus goes back to where it was.
  /// See [_PaletteFocusReturn].
  static Future<void> show(
    BuildContext context, {
    required ValueChanged<LintcruxAction> onAction,
  }) {
    final l10n = L10N.of(context);
    // The descriptor table is the single source of truth for every surface.
    // `paletteActionsFor` returns visible AND enabled actions: the palette has
    // no greyed state, so a command that would be inert is omitted rather than
    // shown and silently doing nothing.
    final actions = paletteActionsFor(
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(lintcruxActionContextProvider),
    );
    final bindings = _readBindings(context);
    final focusBefore = FocusManager.instance.primaryFocus;
    return showCruxDialog<void>(
      context: context,
      modalGuardKey: 'commandPalette',
      builder: (_) => _PaletteFocusReturn(
        focusBefore: focusBefore,
        child: CommandPalette<LintcruxAction>(
          actions: actions,
          labelFor: (a) => a.label(l10n),
          onAction: onAction,
          hintText: l10n.commandPaletteSearchHint,
          noResultsLabel: l10n.commandPaletteNoResults,
          bindings: bindings,
          activatorLabel: formatShortcutLabel,
          trailingBuilder: _tierBadgeFor,
        ),
      ),
    );
  }

  /// Reads the active bindings via a one-shot `ProviderScope.containerOf`
  /// lookup so [show] can be invoked from anywhere without a `WidgetRef`
  /// in hand.
  static Map<LintcruxAction, ShortcutActivator?> _readBindings(
    BuildContext context,
  ) {
    final container = ProviderScope.containerOf(context, listen: false);
    return container.read(shortcutBindingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    return CommandPalette<LintcruxAction>(
      actions: paletteActionsFor(ref.watch(lintcruxActionContextProvider)),
      labelFor: (a) => a.label(l10n),
      onAction: onAction,
      hintText: l10n.commandPaletteSearchHint,
      noResultsLabel: l10n.commandPaletteNoResults,
      bindings: bindings,
      activatorLabel: formatShortcutLabel,
      trailingBuilder: _tierBadgeFor,
    );
  }
}
