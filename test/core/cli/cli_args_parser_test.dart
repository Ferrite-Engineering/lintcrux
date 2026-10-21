// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/cli/cli_args_parser.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';

void main() {
  group('CliArgsParser', () {
    final parser = CliArgsParser();

    test('no args yields the empty result', () {
      final r = parser.parse(const <String>[]);
      expect(r.isSuccess, isTrue);
      expect(r.args!.paths, isEmpty);
      expect(r.args!.configPath, isNull);
      expect(r.args!.sarifOutputPath, isNull);
      expect(r.args!.exitCodeOnFindings, isFalse);
      expect(r.args!.showHelp, isFalse);
      expect(r.args!.showVersion, isFalse);
    });

    test('positional paths are preserved in order', () {
      final r = parser.parse(const ['a.v', 'b.sv', 'project.lintcrux']);
      expect(r.isSuccess, isTrue);
      expect(r.args!.paths, ['a.v', 'b.sv', 'project.lintcrux']);
    });

    test('--config / -c reads the next token as the YAML path', () {
      final long = parser.parse(const ['--config', 'team.yaml']);
      final short = parser.parse(const ['-c', 'team.yaml']);
      final equal = parser.parse(const ['--config=team.yaml']);
      expect(long.args!.configPath, 'team.yaml');
      expect(short.args!.configPath, 'team.yaml');
      expect(equal.args!.configPath, 'team.yaml');
    });

    test('--sarif accepts a path', () {
      final r = parser.parse(const ['--sarif', 'out.sarif']);
      expect(r.args!.sarifOutputPath, 'out.sarif');
    });

    test('--exit-code is a flag and not negatable', () {
      final r = parser.parse(const ['--exit-code']);
      expect(r.args!.exitCodeOnFindings, isTrue);
      final neg = parser.parse(const ['--no-exit-code']);
      expect(neg.isSuccess, isFalse);
      expect(neg.error, isNotNull);
    });

    test('--help and -h set showHelp', () {
      expect(parser.parse(const ['--help']).args!.showHelp, isTrue);
      expect(parser.parse(const ['-h']).args!.showHelp, isTrue);
    });

    test('--version sets showVersion', () {
      expect(parser.parse(const ['--version']).args!.showVersion, isTrue);
    });

    test('positional + flags can be intermixed', () {
      final r = parser.parse(const [
        'a.v',
        '--config',
        'team.yaml',
        'b.sv',
        '--sarif',
        'out.sarif',
        '--exit-code',
      ]);
      expect(r.isSuccess, isTrue);
      expect(r.args!.paths, ['a.v', 'b.sv']);
      expect(r.args!.configPath, 'team.yaml');
      expect(r.args!.sarifOutputPath, 'out.sarif');
      expect(r.args!.exitCodeOnFindings, isTrue);
    });

    test('unknown flag produces a parse error with usage text', () {
      final r = parser.parse(const ['--no-such-flag']);
      expect(r.isSuccess, isFalse);
      expect(r.error, contains('--no-such-flag'));
      expect(r.usage, contains('Usage: lintcrux'));
    });

    test('the first-launch reset flags parse and are documented', () {
      for (final flag in <String>[
        '--reset-eula',
        '--reset-telemetry-consent',
      ]) {
        final r = parser.parse(<String>[flag, 'project.lintcrux']);
        expect(r.isSuccess, isTrue, reason: flag);
        expect(r.args!.paths, <String>['project.lintcrux'], reason: flag);
        expect(parser.usage, contains(flag));
      }
    });

    test('missing value for --config produces a parse error', () {
      final r = parser.parse(const ['--config']);
      expect(r.isSuccess, isFalse);
      expect(r.error, isNotNull);
    });

    test('usage block documents every flag the parser accepts', () {
      final u = parser.usage;
      expect(u, contains('Usage: lintcrux'));
      expect(u, contains('--config'));
      expect(u, contains('--sarif'));
      expect(u, contains('--exit-code'));
      expect(u, contains('--help'));
      expect(u, contains('--version'));
      expect(u, contains('--import-filelist'));
      expect(u, contains('--import-edam'));
      expect(u, contains('--engine-timeout'));
      expect(u, contains('Default 300'));
      // Examples block helps first-time users.
      expect(u, contains('lintcrux project.lintcrux'));
    });

    group('--constraints', () {
      test('is empty by default', () {
        expect(parser.parse(const []).args!.constraintFiles, isEmpty);
      });

      test(
        'is repeatable and order-preserving, with any case of extension',
        () {
          final r = parser.parse(const [
            '--constraints',
            'a.pcf',
            '--constraints=B.LPF',
            '--constraints',
            'c.cst',
            'top.v',
          ]);
          expect(r.args!.constraintFiles, ['a.pcf', 'B.LPF', 'c.cst']);
          expect(r.args!.paths, ['top.v']);
        },
      );

      test('an extension that is none of the three is a usage error', () {
        final r = parser.parse(const ['--constraints', 'timing.sdc']);
        expect(r.isSuccess, isFalse);
        expect(r.error, contains('timing.sdc'));
        expect(r.error, contains('.pcf, .lpf, .cst'));
      });

      test('no extension at all is a usage error, not a guess', () {
        expect(
          parser.parse(const ['--constraints', 'pins']).isSuccess,
          isFalse,
        );
      });

      test('a missing value is a usage error', () {
        expect(parser.parse(const ['--constraints']).isSuccess, isFalse);
      });

      test('is documented', () {
        expect(parser.usage, contains('--constraints'));
        expect(parser.usage, contains('lintcrux top.v --top top'));
      });
    });

    group('--sarif-root', () {
      test('is absent by default, leaving the writer its own detection', () {
        expect(parser.parse(const []).args!.sarifRoot, isNull);
      });

      test('captures the directory', () {
        final r = parser.parse(const ['--sarif-root', '/ci/checkout', 'a.sv']);
        expect(r.isSuccess, isTrue, reason: r.error);
        expect(r.args!.sarifRoot, '/ci/checkout');
      });

      test('an empty value reads as absent', () {
        expect(
          parser.parse(const ['--sarif-root', '', 'a.sv']).args!.sarifRoot,
          isNull,
        );
      });

      test('is documented', () {
        expect(parser.usage, contains('--sarif-root'));
      });
    });

    group('--engine-timeout', () {
      test('is absent by default, leaving the runner its own budget', () {
        expect(parser.parse(const []).args!.engineTimeout, isNull);
      });

      test('reads a whole number of seconds', () {
        final r = parser.parse(const ['--engine-timeout', '1800', 'a.sv']);
        expect(r.isSuccess, isTrue, reason: r.error);
        expect(r.args!.engineTimeout, const Duration(seconds: 1800));
        expect(r.args!.paths, ['a.sv']);
      });

      for (final bad in const <String>['0', '-5', '2.5', '5m', 'soon']) {
        test('"$bad" is a usage error, not a silent default', () {
          final r = parser.parse(['--engine-timeout', bad, 'a.sv']);
          expect(r.isSuccess, isFalse);
          expect(r.error, contains('--engine-timeout'));
          expect(r.error, contains('"$bad"'));
        });
      }

      test('a missing value is a usage error', () {
        expect(parser.parse(const ['--engine-timeout']).isSuccess, isFalse);
      });
    });

    test('--import-filelist accepts a path', () {
      final r = parser.parse(const ['--import-filelist', 'rtl.f']);
      expect(r.isSuccess, isTrue);
      expect(r.args!.importFilelistPath, 'rtl.f');
    });

    test('--import-filelist defaults to null when absent', () {
      final r = parser.parse(const <String>[]);
      expect(r.args!.importFilelistPath, isNull);
    });

    test('--import-edam accepts a path', () {
      final r = parser.parse(const ['--import-edam', 'design.eda.yml']);
      expect(r.isSuccess, isTrue);
      expect(r.args!.importEdamPath, 'design.eda.yml');
    });

    test('--import-edam defaults to null when absent', () {
      final r = parser.parse(const <String>[]);
      expect(r.args!.importEdamPath, isNull);
    });

    test('--<engine>-path flags populate engineBinaryPaths', () {
      final r = parser.parse(const [
        '--verilator-path',
        '/opt/verilator',
        '--ghdl-path=/opt/ghdl',
        '--svlint-path',
        '/opt/svlint',
      ]);
      expect(r.isSuccess, isTrue);
      expect(r.args!.engineBinaryPaths, {
        'verilator': '/opt/verilator',
        'ghdl': '/opt/ghdl',
        'svlint': '/opt/svlint',
      });
    });

    test('engineBinaryPaths defaults to empty when no flags provided', () {
      final r = parser.parse(const <String>[]);
      expect(r.args!.engineBinaryPaths, isEmpty);
    });

    test('--workspace accepts a path', () {
      final r = parser.parse([
        '--workspace',
        '/team/release.lintcrux-workspace',
      ]);
      expect(r.isSuccess, isTrue);
      expect(r.args!.workspacePath, '/team/release.lintcrux-workspace');
    });

    test('--workspace defaults to null when absent', () {
      final r = parser.parse(const <String>[]);
      expect(r.args!.workspacePath, isNull);
    });

    test('--session accepts a path (regression)', () {
      final r = parser.parse(['--session', '/team/dbg.lintcrux-session']);
      expect(r.isSuccess, isTrue);
      expect(r.args!.sessionPath, '/team/dbg.lintcrux-session');
    });

    test('--workspace and --session combine in one invocation', () {
      final r = parser.parse([
        '--workspace',
        '/team/main.lintcrux-workspace',
        '--session',
        '/team/dbg.lintcrux-session',
        '/p/extra.lintcrux',
      ]);
      expect(r.isSuccess, isTrue);
      expect(r.args!.workspacePath, '/team/main.lintcrux-workspace');
      expect(r.args!.sessionPath, '/team/dbg.lintcrux-session');
      expect(r.args!.paths, ['/p/extra.lintcrux']);
    });

    group('CI flags', () {
      test('--top is captured', () {
        expect(
          parser.parse(['--top', 'top_module']).args!.topModule,
          'top_module',
        );
        expect(
          parser.parse(['--top=top_module']).args!.topModule,
          'top_module',
        );
      });

      test('--engine help names every shipped engine, cdc included', () {
        final usage = parser.usage.replaceAll(RegExp(r'\s+'), ' ');
        for (final id in defaultEngineRegistry().engineIds) {
          expect(usage, contains(id), reason: id);
        }
        expect(usage, contains('svlint, cdc'));
      });

      test('--engine is repeatable and order-preserving', () {
        final r = parser.parse([
          '--engine',
          'verilator',
          '--engine',
          'verible',
        ]);
        expect(r.args!.engineIds, ['verilator', 'verible']);
      });

      test('--export + --out are captured as a pair', () {
        final r = parser.parse(['--export', 'sarif', '--out', 'lint.sarif']);
        expect(r.args!.exportFormat, 'sarif');
        expect(r.args!.exportOutputPath, 'lint.sarif');
        expect(r.args!.sarifOutputPath, 'lint.sarif');
      });

      test('--sarif is normalized into the --export/--out pair', () {
        // Downstream code must have exactly one shape to read, not two.
        final r = parser.parse(['--sarif', 'lint.sarif']);
        expect(r.args!.exportFormat, 'sarif');
        expect(r.args!.exportOutputPath, 'lint.sarif');
      });

      test('--export without --out is a usage error, not a silent skip', () {
        // A CI step that meant to produce an upload artifact and produced
        // nothing must fail loudly.
        final r = parser.parse(['--export', 'sarif']);
        expect(r.isSuccess, isFalse);
        expect(r.error, contains('--out'));
      });

      test('--out without --export is a usage error', () {
        final r = parser.parse(['--out', 'lint.sarif']);
        expect(r.isSuccess, isFalse);
        expect(r.error, contains('--export'));
      });

      test('an unknown --export format is rejected by name', () {
        final r = parser.parse(['--export', 'xml', '--out', 'x']);
        expect(r.isSuccess, isFalse);
      });

      test('every advertised export format parses', () {
        for (final f in CliArgsParser.kExportFormats) {
          final r = parser.parse(['--export', f, '--out', 'o']);
          expect(r.isSuccess, isTrue, reason: f);
          expect(r.args!.exportFormat, f);
        }
      });

      test('sarifOutputPath is null for non-SARIF exports', () {
        final r = parser.parse(['--export', 'csv', '--out', 'o.csv']);
        expect(r.args!.exportOutputPath, 'o.csv');
        expect(r.args!.sarifOutputPath, isNull);
      });

      test('the gate flags default off and are negatable-free', () {
        final none = parser.parse(const <String>[]).args!;
        expect(none.failOnNewViolations, isFalse);
        expect(none.allowMissingEngines, isFalse);
        expect(none.quiet, isFalse);

        final all = parser.parse([
          '--fail-on-new-violations',
          '--allow-missing-engines',
          '--exit-code',
          '--quiet',
        ]).args!;
        expect(all.failOnNewViolations, isTrue);
        expect(all.allowMissingEngines, isTrue);
        expect(all.exitCodeOnFindings, isTrue);
        expect(all.quiet, isTrue);
      });

      test('--baseline is captured', () {
        final r = parser.parse(['--baseline', 'ci/base.json']);
        expect(r.args!.baselinePath, 'ci/base.json');
      });

      test('the usage block names the headless binary and exit codes', () {
        expect(parser.usage, contains('bin/lintcrux.dart'));
        expect(parser.usage, contains('Exit codes:'));
      });
    });
  });
}
