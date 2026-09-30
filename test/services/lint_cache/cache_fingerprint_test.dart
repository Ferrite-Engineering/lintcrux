// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/lint_cache/cache_fingerprint.dart';

void main() {
  group('CacheFingerprint.sourceOfBytes', () {
    test('produces a 64-char hex digest', () {
      final fp = CacheFingerprint.sourceOfBytes('hello'.codeUnits);
      expect(fp.length, equals(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(fp), isTrue);
    });

    test('normalizes CRLF to LF (CRLF and LF produce same digest)', () {
      final lf = CacheFingerprint.sourceOfBytes('a\nb\n'.codeUnits);
      final crlf = CacheFingerprint.sourceOfBytes('a\r\nb\r\n'.codeUnits);
      expect(lf, equals(crlf));
    });

    test('different contents produce different digests', () {
      expect(
        CacheFingerprint.sourceOfBytes('a'.codeUnits),
        isNot(equals(CacheFingerprint.sourceOfBytes('b'.codeUnits))),
      );
    });
  });

  group('CacheFingerprint.sourceOf (file I/O)', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lintcrux_cache_fp');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('reads file and returns its digest', () async {
      final f = File('${tmp.path}/a.sv')
        ..writeAsStringSync('module a;\nendmodule\n');
      final got = await CacheFingerprint.sourceOf(f.path);
      expect(
        got,
        equals(
          CacheFingerprint.sourceOfBytes('module a;\nendmodule\n'.codeUnits),
        ),
      );
    });

    test('returns null when the file does not exist', () async {
      final got = await CacheFingerprint.sourceOf('${tmp.path}/nope.sv');
      expect(got, isNull);
    });
  });

  group('CacheFingerprint.configOf', () {
    LintRunRequest req({
      List<String> sourceFiles = const ['/a.sv'],
      List<String> includePaths = const ['/inc'],
      Map<String, String> defines = const {'X': '1', 'Y': '2'},
      String? topModule,
      HdlLanguage language = HdlLanguage.systemVerilog,
      String? binaryPath = '/usr/bin/verilator',
      EngineBinarySource binarySource = EngineBinarySource.system,
      Map<String, Object?> options = const {},
    }) => LintRunRequest(
      sourceFiles: sourceFiles,
      includePaths: includePaths,
      defines: defines,
      topModule: topModule,
      language: language,
      binary: EngineBinaryConfig(
        source: binarySource,
        path: binaryPath,
      ),
      options: options,
    );

    test('deterministic — same input produces same hash', () {
      final a = CacheFingerprint.configOf(req());
      final b = CacheFingerprint.configOf(req());
      expect(a, equals(b));
      expect(a.length, equals(64));
    });

    test('map key order does not change the hash', () {
      // Same logical map, different declaration order. Canonical
      // JSON sorts keys before hashing → identical digests.
      final a = CacheFingerprint.configOf(
        req(defines: const {'A': '1', 'B': '2', 'C': '3'}),
      );
      final b = CacheFingerprint.configOf(
        req(defines: const {'C': '3', 'A': '1', 'B': '2'}),
      );
      expect(a, equals(b));
    });

    test('source file ORDER affects the hash (order is significant)', () {
      final a = CacheFingerprint.configOf(
        req(sourceFiles: const ['/a.sv', '/b.sv']),
      );
      final b = CacheFingerprint.configOf(
        req(sourceFiles: const ['/b.sv', '/a.sv']),
      );
      expect(a, isNot(equals(b)));
    });

    test('include path ORDER affects the hash', () {
      final a = CacheFingerprint.configOf(
        req(includePaths: const ['/x', '/y']),
      );
      final b = CacheFingerprint.configOf(
        req(includePaths: const ['/y', '/x']),
      );
      expect(a, isNot(equals(b)));
    });

    test('language change invalidates the hash', () {
      // Default is HdlLanguage.systemVerilog; compare against vhdl.
      final a = CacheFingerprint.configOf(req());
      final b = CacheFingerprint.configOf(
        req(language: HdlLanguage.vhdl),
      );
      expect(a, isNot(equals(b)));
    });

    test('top module change invalidates the hash', () {
      final a = CacheFingerprint.configOf(req(topModule: 'top'));
      final b = CacheFingerprint.configOf(req(topModule: 'other'));
      expect(a, isNot(equals(b)));
    });

    test('binary source change invalidates the hash', () {
      // Default is EngineBinarySource.system; compare against custom.
      final a = CacheFingerprint.configOf(req());
      final b = CacheFingerprint.configOf(
        req(binarySource: EngineBinarySource.custom),
      );
      expect(a, isNot(equals(b)));
    });

    test('options bag changes invalidate the hash', () {
      final a = CacheFingerprint.configOf(
        req(options: const {'foo': 1}),
      );
      final b = CacheFingerprint.configOf(
        req(options: const {'foo': 2}),
      );
      expect(a, isNot(equals(b)));
    });

    test('null options values are dropped (do not affect hash)', () {
      final a = CacheFingerprint.configOf(req());
      final b = CacheFingerprint.configOf(
        req(options: const {'unused': null}),
      );
      expect(a, equals(b));
    });
  });
  group('CacheFingerprint.configOf engine config files', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('lintcrux_cache_cfg_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    LintRunRequest request({Map<String, Object?> options = const {}}) =>
        LintRunRequest(
          sourceFiles: ['${root.path}/top.sv'],
          binary: const EngineBinaryConfig.system(),
          language: HdlLanguage.systemVerilog,
          projectRoot: root.path,
          options: options,
        );

    test('editing .rules.verible_lint changes the Verible key', () {
      final rules = File('${root.path}/.rules.verible_lint')
        ..writeAsStringSync('-line-length\n');
      final before = CacheFingerprint.configOf(request(), engineId: 'verible');
      rules.writeAsStringSync('+line-length=length:120\n');
      final after = CacheFingerprint.configOf(request(), engineId: 'verible');
      expect(after, isNot(before));
    });

    test('creating .svlint.toml changes the Svlint key', () {
      final before = CacheFingerprint.configOf(request(), engineId: 'svlint');
      File('${root.path}/.svlint.toml').writeAsStringSync('[option]\n');
      final after = CacheFingerprint.configOf(request(), engineId: 'svlint');
      expect(after, isNot(before));
    });

    test('an explicit Svlint configPath is the file that is hashed', () {
      final custom = File('${root.path}/lint/custom.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('a');
      final req = request(options: {'configPath': custom.path});
      final before = CacheFingerprint.configOf(req, engineId: 'svlint');
      custom.writeAsStringSync('b');
      expect(CacheFingerprint.configOf(req, engineId: 'svlint'), isNot(before));
    });

    test('an engine with no config file keeps the key it had', () {
      File('${root.path}/.svlint.toml').writeAsStringSync('[option]\n');
      final verilator = CacheFingerprint.configOf(
        request(),
        engineId: 'verilator',
      );
      expect(verilator, CacheFingerprint.configOf(request()));
    });
  });
}
