// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/process_runner.dart';

/// Spawn-layer guarantees for [SystemProcessRunner].
///
/// The `cleanEngineEnvironment` unit tests prove the environment *map* is
/// built correctly; these tests prove [SystemProcessRunner.start] actually
/// wires that map into the real `Process.start` call — the exact invocation
/// the availability probe uses (`engineVersionsProvider` →
/// `LintEngine.detectVersion` → `runner.start(<exe>, ['--version'])`).
void main() {
  group('SystemProcessRunner spawn layer', () {
    // A Finder/Dock launch inherits launchd's minimal PATH (no Homebrew). The
    // runner must augment it so the availability probe (`--version`) and the
    // real lint run resolve `/opt/homebrew/bin/verilator` without a terminal
    // relaunch or a Custom-path override. This is the end-to-end proof of the
    // Finder-launch PATH fix: we spawn a real subprocess with a Finder-style
    // minimal PATH and read back the PATH it actually received.
    test(
      'carries the augmented Homebrew PATH into the spawned process (macOS)',
      () async {
        const runner = SystemProcessRunner();
        // Echo the child's own PATH back on stdout.
        final proc = await runner.start(
          '/bin/sh',
          const ['-c', r'printf %s "$PATH"'],
          // Simulate the minimal PATH a Finder/Dock launch inherits.
          environment: const <String, String>{
            'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
          },
        );
        final out = (await proc.stdout.toList()).join();
        await proc.exitCode;

        final entries = out.split(':');
        expect(
          entries,
          containsAll(<String>['/opt/homebrew/bin', '/usr/local/bin']),
          reason:
              'the availability-probe spawn must expose Homebrew engine dirs '
              'as discrete PATH entries so a Finder launch resolves verilator',
        );
        // No malformed fused entry (the `Platform.pathSeparator` footgun).
        expect(entries.every((e) => !e.contains('//')), isTrue);
      },
      skip: Platform.isMacOS
          ? false
          : 'PATH augmentation is macOS-only (Finder/Dock launchd PATH)',
    );

    // The NO_COLOR contract rides the same spawn path — assert it end-to-end
    // too so a future refactor of the runner can't silently drop it.
    test(
      'injects NO_COLOR and TERM into the spawned process',
      () async {
        const runner = SystemProcessRunner();
        final proc = await runner.start(
          '/bin/sh',
          const ['-c', r'printf %s "$NO_COLOR|$TERM"'],
        );
        final out = (await proc.stdout.toList()).join();
        await proc.exitCode;
        expect(out, '1|dumb');
      },
      skip: Platform.isWindows ? 'POSIX shell fixture' : false,
    );
  });

  // Windows `CreateProcess` searches the *calling* process's current
  // directory before `PATH`, and LintCrux never moves its own. A developer
  // who launched it with `cd rtl-repo && lintcrux.exe` would otherwise hand
  // a `verible-verilog-lint.exe` committed to that repository priority over
  // every copy on `PATH`. The runner resolves through `crux_io`'s shared
  // spawn resolver; a Windows [SpawnHost] with a synthetic `PATH` and probe
  // proves that on any machine, so the guard does not wait for the weekly
  // Windows job.
  group('SystemProcessRunner on Windows', () {
    const path = r'C:\rtl-repo;C:\tools\oss-cad-suite\bin;C:\Windows\System32';

    SystemProcessRunner windowsRunner(
      Set<String> present, {
      Map<String, String> environment = const {'PATH': path},
    }) => SystemProcessRunner(
      host: SpawnHost(
        windows: true,
        environment: environment,
        exists: present.contains,
      ),
    );

    test('a bare engine name is spawned by its absolute PATH hit', () {
      expect(
        windowsRunner(<String>{
          r'C:\tools\oss-cad-suite\bin\verible-verilog-lint.EXE',
        }).spawnExecutableFor('verible-verilog-lint', environment: const {}),
        r'C:\tools\oss-cad-suite\bin\verible-verilog-lint.EXE',
      );
    });

    test('a planted binary in the launch folder cannot displace PATH', () {
      final exe = windowsRunner(<String>{
        r'C:\tools\oss-cad-suite\bin\verilator.EXE',
      }).spawnExecutableFor('verilator', environment: const {});
      expect(exe, r'C:\tools\oss-cad-suite\bin\verilator.EXE');
      expect(exe, isNot(contains('rtl-repo')));
    });

    test(
      "the child's augmented PATH is searched, in Windows' Path spelling",
      () {
        // The engine environment appends the engine search directories to
        // PATH, and Windows spells the variable `Path`. A binary found only
        // through the augmentation still resolves.
        expect(
          windowsRunner(
            <String>{r'D:\engines\slang.EXE'},
            environment: const {'Path': r'C:\Windows\System32'},
          ).spawnExecutableFor(
            'slang',
            environment: const {'Path': r'C:\Windows\System32;D:\engines'},
          ),
          r'D:\engines\slang.EXE',
        );
      },
    );

    test('an explicit Custom path is never rewritten', () {
      const custom = r'D:\custom\verible-verilog-lint.exe';
      expect(
        windowsRunner(<String>{
          custom,
        }).spawnExecutableFor(custom, environment: const {}),
        custom,
      );
    });

    test(
      'an engine nothing on PATH answers to starts nothing: start throws '
      'the ProcessException the engines report as not installed',
      () async {
        await expectLater(
          windowsRunner(const <String>{}).start('svlint', const ['--version']),
          throwsA(
            isA<ProcessException>()
                .having((e) => e.executable, 'executable', 'svlint')
                .having((e) => e.errorCode, 'errorCode', 2),
          ),
        );
      },
    );

    test('off Windows the name is left to execvp', () {
      expect(
        const SystemProcessRunner(
          host: SpawnHost(windows: false),
        ).spawnExecutableFor('verilator', environment: const {}),
        'verilator',
      );
    });
  });
}
