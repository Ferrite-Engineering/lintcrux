// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/import_viewer/providers/imported_sarif_providers.dart';
import 'package:lintcrux/features/import_viewer/screens/imported_sarif_viewer_screen.dart';
import 'package:lintcrux/features/import_viewer/services/sarif_import_service.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';

/// End-to-end coverage for the desktop imported-SARIF viewer.
///
/// This is the coverage gap that let the "viewer shows 0 violations" defect
/// ship: a `SarifImportService`-writes-to-store *unit* test passes while the
/// screen still renders nothing, because the bug was in the container/scope
/// wiring between the flow's write and the screen's read — not in the write
/// itself. These tests drive the real store-population step (exactly what
/// `runSarifImportFlow` does — write into the root-hoisted
/// `importedSarifStoreProvider`, then record the source) and pump the REAL
/// [ImportedSarifViewerScreen], asserting the table renders the imported
/// violations and the footer total matches.
///
/// It fails on the pre-fix screen (which overrode only
/// `activeProjectIdProvider` — inert for the un-scoped `violationStoreProvider`
/// chain, so the table read the root's empty store and showed "0 total") and
/// passes once the screen applies [importedSarifViewerOverrides].
void main() {
  String validText() => File(
    'test/fixtures/sarif/verilator_basic.sarif.json',
  ).readAsStringSync();

  String malformedText() => File(
    'test/fixtures/stress/sarif_malformed/truncated.sarif.json',
  ).readAsStringSync();

  XFile xfileOf(String text, String name) =>
      XFile.fromData(Uint8List.fromList(text.codeUnits), name: name);

  Widget appWith(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      localizationsDelegates: [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: ImportedSarifViewerScreen(),
    ),
  );

  // A generous surface so the four-pane IDE layout lays out without a
  // RenderFlex overflow (which `takeException` would otherwise surface).
  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('a valid import renders in the viewer table (N>0 rows + footer '
      'total)', (tester) async {
    useLargeSurface(tester);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Populate the imported store the way `runSarifImportFlow` does: the
    // service writes into the root-hoisted `importedSarifStoreProvider`, and
    // the source name is recorded for the app-bar subtitle. The streaming
    // read is real async, so it runs inside `tester.runAsync`.
    final service = SarifImportService(SarifFileLoader());
    final display = container.read(importedSarifStoreProvider);
    await tester.runAsync(() async {
      await service.importFromXFile(
        xfileOf(validText(), 'lint_realistic.sarif'),
        display: display,
      );
    });
    container
        .read(importedSarifSourceProvider.notifier)
        .record(
          'lint_realistic.sarif',
        );
    // Sanity: the store the flow writes to is populated.
    expect(display.count, 4);

    await tester.pumpWidget(appWith(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    // The viewer renders the imported violations, NOT the empty state.
    expect(find.text('No violations.'), findsNothing);
    // Footer total reflects the imported violation count (was "0 total"
    // before the scope fix).
    expect(find.textContaining('4 total'), findsOneWidget);
    // Engine filter chip is derived from the imported report's engines.
    expect(
      find.byKey(const ValueKey('violationFilterChip-engine-verilator')),
      findsOneWidget,
    );
    // The app-bar subtitle shows the imported source name.
    expect(find.text('lint_realistic.sarif'), findsOneWidget);
  });

  testWidgets('a malformed import is rejected and leaves the viewer empty', (
    tester,
  ) async {
    useLargeSurface(tester);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final service = SarifImportService(SarifFileLoader());
    final display = container.read(importedSarifStoreProvider);

    // Desktop path: a malformed import surfaces the typed rejection and
    // never partially populates the store.
    Object? caught;
    await tester.runAsync(() async {
      try {
        await service.importFromXFile(
          xfileOf(malformedText(), 'truncated.sarif'),
          display: display,
        );
      } on Object catch (e) {
        caught = e;
      }
    });
    expect(caught, isA<SarifLoadException>());
    expect(display.count, 0);

    await tester.pumpWidget(appWith(container));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    // Nothing imported → the viewer shows the empty state.
    expect(find.text('No violations.'), findsOneWidget);
  });
}
