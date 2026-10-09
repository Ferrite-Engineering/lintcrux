// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation_column_layout.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';
import 'package:lintcrux/services/persistence/violation_column_layout_codec.dart';

/// The [SettingsService] that reads and writes the violation table's column
/// widths.
///
/// Override in tests with a `SettingsService(codec, prefsOverride: prefs)`.
final Provider<SettingsService<ViolationColumnLayout>>
violationColumnLayoutSettingsServiceProvider =
    Provider<SettingsService<ViolationColumnLayout>>(
      (_) => const SettingsService<ViolationColumnLayout>(
        ViolationColumnLayoutCodec(),
      ),
      name: 'violationColumnLayoutSettingsServiceProvider',
    );

/// The column widths persisted when this launch started.
///
/// Read synchronously so the first frame of a restored tab draws its columns
/// at their saved widths rather than jumping to them a moment later.
/// `bootstrap` resolves [loadViolationColumnLayout] before `runApp` and
/// overrides this; tests get the defaults with no storage call.
final Provider<ViolationColumnLayout> launchViolationColumnLayoutProvider =
    Provider<ViolationColumnLayout>(
      (_) => ViolationColumnLayout.defaults,
      name: 'launchViolationColumnLayoutProvider',
    );

/// Loads the persisted column widths, or the defaults on any failure.
///
/// [service] is injectable for tests; production passes nothing.
Future<ViolationColumnLayout> loadViolationColumnLayout({
  SettingsService<ViolationColumnLayout>? service,
}) async {
  try {
    return await (service ??
            const SettingsService<ViolationColumnLayout>(
              ViolationColumnLayoutCodec(),
            ))
        .load();
  } on Object {
    return ViolationColumnLayout.defaults;
  }
}

/// The violation table's column widths.
///
/// App-wide rather than per tab: every tab shows the same columns, and a
/// width the user dragged in one is the width they want in the next. Lives in
/// the root container, which every tab's container is parented to.
final NotifierProvider<ViolationColumnLayoutNotifier, ViolationColumnLayout>
violationColumnLayoutProvider =
    NotifierProvider<ViolationColumnLayoutNotifier, ViolationColumnLayout>(
      ViolationColumnLayoutNotifier.new,
      name: 'violationColumnLayoutProvider',
    );

/// Notifier backing [violationColumnLayoutProvider].
class ViolationColumnLayoutNotifier extends Notifier<ViolationColumnLayout> {
  @override
  ViolationColumnLayout build() =>
      ref.read(launchViolationColumnLayoutProvider);

  /// Drags the divider after [column] by [dx] pixels in a table whose
  /// columns span [tableWidth] pixels. Not saved until [commit].
  void resize(ViolationTableColumn column, double dx, double tableWidth) {
    state = state.resize(column, dx, tableWidth);
  }

  /// Saves the current widths. Called when a drag ends, so a drag writes
  /// once rather than on every pointer move.
  void commit() => unawaited(_save());

  /// Restores and saves the default widths.
  void reset() {
    state = ViolationColumnLayout.defaults;
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await ref.read(violationColumnLayoutSettingsServiceProvider).save(state);
    } on Object {
      // No preferences backend: the widths still apply to this session.
    }
  }
}
