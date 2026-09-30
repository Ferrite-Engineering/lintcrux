// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';

void main() {
  group('EditorCommand presets', () {
    test('VS Code preset matches `code -g {file}:{line}:{column}`', () {
      const c = EditorCommand.vsCode;
      expect(c.executable, 'code');
      expect(c.argsTemplate, ['-g', '{file}:{line}:{column}']);
      expect(
        c.render(file: '/a.sv', line: 12, column: 7),
        ['-g', '/a.sv:12:7'],
      );
    });

    test('Sublime preset matches `subl {file}:{line}:{column}`', () {
      const c = EditorCommand.sublime;
      expect(c.executable, 'subl');
      expect(
        c.render(file: '/a.sv', line: 12, column: 7),
        ['/a.sv:12:7'],
      );
    });

    test('Vim preset matches `vim +{line} {file}`', () {
      const c = EditorCommand.vim;
      expect(c.executable, 'vim');
      expect(c.render(file: '/a.sv', line: 12, column: 7), ['+12', '/a.sv']);
    });

    test('Emacs preset matches `emacs +{line} {file}`', () {
      const c = EditorCommand.emacs;
      expect(c.executable, 'emacs');
      expect(c.render(file: '/a.sv', line: 12, column: 7), ['+12', '/a.sv']);
    });

    test('default preset is VS Code', () {
      expect(EditorCommand.defaultPreset, EditorCommand.vsCode);
    });
  });

  group('EditorCommand custom', () {
    test('custom preset substitutes all placeholders in every arg', () {
      const c = EditorCommand(
        preset: EditorPreset.custom,
        executable: 'myedit',
        argsTemplate: ['--file={file}', '--line={line}', '--col={column}'],
      );
      expect(
        c.render(file: '/foo.sv', line: 9, column: 3),
        ['--file=/foo.sv', '--line=9', '--col=3'],
      );
    });

    test('args with no placeholders pass through unchanged', () {
      const c = EditorCommand(
        preset: EditorPreset.custom,
        executable: 'myedit',
        argsTemplate: ['--mode', 'edit', '{file}'],
      );
      expect(
        c.render(file: '/a.sv', line: 1, column: 1),
        ['--mode', 'edit', '/a.sv'],
      );
    });
  });

  group('EditorCommand serialization', () {
    test('round-trips through toJson / fromJson', () {
      const c = EditorCommand(
        preset: EditorPreset.custom,
        executable: 'myedit',
        argsTemplate: ['-x', '{file}:{line}'],
      );
      final out = EditorCommand.fromJson(c.toJson());
      expect(out, c);
    });

    test('falls back to defaultPreset on missing fields', () {
      expect(
        EditorCommand.fromJson(const <String, Object?>{}),
        EditorCommand.defaultPreset,
      );
    });

    test('falls back to defaultPreset on wrong types', () {
      expect(
        EditorCommand.fromJson(const <String, Object?>{
          'preset': 'vsCode',
          'executable': 7,
          'argsTemplate': ['x'],
        }),
        EditorCommand.defaultPreset,
      );
    });

    test('falls back to defaultPreset on empty arg list', () {
      expect(
        EditorCommand.fromJson(const <String, Object?>{
          'preset': 'vsCode',
          'executable': 'code',
          'argsTemplate': <String>[],
        }),
        EditorCommand.defaultPreset,
      );
    });
  });

  group('EditorCommand equality and copyWith', () {
    test('equality is by value', () {
      const a = EditorCommand(
        preset: EditorPreset.vsCode,
        executable: 'code',
        argsTemplate: ['-g', '{file}:{line}'],
      );
      const b = EditorCommand(
        preset: EditorPreset.vsCode,
        executable: 'code',
        argsTemplate: ['-g', '{file}:{line}'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality on any differing field', () {
      const a = EditorCommand(
        preset: EditorPreset.vsCode,
        executable: 'code',
        argsTemplate: ['-g'],
      );
      const b = EditorCommand(
        preset: EditorPreset.vsCode,
        executable: 'code-insiders',
        argsTemplate: ['-g'],
      );
      expect(a, isNot(equals(b)));
    });

    test('copyWith returns a copy with overridden fields', () {
      const c = EditorCommand.vsCode;
      final out = c.copyWith(executable: 'cursor');
      expect(out.executable, 'cursor');
      expect(out.preset, c.preset);
      expect(out.argsTemplate, c.argsTemplate);
    });
  });
}
