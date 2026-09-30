// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';

void main() {
  group('SarifFileLoader', () {
    late InMemoryViolationStore store;
    late SarifFileLoader loader;

    String fixtureText() => File(
      'test/fixtures/sarif/verilator_basic.sarif.json',
    ).readAsStringSync();

    setUp(() {
      store = InMemoryViolationStore();
    });

    tearDown(() async {
      loader.dispose();
      await store.dispose();
    });

    test('loadFromString populates the store via replaceFromEngine', () async {
      loader = SarifFileLoader();
      final report = await loader.loadFromString(fixtureText(), store: store);
      expect(report.runs.single.engineId, 'verilator');
      expect(report.runs.single.violations, hasLength(4));
      // Store now reflects every violation, indexed by engine.
      expect(store.byEngine['verilator'], hasLength(4));
      // Pre-computed indices are also populated.
      expect(store.byFile.containsKey('src/top.v'), isTrue);
    });

    test('loadFromXFile reads bytes from the file', () async {
      loader = SarifFileLoader();
      final xfile = XFile.fromData(
        Uint8List.fromList(fixtureText().codeUnits),
        name: 'verilator_basic.sarif.json',
        mimeType: 'application/sarif+json',
      );
      final report = await loader.loadFromXFile(xfile, store: store);
      expect(report.runs.single.violations, hasLength(4));
    });

    test('loadFromXFile streams a real file from disk (openRead)', () async {
      loader = SarifFileLoader();
      final tmp = File(
        '${Directory.systemTemp.path}/lintcrux_loader_'
        '${DateTime.now().microsecondsSinceEpoch}.sarif.json',
      );
      await tmp.writeAsString(fixtureText());
      addTearDown(() async {
        if (tmp.existsSync()) await tmp.delete();
      });
      final report = await loader.loadFromXFile(
        XFile(tmp.path, name: 'from_disk.sarif.json'),
        store: store,
      );
      expect(report.runs.single.violations, hasLength(4));
      expect(store.byEngine['verilator'], hasLength(4));
    });

    test('loadFromUrl fetches the document over HTTP', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://example.com/report.sarif');
        return http.Response(fixtureText(), 200);
      });
      loader = SarifFileLoader(client: client);
      final report = await loader.loadFromUrl(
        Uri.parse('https://example.com/report.sarif'),
        store: store,
      );
      expect(report.runs.single.engineId, 'verilator');
      expect(store.byEngine['verilator'], hasLength(4));
    });

    test('loadFromUrl rejects non-http(s) schemes', () async {
      loader = SarifFileLoader(
        client: MockClient((_) async {
          fail('should never be called for file: scheme');
        }),
      );
      await expectLater(
        loader.loadFromUrl(
          Uri.parse('file:///tmp/report.sarif'),
          store: store,
        ),
        throwsA(isA<SarifLoadException>()),
      );
    });

    test('loadFromUrl wraps non-2xx responses', () async {
      final client = MockClient((request) async {
        return http.Response('not found', 404);
      });
      loader = SarifFileLoader(client: client);
      await expectLater(
        loader.loadFromUrl(
          Uri.parse('https://example.com/missing.sarif'),
          store: store,
        ),
        throwsA(
          isA<SarifLoadException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('loadFromUrl wraps network failures', () async {
      final client = MockClient((request) async {
        throw const SocketException('connection refused');
      });
      loader = SarifFileLoader(client: client);
      await expectLater(
        loader.loadFromUrl(
          Uri.parse('https://example.com/sarif'),
          store: store,
        ),
        throwsA(isA<SarifLoadException>()),
      );
    });

    test('loadFromString throws on malformed input', () async {
      loader = SarifFileLoader();
      await expectLater(
        loader.loadFromString('{not valid sarif}', store: store),
        throwsA(isA<SarifLoadException>()),
      );
    });

    test('successive loads replace prior engine results', () async {
      loader = SarifFileLoader();
      await loader.loadFromString(fixtureText(), store: store);
      expect(store.byEngine['verilator'], hasLength(4));
      // Same engine, empty results — should clear out the old set.
      const emptyForSameEngine = '''
{
  "version": "2.1.0",
  "runs": [
    {
      "tool": {"driver": {"name": "verilator", "version": "5.0"}},
      "results": []
    }
  ]
}
''';
      await loader.loadFromString(emptyForSameEngine, store: store);
      expect(store.byEngine['verilator'], isNull);
    });

    test(
      'a malformed streaming load settles (typed rejection) without '
      'poisoning the next load — re-entrancy regression',
      () async {
        // Regression for the "Cannot add event while adding stream" harness
        // abort / forever-spinning web malformed load: a mid-stream parse
        // failure used to leave the streaming reader's subscription open
        // after the Future settled, so the *next* streaming load in the same
        // isolate re-entered the zone's stream machinery and hung. Both loads
        // below MUST complete promptly.
        loader = SarifFileLoader();
        final truncated = File(
          'test/fixtures/stress/sarif_malformed/truncated.sarif.json',
        ).readAsStringSync();

        XFile xfileOf(String text, String name) =>
            XFile.fromData(Uint8List.fromList(text.codeUnits), name: name);

        // 1) Malformed streaming load surfaces the typed rejection…
        await expectLater(
          loader.loadFromXFile(
            xfileOf(truncated, 'truncated.sarif.json'),
            store: store,
          ),
          throwsA(isA<SarifLoadException>()),
        );

        // 2) …and a subsequent valid load on the same loader still completes
        //    (would hang before the cancelOnError / subscription teardown fix).
        final report = await loader.loadFromXFile(
          xfileOf(fixtureText(), 'verilator_basic.sarif.json'),
          store: store,
        );
        expect(report.runs.single.engineId, 'verilator');
        expect(store.byEngine['verilator'], hasLength(4));
      },
    );
  });
}
