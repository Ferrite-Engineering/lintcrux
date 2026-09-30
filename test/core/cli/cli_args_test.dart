// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args.dart';

void main() {
  group('CliArgs', () {
    test('empty is the zero value', () {
      const e = CliArgs.empty;
      expect(e.paths, isEmpty);
      expect(e.configPath, isNull);
      expect(e.sarifOutputPath, isNull);
      expect(e.exitCodeOnFindings, isFalse);
      expect(e.showHelp, isFalse);
      expect(e.showVersion, isFalse);
    });

    test('constructor stores all fields verbatim', () {
      const a = CliArgs(
        paths: ['a.v', 'b.sv'],
        configPath: 'cfg.yaml',
        sarifOutputPath: 'out.sarif',
        exitCodeOnFindings: true,
        showHelp: true,
        showVersion: true,
      );
      expect(a.paths, ['a.v', 'b.sv']);
      expect(a.configPath, 'cfg.yaml');
      expect(a.sarifOutputPath, 'out.sarif');
      expect(a.exitCodeOnFindings, isTrue);
      expect(a.showHelp, isTrue);
      expect(a.showVersion, isTrue);
    });

    test('copyWith replaces selected fields', () {
      const a = CliArgs(paths: ['a.v'], exitCodeOnFindings: true);
      final b = a.copyWith(sarifOutputPath: 'out.sarif');
      expect(b.paths, ['a.v']);
      expect(b.exitCodeOnFindings, isTrue);
      expect(b.sarifOutputPath, 'out.sarif');
    });

    test('== is structural across all fields', () {
      const a = CliArgs(paths: ['a.v', 'b.v'], configPath: 'c.yaml');
      const b = CliArgs(paths: ['a.v', 'b.v'], configPath: 'c.yaml');
      const c = CliArgs(paths: ['a.v'], configPath: 'c.yaml');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('toString includes every field', () {
      const a = CliArgs(
        paths: ['x'],
        configPath: 'c',
        sarifOutputPath: 's',
        exitCodeOnFindings: true,
        showHelp: true,
        showVersion: true,
      );
      final s = a.toString();
      expect(s, contains('paths: [x]'));
      expect(s, contains('config: c'));
      expect(s, contains('sarif: s'));
      expect(s, contains('exitCode: true'));
      expect(s, contains('help: true'));
      expect(s, contains('version: true'));
    });
  });
}
