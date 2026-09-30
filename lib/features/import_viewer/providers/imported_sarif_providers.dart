// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_projects/crux_projects.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/features/violations/providers/present_engine_ids_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_view_mode_provider.dart';
import 'package:lintcrux/services/filter_presets/active_filter_preset_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// Dedicated per-project id used to isolate the desktop imported-SARIF
/// report's violation set from any open project's store.
///
/// The desktop imported-report viewer overrides [activeProjectIdProvider]
/// with this constant, so the shared `violationStoreProvider` /
/// `ViolationTable` pipeline resolves to [violationStorePerProjectFamily]
/// slot keyed by this id rather than the active project's slot. That keeps
/// an imported CI report entirely separate from — and non-destructive to —
/// whatever project the user has open in the workspace.
///
/// It is deliberately distinct from [emptyWorkspaceProjectId] (`<none>`)
/// so importing while no project is open still lands in its own slot.
const String importedSarifProjectId = '<imported-sarif>';

/// The [ViolationStore] backing the imported-SARIF report. Resolves the
/// [violationStorePerProjectFamily] slot for [importedSarifProjectId], the
/// same instance the imported-report viewer renders (which reaches it via
/// the [activeProjectIdProvider] override).
final Provider<ViolationStore> importedSarifStoreProvider =
    Provider<ViolationStore>(
      (ref) =>
          ref.watch(violationStorePerProjectFamily(importedSarifProjectId)),
      name: 'importedSarifStore',
    );

/// Display name (file name) of the most recently imported SARIF report, or
/// `null` when nothing has been imported yet. Drives the imported-report
/// viewer's app-bar subtitle. Root-scoped so it survives navigation into
/// the (nested-scope) viewer screen.
final NotifierProvider<ImportedSarifSourceNotifier, String?>
importedSarifSourceProvider =
    NotifierProvider<ImportedSarifSourceNotifier, String?>(
      ImportedSarifSourceNotifier.new,
      name: 'importedSarifSource',
    );

/// Notifier exposing `set` over the imported-report source name.
class ImportedSarifSourceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Records [name] as the imported report's display name.
  // ignore: use_setters_to_change_properties
  void record(String? name) => state = name;
}

/// Provider overrides applied by [ImportedSarifViewerScreen] so the shared
/// `ViolationTable` / inspector / source-preview panes render the imported
/// report rather than the active project's (root-scoped, empty) store.
///
/// ### Why a bundle rather than a single `activeProjectIdProvider` override
///
/// `violationStoreProvider` (a `perProjectScope` provider) and the derived
/// `visibleViolationsProvider` / `presentEngineIdsProvider` declare no
/// Riverpod `dependencies`, so they are hoisted to the ROOT container and
/// read the ROOT `activeProjectIdProvider` regardless of any descendant
/// scope's override. Overriding `activeProjectIdProvider` alone was
/// therefore inert: the viewer's table read the root's empty store and
/// showed "No violations. / 0 total" even though the import had populated
/// the `<imported-sarif>` slot.
///
/// The imported store is a single root-hoisted instance (via
/// [importedSarifStoreProvider] → [violationStorePerProjectFamily] keyed by
/// [importedSarifProjectId]), so the flow's write and this override resolve
/// the SAME store no matter which container the import button lived in. The
/// fix is to re-bind, in the viewer's scope, exactly the store-derived
/// providers the panes read so they re-evaluate against that store:
///
///  * `violationStoreProvider` → the imported store instance;
///  * `visibleViolationsProvider`, `presentEngineIdsProvider`,
///    `violationTableStateProvider`, `violationViewModeProvider`,
///    `activeFilterPresetProvider`, `selectedViolationProvider`,
///    `currentProjectProvider` → fresh in-scope notifiers, so the viewer's
///    filter / sort / selection state is isolated from any open project's
///    and its derivations watch the overridden store.
///
/// This keeps the imported report entirely separate from — and
/// non-destructive to — whatever project the user has open, while
/// guaranteeing write-store === read-store.
List<Override> importedSarifViewerOverrides() => <Override>[
  // The store the panes render: the imported-report slot (same root
  // instance the import flow committed into).
  violationStoreProvider.overrideWith(
    (ref) => ref.watch(importedSarifStoreProvider),
  ),
  // Isolate the viewer's project-keyed table state from any open project.
  currentProjectProvider.overrideWith(CurrentProjectNotifier.new),
  // Filter / sort / view-mode / preset / selection — fresh per viewer so
  // they neither inherit nor mutate an open tab's state, and (critically)
  // re-evaluate against the overridden `violationStoreProvider` above.
  violationTableStateProvider.overrideWith(ViolationTableNotifier.new),
  violationViewModeProvider.overrideWith(ViolationViewModeNotifier.new),
  activeFilterPresetProvider.overrideWith(ActiveFilterPresetNotifier.new),
  selectedViolationProvider.overrideWith(SelectedViolationNotifier.new),
  visibleViolationsProvider.overrideWith(VisibleViolationsNotifier.new),
  presentEngineIdsProvider.overrideWith(PresentEngineIdsNotifier.new),
];
