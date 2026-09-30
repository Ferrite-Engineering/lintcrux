// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lintcrux/features/import_viewer/providers/imported_sarif_providers.dart';
import 'package:lintcrux/features/import_viewer/services/sarif_import_service.dart';
import 'package:lintcrux/features/project/providers/project_picker_provider.dart';
import 'package:lintcrux/features/web_viewer/providers/sarif_file_loader_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';
import 'package:path/path.dart' as p;

/// Route the desktop imported-SARIF viewer lives at.
const String importedSarifViewerRoute = '/import/viewer';

/// App-wide [SarifImportService] over the shared [sarifFileLoaderProvider].
final Provider<SarifImportService> sarifImportServiceProvider =
    Provider<SarifImportService>(
      (ref) => SarifImportService(ref.watch(sarifFileLoaderProvider)),
      name: 'sarifImportService',
    );

/// Drives the desktop "Import SARIF report" flow end to end:
/// pick a `.sarif` / `.json` file → stream it through the existing
/// [SarifImportService] into the isolated imported-report store → on
/// success navigate to the read-only imported-report viewer.
///
/// Malformed safety: on a bad / truncated SARIF the loader throws
/// [SarifLoadException]; this surfaces a typed snackbar and leaves any
/// previously-imported report intact (the service commits nothing on
/// failure). Mirrors the web landing screen's error handling.
///
/// Shared by every entry point (File menu / command palette / toolbar /
/// welcome) so the pick-load-navigate behaviour lives in exactly one
/// place.
///
/// [path] skips the picker: a report the operating system opened LintCrux
/// with (a Finder double-click) is already chosen, and takes the same
/// load-and-navigate path from there.
Future<void> runSarifImportFlow(
  BuildContext context,
  WidgetRef ref, {
  String? path,
}) async {
  final l10n = L10N.of(context);
  final router = GoRouter.of(context);
  // Everything read through `ref` before the first await: the widget that
  // started the import can be gone by the time the picker or the load
  // returns, and `ref` throws from then on. The telemetry service is a local
  // for this one call, never a field (see
  // `telemetry_service_not_captured_test.dart`).
  final picker = ref.read(projectPickerProvider);
  final service = ref.read(sarifImportServiceProvider);
  // Write into the imported-report store via `importedSarifStoreProvider`.
  // It (and `violationStorePerProjectFamily`) declare no Riverpod
  // `dependencies`, so the instance is hoisted to the ROOT container and is
  // the SAME object the viewer's `importedSarifViewerOverrides` re-bind
  // `violationStoreProvider` to — regardless of which container (root or a
  // per-tab child) the import button that called this flow lived in.
  // Guarantees write-store === read-store.
  final display = ref.read(importedSarifStoreProvider);
  final telemetry = ref.read(telemetryServiceProvider);
  final source = ref.read(importedSarifSourceProvider.notifier);

  final String? picked;
  try {
    picked =
        path ??
        await picker.pickSarifFile(
          confirmButtonText: l10n.filePickerImportSarifButton,
          // Locale-neutral format acronym, matching the export picker's
          // `label` convention.
          typeLabel: 'SARIF',
        );
  } on Object catch (error) {
    if (!context.mounted) return;
    showCruxErrorSnack(context, l10n.filePickerFailed('$error'));
    return;
  }
  if (picked == null) return;

  final file = XFile(picked);
  try {
    await service.importFromXFile(file, display: display);
  } on SarifLoadException catch (e) {
    if (!context.mounted) return;
    showCruxErrorSnack(context, l10n.importSarifFailed(e.message));
    return;
  }
  // Past the cancelled-picker and `SarifLoadException` returns, so this counts
  // reports that actually rendered. No properties: the file name is the
  // report's, and the telemetry never-collect list excludes file names.
  telemetry.record(TelemetryEvent('sarif.imported'));
  // `p.basename`, not `XFile.name`: on Windows `XFile.name` splits on `\`
  // alone, so a path spelled with `/` (a command-line argument, a script)
  // would put the whole path in the viewer's title.
  source.record(p.basename(picked));
  router.go(importedSarifViewerRoute);
}
