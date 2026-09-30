// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/session/lintcrux_session.dart';
import 'package:lintcrux/services/session/session_service.dart';

class _InMemory implements SessionFileReader, SessionFileWriter {
  _InMemory();
  final Map<String, String> files = <String, String>{};
  @override
  Future<String?> readString(String path) async => files[path];
  @override
  Future<void> writeString(String path, String body) async {
    files[path] = body;
  }
}

void main() {
  group('SessionService', () {
    test('save then load round-trips the session', () async {
      final io = _InMemory();
      final svc = SessionService(reader: io, writer: io);
      const session = LintcruxSession(
        projectPath: '/work/p.lintcrux',
        selectedRuleId: 'verilator/UNUSED',
      );
      await svc.save('/x/y.lintcrux-session', session);
      final loaded = await svc.load('/x/y.lintcrux-session');
      expect(loaded, isNotNull);
      expect(loaded!.projectPath, '/work/p.lintcrux');
      expect(loaded.selectedRuleId, 'verilator/UNUSED');
    });

    test('load returns null when the file does not exist', () async {
      final io = _InMemory();
      final svc = SessionService(reader: io, writer: io);
      expect(await svc.load('/missing.lintcrux-session'), isNull);
    });

    test('load throws on malformed JSON', () async {
      final io = _InMemory()..files['/x'] = '{ broken';
      final svc = SessionService(reader: io, writer: io);
      await expectLater(
        () => svc.load('/x'),
        throwsA(isA<LintcruxSessionLoadException>()),
      );
    });

    test('load throws on a non-object root', () async {
      final io = _InMemory()..files['/x'] = '[]';
      final svc = SessionService(reader: io, writer: io);
      await expectLater(
        () => svc.load('/x'),
        throwsA(isA<LintcruxSessionLoadException>()),
      );
    });

    test('load throws on unsupported version', () async {
      final io = _InMemory()
        ..files['/x'] = '{"version": 999, "projectPath": "/y"}';
      final svc = SessionService(reader: io, writer: io);
      await expectLater(
        () => svc.load('/x'),
        throwsA(isA<LintcruxSessionLoadException>()),
      );
    });
  });
}
