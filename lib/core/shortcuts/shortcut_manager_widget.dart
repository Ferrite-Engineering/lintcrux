// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:lintcrux/core/shortcuts/shortcut_conflicts.dart';

/// A [ShortcutManager] that passes all key events through when a
/// text-input widget ([EditableText]) currently holds focus.
///
/// Without this guard, bare-letter shortcuts (e.g. a future
/// vim-style `F`) would swallow keystrokes inside dialogs or inline
/// text fields. Modifier combos (Cmd/Ctrl+P, Cmd/Ctrl+F) always fire so
/// shortcuts like the command palette and rule-id search work from any
/// focus state, including from inside the project filter field.
class _TextAwareShortcutManager extends ShortcutManager {
  _TextAwareShortcutManager({required super.shortcuts});

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (_isTextInputFocused() && _isBareLetter()) {
      return KeyEventResult.ignored;
    }
    return super.handleKeypress(context, event);
  }

  /// True when the current key event has no primary modifier keys
  /// (Ctrl, Cmd/Meta, Alt). Shift is not a primary modifier — a
  /// `Shift+<letter>` combo is just a capital letter, so it is treated as
  /// a bare letter and suppressed inside a text field like any other.
  static bool _isBareLetter() =>
      !HardwareKeyboard.instance.isControlPressed &&
      !HardwareKeyboard.instance.isMetaPressed &&
      !HardwareKeyboard.instance.isAltPressed;

  /// True when a text-input widget is anywhere in the focus ancestry.
  ///
  /// `EditableText` attaches its `FocusNode` to an inner `Focus` child
  /// widget, so `primaryFocus.context.widget` is never `EditableText`
  /// itself. Walking up the ancestor elements from that `Focus` finds it
  /// reliably.
  static bool _isTextInputFocused() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    if (focusContext.widget is EditableText) return true;
    var found = false;
    focusContext.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }
}

/// Wraps [child] with Flutter's [Shortcuts] and [Actions] machinery,
/// using bindings from `shortcutBindingsProvider`.
///
/// Pass [handlers] for globally-scoped actions (theme toggle, opening
/// the command palette, etc. — wired at the app root in [LintcruxApp]).
/// Context-sensitive areas (the violation table, the rule-id search
/// field) can register their own `Actions` widget lower in the tree —
/// unhandled intents propagate up to this top-level handler.
class ShortcutManagerWidget extends ConsumerWidget {
  /// Creates a manager wrapping [child]. [handlers] is a map from each
  /// action to the callback that fires when its key binding matches.
  /// Actions absent from the map propagate to lower `Actions` widgets
  /// before falling on the floor.
  const ShortcutManagerWidget({
    required this.child,
    this.handlers = const {},
    super.key,
  });

  /// The wrapped subtree.
  final Widget child;

  /// Callbacks invoked when a matched shortcut fires.
  final Map<LintcruxAction, VoidCallback> handlers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = ref.watch(shortcutBindingsProvider);
    // Resolve collisions deterministically: when two actions share a chord, the
    // user's customized binding wins over the action that holds it by default
    // (shadowed losers are dropped), so a fresh remap actually fires. Previously
    // the map literal let whichever action came later in `bindings` iteration
    // order (LintcruxAction enum declaration order) silently win.
    final effective = resolveShortcutConflicts(bindings).effectiveBindings;
    return Shortcuts.manager(
      manager: _TextAwareShortcutManager(
        shortcuts: {
          for (final e in effective.entries)
            e.value: ShortcutActionIntent(e.key),
        },
      ),
      child: Actions(
        actions: <Type, Action<Intent>>{
          ShortcutActionIntent: CallbackAction<ShortcutActionIntent>(
            onInvoke: (intent) {
              handlers[intent.action]?.call();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
