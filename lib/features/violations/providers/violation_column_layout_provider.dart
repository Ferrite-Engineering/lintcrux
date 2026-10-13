// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_table/crux_table.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/domain/models/violation_column_layout.dart';
import 'package:lintcrux/domain/models/violation_table_state.dart';

/// The Riverpod seam for the violation table's persisted column widths:
/// `crux_table`'s providers over [violationTableColumns], stored under
/// [kViolationColumnWeightsPrefsKey].
///
/// App-wide rather than per tab: every tab shows the same columns, and a
/// width the user dragged in one is the width they want in the next. Lives in
/// the root container, which every tab's container is parented to.
final CruxColumnLayoutProviders<ViolationTableColumn> violationColumnLayout =
    CruxColumnLayoutProviders<ViolationTableColumn>(
      columns: violationTableColumns,
      prefsKey: kViolationColumnWeightsPrefsKey,
      name: 'violationColumnLayout',
    );

/// The [SettingsService] that reads and writes the violation table's column
/// widths.
///
/// Override in tests with a `SettingsService(violationColumnLayout.codec,
/// prefsOverride: prefs)`.
final Provider<SettingsService<ViolationColumnLayout>>
violationColumnLayoutSettingsServiceProvider =
    violationColumnLayout.settingsService;

/// The column widths persisted when this launch started.
///
/// Read synchronously so the first frame of a restored tab draws its columns
/// at their saved widths rather than jumping to them a moment later.
/// `bootstrap` resolves [loadViolationColumnLayout] before `runApp` and
/// overrides this; tests get the defaults with no storage call.
final Provider<ViolationColumnLayout> launchViolationColumnLayoutProvider =
    violationColumnLayout.launch;

/// Loads the persisted column widths, or the defaults on any failure.
///
/// [service] is injectable for tests; production passes nothing.
Future<ViolationColumnLayout> loadViolationColumnLayout({
  SettingsService<ViolationColumnLayout>? service,
}) => violationColumnLayout.load(service: service);

/// The violation table's live column widths. Its notifier is the
/// [CruxColumnResizeController] the header's dividers drive: `resize` while
/// a drag is in progress, `commit` when it ends, `reset` on a double-click.
final NotifierProvider<
  CruxColumnLayoutNotifier<ViolationTableColumn>,
  ViolationColumnLayout
>
violationColumnLayoutProvider = violationColumnLayout.layout;
