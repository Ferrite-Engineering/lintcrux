// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/custom_regex_rule.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/named_filter_preset.dart';
import 'package:lintcrux/domain/models/project_source_file.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';

void main() {
  group('ProjectFileCodec', () {
    const codec = ProjectFileCodec();

    test('round-trips a minimal project unchanged', () {
      const project = LintProject(name: 'minimal', rootPath: '/tmp/minimal');
      final encoded = codec.encode(project);
      final decoded = codec.decode(encoded);
      expect(decoded, project);
    });

    test('round-trips a fully populated project unchanged', () {
      const project = LintProject(
        name: 'soc',
        rootPath: '/work/soc',
        sourceFiles: ['/work/soc/a.sv', '/work/soc/b.sv'],
        includePaths: ['/work/soc/inc'],
        defines: {'WIDTH': '32', 'DEBUG': '1'},
        topModule: 'soc_top',
        enabledEngineIds: ['verilator', 'verible'],
        severityOverrides: {
          'verilator/UNUSEDSIGNAL': Severity.error,
          'verible/no-tabs': Severity.note,
        },
        perEngineOptions: {
          'verilator': {'extraArgs': '-Wall -Wpedantic'},
          'verible': {'rulesConfigSearch': true},
        },
      );
      final decoded = codec.decode(codec.encode(project));
      expect(decoded, project);
    });

    test('writes a stable version field', () {
      const project = LintProject(name: 'x', rootPath: '/y');
      final encoded = codec.encode(project);
      expect(encoded, contains('"version": 1'));
    });

    test('preserves source-file order', () {
      const project = LintProject(
        name: 'p',
        rootPath: '/r',
        sourceFiles: ['/r/c.v', '/r/a.v', '/r/b.v'],
      );
      final decoded = codec.decode(codec.encode(project));
      expect(decoded.sourceFiles, ['/r/c.v', '/r/a.v', '/r/b.v']);
    });

    test('decode silently ignores unknown top-level keys', () {
      const jsonStr = '''
{
  "version": 1,
  "name": "x",
  "rootPath": "/y",
  "futureField": "ignored",
  "experimentalFlag": true
}
''';
      final decoded = codec.decode(jsonStr);
      expect(decoded.name, 'x');
      expect(decoded.rootPath, '/y');
    });

    test('decode silently ignores unknown keys in nested options bags', () {
      const jsonStr = '''
{
  "version": 1,
  "name": "x",
  "rootPath": "/y",
  "perEngineOptions": {
    "verilator": {"knownKey": 1, "futureKey": [1, 2, 3]}
  }
}
''';
      final decoded = codec.decode(jsonStr);
      expect(decoded.perEngineOptions['verilator']?['knownKey'], 1);
      expect(decoded.perEngineOptions['verilator']?['futureKey'], [1, 2, 3]);
    });

    test('decode rejects malformed JSON', () {
      expect(
        () => codec.decode('{not json'),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode rejects non-object top level', () {
      expect(
        () => codec.decode('[]'),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode rejects missing version', () {
      expect(
        () => codec.decode('{"name": "x", "rootPath": "/y"}'),
        throwsA(
          isA<ProjectFileException>().having(
            (e) => e.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });

    test('decode rejects unknown major version', () {
      expect(
        () => codec.decode(
          '{"version": 99, "name": "x", "rootPath": "/y"}',
        ),
        throwsA(
          isA<ProjectFileException>().having(
            (e) => e.message,
            'message',
            contains('unsupported schema version 99'),
          ),
        ),
      );
    });

    test('decode rejects missing name', () {
      expect(
        () => codec.decode('{"version": 1, "rootPath": "/y"}'),
        throwsA(
          isA<ProjectFileException>().having(
            (e) => e.message,
            'message',
            contains('name'),
          ),
        ),
      );
    });

    test('decode rejects missing rootPath', () {
      expect(
        () => codec.decode('{"version": 1, "name": "x"}'),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode rejects empty name', () {
      expect(
        () => codec.decode(
          '{"version": 1, "name": "", "rootPath": "/y"}',
        ),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode rejects wrong types for list fields', () {
      expect(
        () => codec.decode(
          '{"version": 1, "name": "x", "rootPath": "/y", '
          '"sourceFiles": "not a list"}',
        ),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode rejects unknown language', () {
      expect(
        () => codec.decode(
          '{"version": 1, "name": "x", "rootPath": "/y", '
          '"language": "klingon"}',
        ),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode rejects unknown severity', () {
      expect(
        () => codec.decode(
          '{"version": 1, "name": "x", "rootPath": "/y", '
          '"severityOverrides": {"r/x": "critical"}}',
        ),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('encode emits pretty-printed JSON', () {
      const project = LintProject(name: 'x', rootPath: '/y');
      final encoded = codec.encode(project);
      expect(encoded, contains('\n'));
      expect(encoded, contains('  ')); // 2-space indent
    });

    test('decode treats missing language as systemVerilog (the default)', () {
      const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y"}
''';
      final decoded = codec.decode(jsonStr);
      expect(decoded.language, HdlLanguage.systemVerilog);
    });

    test('decode handles every supported language', () {
      for (final lang in HdlLanguage.values) {
        const project = LintProject(name: 'x', rootPath: '/y');
        final encoded = codec.encode(project.copyWith(language: lang));
        expect(codec.decode(encoded).language, lang);
      }
    });

    test('decode handles every supported severity', () {
      for (final sev in Severity.values) {
        const project = LintProject(name: 'x', rootPath: '/y');
        final encoded = codec.encode(
          project.copyWith(
            severityOverrides: {'engine/rule': sev},
          ),
        );
        expect(codec.decode(encoded).severityOverrides['engine/rule'], sev);
      }
    });

    test('empty topModule string round-trips as null', () {
      // We never *encode* an empty topModule, but if some upstream tool
      // writes one, the decoder normalizes it to null.
      const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y", "topModule": ""}
''';
      final decoded = codec.decode(jsonStr);
      expect(decoded.topModule, isNull);
    });

    test('round-trips filterPresets unchanged', () {
      const project = LintProject(
        name: 'p',
        rootPath: '/r',
        filterPresets: [
          NamedFilterPreset(name: 'WIDTHs only', severities: {Severity.error}),
          NamedFilterPreset(name: 'Just verilator', engineIds: {'verilator'}),
        ],
      );
      final decoded = codec.decode(codec.encode(project));
      expect(decoded.filterPresets, hasLength(2));
      expect(decoded.filterPresets[0].name, 'WIDTHs only');
      expect(decoded.filterPresets[0].severities, {Severity.error});
      expect(decoded.filterPresets[1].name, 'Just verilator');
      expect(decoded.filterPresets[1].engineIds, {'verilator'});
    });

    test('decode of older file without filterPresets defaults to empty', () {
      const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y"}
''';
      final decoded = codec.decode(jsonStr);
      expect(decoded.filterPresets, isEmpty);
    });

    test('decode silently drops malformed filter-preset entries', () {
      const jsonStr = '''
{
  "version": 1,
  "name": "x",
  "rootPath": "/y",
  "filterPresets": [
    {"name": "good"},
    {"name": ""},
    {}
  ]
}
''';
      final decoded = codec.decode(jsonStr);
      expect(decoded.filterPresets, hasLength(1));
      expect(decoded.filterPresets.single.name, 'good');
    });

    test('round-trips sourceFileLanguages unchanged', () {
      const project = LintProject(
        name: 'mixed',
        rootPath: '/r',
        sourceFiles: ['/r/top.sv', '/r/legacy.v', '/r/dut.vhd'],
        sourceFileLanguages: {
          '/r/top.sv': ProjectSourceFileLanguage.systemVerilog,
          '/r/legacy.v': ProjectSourceFileLanguage.verilog,
          '/r/dut.vhd': ProjectSourceFileLanguage.vhdl,
        },
      );
      final decoded = codec.decode(codec.encode(project));
      expect(decoded.sourceFileLanguages, project.sourceFileLanguages);
    });

    test('round-trips sourceFileProvenance unchanged', () {
      const project = LintProject(
        name: 'edam',
        rootPath: '/r',
        sourceFiles: ['/r/src/serv_top.v'],
        sourceFileProvenance: {
          '/r/src/serv_top.v': 'award-winning:serv:serv:1.4.0',
        },
      );
      final decoded = codec.decode(codec.encode(project));
      expect(decoded.sourceFileProvenance, project.sourceFileProvenance);
    });

    test(
      'decode of an older file without sourceFileProvenance defaults to '
      'empty',
      () {
        const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y",
 "sourceFiles": ["/y/a.sv"]}
''';
        expect(codec.decode(jsonStr).sourceFileProvenance, isEmpty);
      },
    );

    test(
      'decode of an older file without sourceFileLanguages defaults to empty',
      () {
        const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y",
 "sourceFiles": ["/y/a.sv", "/y/b.v"]}
''';
        final decoded = codec.decode(jsonStr);
        expect(decoded.sourceFileLanguages, isEmpty);
        // The typed getter falls back to extension-based detection for
        // every file.
        final typed = decoded.sourceFilesTyped;
        expect(typed[0].language, ProjectSourceFileLanguage.auto);
        expect(typed[0].resolveLanguage(), HdlLanguage.systemVerilog);
        expect(typed[1].resolveLanguage(), HdlLanguage.verilog);
      },
    );

    test('decode rejects an unknown sourceFileLanguages value', () {
      const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y",
 "sourceFileLanguages": {"/y/a.sv": "klingon"}}
''';
      expect(() => codec.decode(jsonStr), throwsA(isA<ProjectFileException>()));
    });

    test('sourceFilesTyped respects explicit per-file language overrides', () {
      const project = LintProject(
        name: 'mixed',
        rootPath: '/r',
        sourceFiles: ['/r/legacy.v'],
        sourceFileLanguages: {
          '/r/legacy.v': ProjectSourceFileLanguage.systemVerilog,
        },
      );
      final typed = project.sourceFilesTyped;
      expect(typed.single.language, ProjectSourceFileLanguage.systemVerilog);
      expect(typed.single.resolveLanguage(), HdlLanguage.systemVerilog);
    });

    test('round-trips customRegexRules unchanged', () {
      const project = LintProject(
        name: 'p',
        rootPath: '/r',
        customRegexRules: [
          CustomRegexRule(
            id: 'no-todo',
            severity: Severity.warning,
            pattern: 'TODO',
            messageTemplate: 'TODO comment at {file}:{line}',
          ),
          CustomRegexRule(
            id: 'no-defparam',
            severity: Severity.error,
            pattern: r'\bdefparam\b',
            patternKind: CustomRulePatternKind.identifier,
            messageTemplate: 'defparam is forbidden',
            filePathGlob: '**/*.sv',
            enabled: false,
          ),
        ],
      );
      final decoded = codec.decode(codec.encode(project));
      expect(decoded.customRegexRules, project.customRegexRules);
    });

    test(
      'decode of an older file without customRegexRules defaults to empty',
      () {
        const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y"}
''';
        final decoded = codec.decode(jsonStr);
        expect(decoded.customRegexRules, isEmpty);
      },
    );

    test('decode rejects a customRegexRules entry with no id', () {
      const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y",
 "customRegexRules": [
   {"severity": "warning", "pattern": "x", "messageTemplate": "x"}
 ]}
''';
      expect(
        () => codec.decode(jsonStr),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode rejects a customRegexRules entry with no pattern', () {
      const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y",
 "customRegexRules": [
   {"id": "r", "severity": "warning", "messageTemplate": "x"}
 ]}
''';
      expect(
        () => codec.decode(jsonStr),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode rejects a customRegexRules entry with an unknown '
        'patternKind value', () {
      const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y",
 "customRegexRules": [
   {"id": "r", "severity": "warning", "pattern": "x",
    "messageTemplate": "x", "patternKind": "klingon"}
 ]}
''';
      expect(
        () => codec.decode(jsonStr),
        throwsA(isA<ProjectFileException>()),
      );
    });

    test('decode of a customRegexRules entry without patternKind defaults '
        'to source_text and enabled defaults to true', () {
      const jsonStr = '''
{"version": 1, "name": "x", "rootPath": "/y",
 "customRegexRules": [
   {"id": "r", "severity": "warning", "pattern": "x",
    "messageTemplate": "x"}
 ]}
''';
      final decoded = codec.decode(jsonStr);
      expect(decoded.customRegexRules, hasLength(1));
      expect(
        decoded.customRegexRules.single.patternKind,
        CustomRulePatternKind.sourceText,
      );
      expect(decoded.customRegexRules.single.enabled, isTrue);
    });
  });

  group('kProjectFileSchemaVersion', () {
    test('is 1 for the original schema', () {
      expect(kProjectFileSchemaVersion, 1);
    });
  });
}
