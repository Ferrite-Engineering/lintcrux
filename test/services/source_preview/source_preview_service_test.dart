// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/source_preview/source_preview_service.dart';

class _FakeReader implements SourceReader {
  _FakeReader(this.byFile);
  final Map<String, List<String>?> byFile;

  @override
  Future<List<String>?> readLines(String file) async => byFile[file];
}

void main() {
  group('SourcePreviewService', () {
    test(
      'returns the requested window centered on the violation line',
      () async {
        final svc = SourcePreviewService(
          reader: _FakeReader({
            '/a.sv': List<String>.generate(100, (i) => 'line ${i + 1}'),
          }),
        );
        final w = await svc.windowAround(file: '/a.sv', line: 50);
        expect(w.startLine, 40);
        expect(w.lines.length, 21);
        expect(w.lines.first, 'line 40');
        expect(w.lines.last, 'line 60');
        expect(w.highlightLine, 50);
      },
    );

    test('clamps the window to the start of the file', () async {
      final svc = SourcePreviewService(
        reader: _FakeReader({
          '/a.sv': List<String>.generate(30, (i) => 'line ${i + 1}'),
        }),
      );
      final w = await svc.windowAround(file: '/a.sv', line: 1);
      expect(w.startLine, 1);
      expect(w.lines.length, 11);
      expect(w.lines.last, 'line 11');
    });

    test('clamps the window to the end of the file', () async {
      final svc = SourcePreviewService(
        reader: _FakeReader({
          '/a.sv': List<String>.generate(30, (i) => 'line ${i + 1}'),
        }),
      );
      final w = await svc.windowAround(file: '/a.sv', line: 30);
      expect(w.startLine, 20);
      expect(w.lines.length, 11);
      expect(w.lines.last, 'line 30');
    });

    test('returns an empty window when the file is missing', () async {
      final svc = SourcePreviewService(reader: _FakeReader({}));
      final w = await svc.windowAround(file: '/missing.sv', line: 5);
      expect(w.isEmpty, isTrue);
      expect(w.file, '/missing.sv');
    });

    test('returns an empty window for invalid line numbers', () async {
      final svc = SourcePreviewService(
        reader: _FakeReader({
          '/a.sv': ['x'],
        }),
      );
      final w = await svc.windowAround(file: '/a.sv', line: 0);
      expect(w.isEmpty, isTrue);
    });

    test(
      'related lines inside the window appear in highlightedRelated',
      () async {
        final svc = SourcePreviewService(
          reader: _FakeReader({
            '/a.sv': List<String>.generate(100, (i) => 'line ${i + 1}'),
          }),
        );
        final w = await svc.windowAround(
          file: '/a.sv',
          line: 50,
          relatedLineSet: {42, 55, 200},
        );
        expect(w.highlightedRelated, {42, 55});
      },
    );

    test('related lines outside the window are excluded', () async {
      final svc = SourcePreviewService(
        reader: _FakeReader({
          '/a.sv': List<String>.generate(100, (i) => 'line ${i + 1}'),
        }),
      );
      final w = await svc.windowAround(
        file: '/a.sv',
        line: 50,
        relatedLineSet: {10, 80},
      );
      expect(w.highlightedRelated, isEmpty);
    });

    test(
      'the violation line is never included in highlightedRelated',
      () async {
        final svc = SourcePreviewService(
          reader: _FakeReader({
            '/a.sv': List<String>.generate(100, (i) => 'line ${i + 1}'),
          }),
        );
        final w = await svc.windowAround(
          file: '/a.sv',
          line: 50,
          relatedLineSet: {50, 51},
        );
        expect(w.highlightedRelated, {51});
      },
    );

    test('custom contextLines configures window size', () async {
      final svc = SourcePreviewService(
        reader: _FakeReader({
          '/a.sv': List<String>.generate(100, (i) => 'line ${i + 1}'),
        }),
        contextLines: 3,
      );
      final w = await svc.windowAround(file: '/a.sv', line: 50);
      expect(w.lines.length, 7);
      expect(w.startLine, 47);
      expect(w.lines.last, 'line 53');
    });
  });
}
