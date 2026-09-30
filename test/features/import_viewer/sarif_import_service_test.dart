// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/features/import_viewer/services/sarif_import_service.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

/// The desktop "Import SARIF report" ingestion semantics:
/// a valid report populates the display store, and a malformed report
/// surfaces a typed [SarifLoadException] while leaving any previously
/// imported report intact (no partial replacement).
void main() {
  group('SarifImportService', () {
    late InMemoryViolationStore display;
    late SarifFileLoader loader;
    late SarifImportService service;

    String validText() => File(
      'test/fixtures/sarif/verilator_basic.sarif.json',
    ).readAsStringSync();

    String malformedText() => File(
      'test/fixtures/stress/sarif_malformed/truncated.sarif.json',
    ).readAsStringSync();

    XFile xfileOf(String text, String name) =>
        XFile.fromData(Uint8List.fromList(text.codeUnits), name: name);

    setUp(() {
      display = InMemoryViolationStore();
      loader = SarifFileLoader();
      service = SarifImportService(loader);
    });

    tearDown(() async {
      loader.dispose();
      await display.dispose();
    });

    test('importing a valid SARIF populates the display store', () async {
      final report = await service.importFromXFile(
        xfileOf(validText(), 'verilator_basic.sarif.json'),
        display: display,
      );
      expect(report.runs.single.engineId, 'verilator');
      // The violation surface (byEngine index the ViolationTable reads) is
      // populated with the imported report's violations.
      expect(display.byEngine['verilator'], hasLength(4));
      expect(display.count, 4);
      expect(display.byFile.containsKey('src/top.v'), isTrue);
    });

    test(
      'importing a malformed SARIF throws SarifLoadException and leaves a '
      'previously-imported report intact',
      () async {
        // Seed a good report first.
        await service.importFromXFile(
          xfileOf(validText(), 'verilator_basic.sarif.json'),
          display: display,
        );
        expect(display.count, 4);

        // A malformed / truncated import must surface the typed error…
        await expectLater(
          service.importFromXFile(
            xfileOf(malformedText(), 'truncated.sarif.json'),
            display: display,
          ),
          throwsA(isA<SarifLoadException>()),
        );

        // …and must NOT have partially replaced the prior report.
        expect(display.count, 4);
        expect(display.byEngine['verilator'], hasLength(4));
      },
    );

    test('importing a valid SARIF into an empty display store works', () async {
      expect(display.isEmpty, isTrue);
      await service.importFromXFile(
        xfileOf(validText(), 'verilator_basic.sarif.json'),
        display: display,
      );
      expect(display.isEmpty, isFalse);
      expect(display.count, 4);
    });
  });
}
