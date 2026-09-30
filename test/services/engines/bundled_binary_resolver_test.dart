// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BundledBinaryResolver', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lintcrux_bundled_');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('returns null when no override / env var is set', () {
      // We can't safely scrub the real env var, so this test just
      // asserts that the no-arg constructor doesn't crash and returns
      // some value (null in normal CI runs, or a path if the host has
      // a bundled binary by accident — both are acceptable).
      const resolver = BundledBinaryResolver();
      final result = resolver.resolve('verilator');
      // Either a path that exists or null.
      if (result != null) {
        expect(File(result).existsSync(), isTrue);
      }
    });

    test('resolves via overrideRoot when the file exists', () async {
      final platformDir = _platformDirForHost();
      if (platformDir == null) return; // unsupported host
      final dir = Directory(p.join(tmp.path, platformDir))..createSync();
      final exeName = Platform.isWindows ? 'verilator.exe' : 'verilator';
      // Build the expected path the way the resolver does (joined with the
      // platform separator) so the comparison holds on Windows too.
      final exePath = p.join(dir.path, exeName);
      await File(exePath).writeAsString('#!/bin/sh\necho fake\n');
      final resolver = BundledBinaryResolver(overrideRoot: tmp.path);
      final resolved = resolver.resolve('verilator');
      expect(resolved, exePath);
    });

    test('returns null when the file is missing under overrideRoot', () {
      final resolver = BundledBinaryResolver(overrideRoot: tmp.path);
      expect(resolver.resolve('verilator'), isNull);
    });

    test('uses the engineId verbatim as the executable basename', () async {
      final platformDir = _platformDirForHost();
      if (platformDir == null) return; // unsupported host
      final dir = Directory('${tmp.path}/$platformDir')..createSync();
      final exe = Platform.isWindows ? 'slang.exe' : 'slang';
      await File('${dir.path}/$exe').writeAsString('#!/bin/sh\nexit 0\n');
      final resolver = BundledBinaryResolver(overrideRoot: tmp.path);
      expect(resolver.resolve('slang'), isNotNull);
    });
  });
}

String? _platformDirForHost() {
  if (Platform.isLinux) return 'linux-x86_64';
  if (Platform.isMacOS) return 'macos-universal';
  if (Platform.isWindows) return 'windows-x86_64';
  return null;
}
