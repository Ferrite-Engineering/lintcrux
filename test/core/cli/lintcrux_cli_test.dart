// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/app_info/build_info.dart';
import 'package:lintcrux/core/cli/cli_exit_codes.dart';
import 'package:lintcrux/core/cli/lintcrux_cli.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/yosys/yosys_signal_reaper.dart';
import 'package:lintcrux/services/headless/headless_signal_guard.dart';
import 'package:path/path.dart' as p;

import '../../support/signal_fakes.dart';

/// An engine that always reports nothing, successfully.
class _SilentEngine implements LintEngine {
  @override
  String get id => 'silent';
  @override
  String get displayName => 'Silent';
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog, HdlLanguage.verilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => '1.0.0';
  @override
  Stream<Violation> run(LintRunRequest request) => const Stream.empty();
  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => const Stream.empty();
  @override
  void cancel() {}
}

/// An engine that is still running until [release] completes, or until a
/// bound runs out so a guard that never fires fails the test instead of
/// hanging it.
class _WaitingEngine extends _SilentEngine {
  _WaitingEngine(this.release);

  final Completer<void> release;

  @override
  String get id => 'waiting';

  @override
  Stream<Violation> run(LintRunRequest request) async* {
    await release.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }
}

void main() {
  late Directory tmp;
  late List<String> out;
  late List<String> err;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_cli_');
    out = <String>[];
    err = <String>[];
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // `installSignalReaper: false` throughout — the reaper attaches
  // process-wide SIGINT/SIGTERM handlers, and a test suite that
  // installs one per case ends up fighting the test runner for them.
  LintcruxCli cli() => LintcruxCli(
    registry: EngineRegistry(<LintEngine>[_SilentEngine()]),
    installSignalReaper: false,
  );

  Future<int> run(List<String> args) => cli().run(
    args,
    stdoutSink: out.add,
    stderrSink: err.add,
  );

  group('--help / --version', () {
    test('--help prints usage and exits 0', () async {
      expect(await run(<String>['--help']), CliExitCode.clean);
      expect(out.join('\n'), contains('Usage: lintcrux'));
      expect(err, isEmpty);
    });

    test('the usage block documents every exit code', () async {
      await run(<String>['--help']);
      final usage = out.join('\n');
      for (final code in CliExitCode.all) {
        expect(
          usage,
          contains(
            RegExp(
              r'^\s*'
              '$code'
              r'\s',
              multiLine: true,
            ),
          ),
          reason: 'exit code $code must appear in --help',
        );
      }
    });

    test('the usage block documents the CI flags', () async {
      await run(<String>['--help']);
      final usage = out.join('\n');
      for (final flag in <String>[
        '--top',
        '--engine',
        '--export',
        '--out',
        '--sarif',
        '--baseline',
        '--exit-code',
        '--fail-on-new-violations',
        '--allow-missing-engines',
        '--config',
      ]) {
        expect(usage, contains(flag), reason: flag);
      }
    });

    test('--version prints the product version and exits 0', () async {
      expect(await run(<String>['--version']), CliExitCode.clean);
      expect(out.single, LintCruxBuildInfo.versionLine);
      expect(out.single, startsWith('lintcrux '));
    });

    test(
      '--version prints the line the host binary names itself with',
      () async {
        // A second binary built on this class must not introduce itself as
        // `lintcrux`: the name in the banner is the name a user types to run it.
        final host = LintcruxCli(
          registry: EngineRegistry(<LintEngine>[_SilentEngine()]),
          installSignalReaper: false,
          versionLine: 'hostcli 9.9.9',
        );
        final code = await host.run(
          const <String>['--version'],
          stdoutSink: out.add,
          stderrSink: err.add,
        );
        expect(code, CliExitCode.clean);
        expect(out.single, 'hostcli 9.9.9');
      },
    );

    test('a host preamble leads the usage block, on stdout', () async {
      final host = LintcruxCli(
        registry: EngineRegistry(<LintEngine>[_SilentEngine()]),
        installSignalReaper: false,
        usagePreamble: 'Usage: hostcli [options]',
      );
      final code = await host.run(
        const <String>['--help'],
        stdoutSink: out.add,
        stderrSink: err.add,
      );
      expect(code, CliExitCode.clean);
      expect(out.first, 'Usage: hostcli [options]');
      expect(out.join('\n'), contains('Usage: lintcrux'));
      expect(err, isEmpty);
    });

    test('isHelpOrVersion is the decision run makes', () async {
      // A host that has to answer these two before doing its own work (a
      // licence lookup, say) asks this predicate first. If it ever disagreed
      // with `run`, the host would skip its work for a command line that then
      // went on to lint.
      for (final args in <List<String>>[
        <String>['--help'],
        <String>['-h'],
        <String>['--version'],
        <String>['design.lintcrux', '--help'],
        <String>['--reset', '--version'],
        <String>['design.lintcrux'],
        <String>['--nope', '--help'],
        const <String>[],
      ]) {
        out.clear();
        err.clear();
        final predicted = LintcruxCli.isHelpOrVersion(args);
        final code = await run(args);
        final answered =
            code == CliExitCode.clean &&
            out.isNotEmpty &&
            (out.first.startsWith('Usage: ') ||
                out.first == LintCruxBuildInfo.versionLine);
        expect(predicted, answered, reason: args.join(' '));
      }
    });
  });

  group('the desktop launch flags', () {
    // `--reset` and `--no-restore` recover a wedged desktop session. A shell
    // alias or wrapper script shared between the app and this binary passes
    // them here too, and there is no session here to reset: accepted, and
    // nothing done. Rejecting them with 64 broke exactly those wrappers.
    // The first-launch testing aids (`--reset-eula`,
    // `--reset-telemetry-consent`) are desktop-only for the same reason: the
    // headless binary presents neither dialog, so it accepts and ignores them.
    String cleanProject() {
      File(
        p.join(tmp.path, 'top.sv'),
      ).writeAsStringSync('module top;endmodule');
      final project = File(p.join(tmp.path, 'p.lintcrux'))
        ..writeAsStringSync('''
{"version":1,"name":"p","rootPath":".","sourceFiles":["top.sv"],
 "language":"systemverilog","enabledEngineIds":["silent"]}
''');
      return project.path;
    }

    for (final flag in <String>[
      '--reset',
      '--no-restore',
      '--reset-eula',
      '--reset-telemetry-consent',
    ]) {
      test('$flag is accepted and changes nothing', () async {
        final code = await run(<String>[flag, cleanProject(), '--exit-code']);
        expect(err.join('\n'), isNot(contains('Could not find an option')));
        expect(code, CliExitCode.clean);
        expect(out.last, contains('exit 0: clean'));
      });
    }

    test('help is still answered beside them', () async {
      final code = await run(<String>['--no-restore', '--help', '--reset']);
      expect(code, CliExitCode.clean);
      expect(out.join('\n'), contains('Usage: lintcrux'));
      expect(err, isEmpty);
    });
  });

  group('argument errors', () {
    test('an unknown flag exits 64 and prints usage to stderr', () async {
      expect(await run(<String>['--nope']), CliExitCode.usage);
      expect(err.join('\n'), contains('Could not find an option'));
      expect(err.join('\n'), contains('Usage: lintcrux'));
      expect(out, isEmpty);
    });

    test('--export without --out exits 64', () async {
      expect(
        await run(<String>['--export', 'sarif']),
        CliExitCode.usage,
      );
      expect(err.join('\n'), contains('--out'));
    });

    test('--out without --export exits 64', () async {
      expect(await run(<String>['--out', 'x.sarif']), CliExitCode.usage);
      expect(err.join('\n'), contains('--export'));
    });

    test('an unknown --export format exits 64', () async {
      expect(
        await run(<String>['--export', 'xml', '--out', 'x']),
        CliExitCode.usage,
      );
    });

    test('an unusable positional exits 64 rather than passing', () async {
      final txt = File(p.join(tmp.path, 'notes.txt'))..writeAsStringSync('');
      expect(await run(<String>[txt.path]), CliExitCode.usage);
      expect(err.join('\n'), contains('notes.txt'));
    });

    test('no arguments at all exits 64', () async {
      expect(await run(const <String>[]), CliExitCode.usage);
    });
  });

  group('--import-filelist', () {
    test('converts a filelist and lints the emitted project', () async {
      File(
        p.join(tmp.path, 'top.sv'),
      ).writeAsStringSync('module top;endmodule');
      final filelist = File(p.join(tmp.path, 'rtl.f'))
        ..writeAsStringSync('top.sv\n');
      final code = await run(<String>['--import-filelist', filelist.path]);
      expect(out.first, startsWith('Imported filelist'));
      expect(File(p.join(tmp.path, 'rtl.lintcrux')).existsSync(), isTrue);
      expect(code, CliExitCode.clean);
    });

    test('a broken filelist exits 65, matching the GUI front door', () async {
      final code = await run(<String>[
        '--import-filelist',
        p.join(tmp.path, 'missing.f'),
      ]);
      expect(code, CliExitCode.dataError);
      expect(err.join('\n'), isNotEmpty);
    });
  });

  group('--import-edam', () {
    test('converts an EDAM and lints the emitted project', () async {
      File(
        p.join(tmp.path, 'top.sv'),
      ).writeAsStringSync('module top;endmodule');
      final edam = File(p.join(tmp.path, 'design.eda.yml'))
        ..writeAsStringSync('''
version: 0.2.1
name: design
toplevel: top
files:
- {file_type: systemVerilogSource, name: top.sv}
''');
      final code = await run(<String>['--import-edam', edam.path]);
      expect(out.first, startsWith('Imported EDAM'));
      expect(File(p.join(tmp.path, 'design.lintcrux')).existsSync(), isTrue);
      expect(code, CliExitCode.clean);
    });

    test('reader warnings are printed to stderr without failing the '
        'run', () async {
      File(
        p.join(tmp.path, 'top.sv'),
      ).writeAsStringSync('module top;endmodule');
      final edam = File(p.join(tmp.path, 'warny.eda.yml'))
        ..writeAsStringSync('''
version: 0.9.9
name: warny
files:
- {file_type: systemVerilogSource, name: top.sv}
''');
      final code = await run(<String>['--import-edam', edam.path]);
      expect(code, CliExitCode.clean);
      expect(err.join('\n'), contains('lintcrux: warning:'));
      expect(err.join('\n'), contains('0.9.9'));
    });

    test('a broken EDAM exits 65, matching the GUI front door', () async {
      final code = await run(<String>[
        '--import-edam',
        p.join(tmp.path, 'missing.eda.yml'),
      ]);
      expect(code, CliExitCode.dataError);
      expect(err.join('\n'), isNotEmpty);
    });
  });

  group('a cancelled run', () {
    test('reaps the engines and exits 128+N through the guard', () async {
      final registry = ProcessRegistry();
      final child = KillRecordingProcess();
      registry.register(child);
      final signalled = Completer<void>();
      final exits = <int>[];

      final host = LintcruxCli(
        registry: EngineRegistry(<LintEngine>[_WaitingEngine(signalled)]),
        signalGuard: HeadlessSignalGuard(
          programName: 'hostcli',
          reaperFactory: () => YosysSignalReaper(
            registry: registry,
            watch: deliverOnListen(ProcessSignal.sigint),
          ),
          exitWith: (code) {
            exits.add(code);
            if (!signalled.isCompleted) signalled.complete();
          },
        ),
      );
      File(
        p.join(tmp.path, 'top.sv'),
      ).writeAsStringSync('module top;endmodule');
      File(p.join(tmp.path, 'p.lintcrux')).writeAsStringSync('''
{"version":1,"name":"p","rootPath":".","sourceFiles":["top.sv"],
 "language":"systemverilog","enabledEngineIds":["waiting"]}
''');

      await host.run(
        <String>[p.join(tmp.path, 'p.lintcrux')],
        stdoutSink: out.add,
        stderrSink: err.add,
      );

      expect(exits, <int>[130]);
      expect(child.kills, <ProcessSignal>[ProcessSignal.sigkill]);
      expect(err, contains('hostcli: received SIGINT, terminating'));
    });
  });

  group('a real (empty) lint run', () {
    test('a clean project exits 0 even with --exit-code', () async {
      File(
        p.join(tmp.path, 'top.sv'),
      ).writeAsStringSync('module top;endmodule');
      File(p.join(tmp.path, 'p.lintcrux')).writeAsStringSync('''
{"version":1,"name":"p","rootPath":".","sourceFiles":["top.sv"],
 "language":"systemverilog","enabledEngineIds":["silent"]}
''');
      final code = await run(<String>[
        p.join(tmp.path, 'p.lintcrux'),
        '--exit-code',
      ]);
      expect(code, CliExitCode.clean);
      expect(out.last, contains('no violations'));
      expect(out.last, contains('exit 0: clean'));
    });
  });
}
