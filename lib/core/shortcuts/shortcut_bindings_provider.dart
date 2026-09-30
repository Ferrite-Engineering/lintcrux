// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/shortcuts/lintcrux_action.dart';
import 'package:lintcrux/core/shortcuts/shortcut_bindings.dart';
import 'package:logging/logging.dart';

final _log = Logger('lintcrux.shortcuts');

/// Provides the [KeyBindingsStore] used to persist customizations, configured
/// with LintCrux's action set + schema (`lintCruxKeymapCodec`).
///
/// Override in tests to inject a `SharedPreferences`-backed store.
final Provider<KeyBindingsStore<LintcruxAction>> shortcutBindingsStoreProvider =
    Provider<KeyBindingsStore<LintcruxAction>>(
      (ref) => KeyBindingsStore<LintcruxAction>(codec: lintCruxKeymapCodec),
    );

/// Manages the active key bindings for all [LintcruxAction]s.
///
/// Seeded synchronously from [defaultBindings] so consumers never see a null
/// map, then persisted customizations are overlaid asynchronously once they
/// load from [KeyBindingsStore]. Customizations are stored as **diffs from
/// default** (see [currentDiffs]).
final NotifierProvider<
  ShortcutBindingsNotifier,
  Map<LintcruxAction, ShortcutActivator>
>
shortcutBindingsProvider =
    NotifierProvider<
      ShortcutBindingsNotifier,
      Map<LintcruxAction, ShortcutActivator>
    >(ShortcutBindingsNotifier.new);

/// Notifier backing [shortcutBindingsProvider].
class ShortcutBindingsNotifier
    extends Notifier<Map<LintcruxAction, ShortcutActivator>> {
  bool _disposed = false;

  /// Set when the stored keymap was written by a newer build. Every save is
  /// then skipped for the rest of the session: this build's diffs would
  /// replace a keymap it cannot read, wiping the user's bindings for the day
  /// they upgrade again.
  bool _storedKeymapIsNewer = false;

  @override
  Map<LintcruxAction, ShortcutActivator> build() {
    ref.onDispose(() => _disposed = true);
    unawaited(_restore());
    return defaultBindings();
  }

  Future<void> _restore() async {
    final Map<LintcruxAction, KeyBinding?> diffs;
    try {
      diffs = await ref.read(shortcutBindingsStoreProvider).load();
    } on KeymapSchemaVersionException catch (e) {
      // The store answers every other failure with "no customizations"; this
      // one it refuses loudly so the caller can decline to overwrite it.
      _storedKeymapIsNewer = true;
      _log.warning(
        'Stored keyboard shortcuts come from a newer LintCrux (${e.message}); '
        'running on defaults and leaving them unsaved this session',
      );
      return;
    }
    if (_disposed || diffs.isEmpty) return;
    state = KeyBindingResolver.resolve(defaultBindings(), diffs);
  }

  /// The current customizations as diffs against the platform defaults
  /// (including explicit unbinds). Persisted and written by keymap Export.
  Map<LintcruxAction, KeyBinding?> currentDiffs() => KeyBindingResolver.diff(
    LintcruxAction.values,
    state,
    defaultBindings(),
  );

  void _persist() {
    if (_storedKeymapIsNewer) return;
    unawaited(ref.read(shortcutBindingsStoreProvider).save(currentDiffs()));
  }

  /// Sets a custom binding for [action], replacing the current activator.
  void setBinding(LintcruxAction action, ShortcutActivator activator) {
    state = Map<LintcruxAction, ShortcutActivator>.of(state)
      ..[action] = activator;
    _persist();
  }

  /// Removes any binding for [action] (an explicit unbind). No-op when the
  /// action is already unbound.
  void unbind(LintcruxAction action) {
    if (!state.containsKey(action)) return;
    state = Map<LintcruxAction, ShortcutActivator>.of(state)..remove(action);
    _persist();
  }

  /// Resets [action] to its platform default (or unbinds it if it has none).
  void reset(LintcruxAction action) {
    final updated = Map<LintcruxAction, ShortcutActivator>.of(state);
    final replacement = defaultBindings()[action];
    if (replacement == null) {
      updated.remove(action);
    } else {
      updated[action] = replacement;
    }
    state = updated;
    _persist();
  }

  /// Resets all bindings to platform defaults and clears persisted overrides.
  void resetAll() {
    state = defaultBindings();
    _persist();
  }

  /// Replaces all customizations with [diffs] (keymap Import).
  void importDiffs(Map<LintcruxAction, KeyBinding?> diffs) {
    state = KeyBindingResolver.resolve(defaultBindings(), diffs);
    _persist();
  }

  /// Replaces all bindings with a named preset's complete map (selected in
  /// Settings → Keyboard Shortcuts).
  ///
  /// The delta from the platform defaults is persisted via [currentDiffs], so a
  /// preset that equals the defaults stores nothing and one that diverges
  /// stores only its overrides — identical to the Import path. The user can
  /// still edit individual rows afterward.
  void applyPreset(Map<LintcruxAction, ShortcutActivator> preset) {
    state = Map<LintcruxAction, ShortcutActivator>.of(preset);
    _persist();
  }
}
