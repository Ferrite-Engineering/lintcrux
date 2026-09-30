// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/ghdl/ghdl_availability_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('GhdlAvailabilityService', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lintcrux_ghdl_');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('isAvailable is consistent with resolveBinaryPath', () {
      const service = GhdlAvailabilityService();
      final resolved = service.resolveBinaryPath();
      expect(service.isAvailable, resolved != null);
    });

    test('resolves the bundled binary when present', () async {
      final platformDir = _platformDirForHost();
      if (platformDir == null) return; // unsupported host
      final dir = Directory(p.join(tmp.path, platformDir))..createSync();
      final exe = Platform.isWindows ? 'ghdl.exe' : 'ghdl';
      // Join with the platform separator so the expected path matches what
      // BundledBinaryResolver produces on Windows.
      final exePath = p.join(dir.path, exe);
      await File(exePath).writeAsString('#!/bin/sh\nexit 0\n');
      final service = GhdlAvailabilityService(
        bundledBinaryResolver: BundledBinaryResolver(overrideRoot: tmp.path),
      );
      expect(service.resolveBinaryPath(), exePath);
      expect(service.isAvailable, isTrue);
    });

    test('returns null when neither bundled nor on PATH', () {
      // We can't control PATH safely in unit tests; instead, point the
      // bundled-resolver at an empty temp dir and trust the test
      // environment doesn't have ghdl on PATH. If it does, the test
      // accepts that path as a valid resolution and asserts shape only.
      final service = GhdlAvailabilityService(
        bundledBinaryResolver: BundledBinaryResolver(overrideRoot: tmp.path),
      );
      final resolved = service.resolveBinaryPath();
      // Either resolves to "ghdl" (PATH) or null (truly absent).
      expect(
        resolved == 'ghdl' || resolved == null,
        isTrue,
        reason: 'unexpected resolution: $resolved',
      );
    });
  });
}

String? _platformDirForHost() {
  if (Platform.isLinux) return 'linux-x86_64';
  if (Platform.isMacOS) return 'macos-universal';
  if (Platform.isWindows) return 'windows-x86_64';
  return null;
}
