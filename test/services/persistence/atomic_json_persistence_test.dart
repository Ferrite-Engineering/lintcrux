// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/persistence/atomic_json_file.dart';

/// Crash-safe JSON persistence: a write interrupted between temp-write and
/// rename leaves the original intact.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('lintcrux_atomic'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File makeFile(String name) => File('${dir.path}/$name');

  group('writeJsonAtomic', () {
    test('writes the document and leaves no .tmp behind', () async {
      final file = makeFile('state.json');
      await writeJsonAtomic(file, <String, Object?>{'version': 1, 'x': 42});
      expect(file.existsSync(), isTrue);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      final read = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(read['x'], 42);
    });

    test(
      'a crash between temp-write and rename leaves the original intact',
      () async {
        final file = makeFile('state.json');
        // Seed an original document.
        await writeJsonAtomic(file, <String, Object?>{
          'version': 1,
          'x': 'old',
        });

        // Simulate a crash at the rename instant via the test seam.
        await expectLater(
          writeJsonAtomic(
            file,
            <String, Object?>{'version': 1, 'x': 'new'},
            onBeforeRename: () => throw const FileSystemException('crash'),
          ),
          throwsA(isA<FileSystemException>()),
        );

        // The original content survives — the new value was never applied.
        final read =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(
          read['x'],
          'old',
          reason:
              'temp+rename must not corrupt the original on a mid-write crash',
        );
      },
    );
  });
}
