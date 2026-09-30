// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/filter_preset.dart';

/// The currently-applied [FilterPreset] in the per-tab violations
/// table, or `null` when no preset is active (the user's table state
/// is whatever they have manually applied).
///
/// Per-tab scope: overridden in `lintcruxTabOverridesFactory` so each
/// tab tracks its own active preset.
///
/// When non-null, the preset's [FilterPreset.filterState] is applied
/// by `VisibleViolationsNotifier` as an additional post-filter on top
/// of the user's manual filter controls. Manual filter adjustments
/// transition the UI into a "Custom filter" mode (the selector chip
/// dims) but the active preset reference is preserved so the user
/// can re-apply it.
///
/// Implemented as a [NotifierProvider] so the selector chip can call
/// `.activate(preset)` / `.clear()` and so widget tests can override
/// the notifier without touching the underlying [FilterPresetStore].
class ActiveFilterPresetNotifier extends Notifier<FilterPreset?> {
  @override
  FilterPreset? build() => null;

  /// Sets [preset] as the active preset. Pass `null` to clear.
  // ignore: use_setters_to_change_properties
  void activate(FilterPreset? preset) {
    state = preset;
  }

  /// Convenience: clears the active preset (equivalent to
  /// `activate(null)`).
  void clear() {
    state = null;
  }
}

/// Per-tab active filter preset. Overridden per-tab via
/// `lintcruxTabOverridesFactory`.
final NotifierProvider<ActiveFilterPresetNotifier, FilterPreset?>
activeFilterPresetProvider =
    NotifierProvider<ActiveFilterPresetNotifier, FilterPreset?>(
      ActiveFilterPresetNotifier.new,
    );
