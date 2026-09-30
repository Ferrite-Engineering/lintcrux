// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/services/engines/clean_engine_environment.dart';

/// Result of a click-to-source launch attempt.
class ClickToSourceResult {
  /// Creates a [ClickToSourceResult].
  const ClickToSourceResult({
    required this.success,
    required this.command,
    this.errorMessage,
  });

  /// `true` when `Process.start` returned without throwing — the
  /// editor binary at least exists and was executable. Editors that
  /// silently refuse to open the file (corrupt config, headless mode,
  /// no DISPLAY) are *not* caught here; the user-visible signal is
  /// the editor itself not opening.
  final bool success;

  /// The materialized executable + args that were invoked.
  final RenderedEditorCommand command;

  /// Human-readable failure cause when [success] is `false`. English-
  /// only; the snackbar translation wraps this.
  final String? errorMessage;
}

/// One materialized editor-command invocation: executable + argv.
class RenderedEditorCommand {
  /// Creates a [RenderedEditorCommand].
  const RenderedEditorCommand({
    required this.executable,
    required this.arguments,
  });

  /// Executable name (resolved against `PATH`).
  final String executable;

  /// Materialized argv (placeholders replaced).
  final List<String> arguments;

  /// Reproducer string (`exe arg1 arg2`) suitable for snackbars and
  /// the diagnostics panel.
  @override
  String toString() => '$executable ${arguments.join(' ')}';
}

/// Maps a well-known bare editor command to the CLI executable that
/// lives inside its macOS `.app` bundle.
///
/// macOS editors installed by drag-and-drop into `/Applications` ship a
/// command-line launcher *inside* the bundle, but only put it on `PATH`
/// if the user runs the app's "Install 'code' command in PATH" action
/// (or Homebrew-casks the app). A user who never did that has a working
/// editor with **no** `code` (or `subl`, …) on any `PATH` dir, so a
/// bare-name spawn fails with "Could not launch editor" even though the
/// editor is clearly installed. This table is the macOS-only fallback:
/// when the configured command is not resolvable on `PATH`, LintCrux
/// checks the editor's known in-bundle CLI path and spawns that instead.
///
/// Keys are the bare command names LintCrux's presets emit; values are
/// the canonical in-bundle CLI path for a stock `/Applications` install.
const Map<String, String> macOsEditorBundleClis = <String, String>{
  'code':
      '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code',
  'code-insiders':
      '/Applications/Visual Studio Code - Insiders.app/Contents/Resources/app/bin/code',
  'subl': '/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl',
  'zed': '/Applications/Zed.app/Contents/MacOS/cli',
  'cursor': '/Applications/Cursor.app/Contents/Resources/app/bin/cursor',
};

/// Resolves an editor executable to the concrete program to spawn.
///
/// The resolution order deliberately keeps `PATH` authoritative:
///
/// 1. A command that already contains a path separator (`/`) is an
///    explicit path — used verbatim, no lookup.
/// 2. On **Windows**, a bare command is resolved to an absolute path
///    against the effective `PATH` before spawning. `CreateProcess`
///    searches the calling process's current directory *ahead of*
///    `PATH`, and LintCrux never moves its own CWD — so a developer who
///    launched it from a terminal inside the repository would run a
///    `code.exe` committed to that repository. A bare command that
///    nothing on `PATH` answers to throws the `not found on PATH`
///    [ProcessException] rather than coming back bare, so it is reported
///    as a launch failure and never searched for in that directory. See
///    `requireSpawnExecutable` in `crux_io`.
/// 3. On other platforms a bare command that resolves on the effective
///    `PATH` is returned unchanged, so a `code` that **is** on `PATH`
///    keeps behaving exactly as before (`execvp` never consults the
///    current directory, so there is nothing to close).
/// 4. Only when a bare command is **not** on `PATH`, and only on macOS,
///    the [macOsEditorBundleClis] fallback is consulted: if the editor's
///    known in-bundle CLI exists on disk, that absolute path is spawned.
/// 5. Otherwise (off Windows) the bare command is returned unchanged, so
///    the spawn fails and surfaces the actionable "Could not launch
///    editor" snackbar rather than silently doing nothing.
///
/// The platform checks and the filesystem existence check are all
/// injectable so tests can exercise every branch deterministically on
/// any host.
class MacOsBundleEditorResolver {
  /// Creates a [MacOsBundleEditorResolver].
  ///
  /// [isMacOs] overrides the platform check (defaults to
  /// [Platform.isMacOS]); [isWindows] overrides the Windows check
  /// (defaults to [Platform.isWindows]); [fileExists] overrides the
  /// on-disk existence check (defaults to a real [FileSystemEntity]
  /// probe). Tests inject them to simulate a machine where `code` is off
  /// `PATH` but the VS Code bundle is installed, or a Windows box with a
  /// planted `code.exe` in the project directory.
  const MacOsBundleEditorResolver({
    bool? isMacOs,
    bool? isWindows,
    bool Function(String path)? fileExists,
  }) : _isMacOsOverride = isMacOs,
       _isWindowsOverride = isWindows,
       _fileExistsOverride = fileExists;

  final bool? _isMacOsOverride;
  final bool? _isWindowsOverride;
  final bool Function(String path)? _fileExistsOverride;

  bool get _isMacOs => _isMacOsOverride ?? Platform.isMacOS;

  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;

  bool _exists(String path) => (_fileExistsOverride ?? _defaultExists)(path);

  static bool _defaultExists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  /// Resolves [executable] against [pathEnvironment] (the `PATH` the
  /// spawn will actually use — the augmented one from
  /// [cleanEngineEnvironment]). See the class doc for the order.
  ///
  /// Throws the `not found on PATH` [ProcessException] on Windows for a
  /// bare command nothing on `PATH` answers to.
  String resolve(String executable, {required String? pathEnvironment}) {
    // An explicit path (absolute or relative) is trusted verbatim.
    if (executable.contains('/')) return executable;
    if (_isWindows) {
      // Absolute-path resolution, not a yes/no PATH probe: the spawn must
      // be handed a path so CreateProcess never searches the CWD. Throws
      // when nothing on PATH matches.
      return requireSpawnExecutable(
        executable,
        pathEnvironment: pathEnvironment,
        windows: true,
        pathExt: Platform.environment['PATHEXT'],
        exists: _exists,
      );
    }
    // PATH wins: a bare command already resolvable on PATH is unchanged.
    if (_isOnPath(executable, pathEnvironment)) return executable;
    // macOS-only app-bundle fallback for well-known editors.
    if (_isMacOs) {
      final bundleCli = macOsEditorBundleClis[executable];
      if (bundleCli != null && _exists(bundleCli)) return bundleCli;
    }
    // Neither PATH nor a known bundle resolved it — return the bare name
    // so the spawn fails with a clear, actionable error.
    return executable;
  }

  bool _isOnPath(String name, String? pathEnvironment) {
    if (pathEnvironment == null || pathEnvironment.isEmpty) return false;
    // PATH entries are `:`-separated on macOS/POSIX (never the file-path
    // separator — see cleanEngineEnvironment for that same footgun).
    for (final dir in pathEnvironment.split(':')) {
      if (dir.isEmpty) continue;
      final candidate = dir.endsWith('/') ? '$dir$name' : '$dir/$name';
      if (_exists(candidate)) return true;
    }
    return false;
  }
}

/// Launcher abstraction so tests can substitute a fake.
// ignore: one_member_abstracts
abstract class EditorLauncher {
  /// Launches [executable] with [arguments] and returns the new
  /// process. Throws [ProcessException] when the binary cannot be
  /// found / executed.
  ///
  /// [environment] is layered on top of the inherited process
  /// environment (`Process.start` runs with
  /// `includeParentEnvironment: true`). It carries the augmented `PATH`
  /// that lets a bare-name editor command (`code`, …) resolve even when
  /// LintCrux was launched from Finder/Dock — see
  /// [ClickToSourceService.openInEditor].
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  });
}

/// Production launcher: forwards to `Process.start`.
class SystemEditorLauncher implements EditorLauncher {
  /// Creates a [SystemEditorLauncher].
  const SystemEditorLauncher();

  @override
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    return Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
      environment: environment,
    );
  }
}

/// Implements the click-to-source action: render the configured
/// [EditorCommand] for a [SourceLocation], then shell out via
/// [EditorLauncher].
///
/// `commandFor` is a thunk so callers always see the *current*
/// preference (the Riverpod provider's notifier mutates underneath us).
/// `launcher` defaults to the production [SystemEditorLauncher]; tests
/// inject a fake that records invocations and never spawns a real
/// process.
class ClickToSourceService {
  /// Creates a [ClickToSourceService].
  ///
  /// [onLaunched] is the `editor.launched` telemetry seam: one call per
  /// attempt, carrying the preset and whether the spawn succeeded. A callback
  /// rather than a `Ref` read inside the service, so the service stays a plain
  /// testable object and the wiring lives in `clickToSourceServiceProvider`
  /// alongside the rest of the Riverpod graph.
  const ClickToSourceService({
    required this.commandFor,
    this.launcher = const SystemEditorLauncher(),
    this.resolver = const MacOsBundleEditorResolver(),
    this.environmentBuilder,
    this.onLaunched,
  });

  /// Thunk returning the active editor command on each invocation.
  final EditorCommand Function() commandFor;

  /// Reports each click-to-source attempt: which preset, and whether the
  /// editor actually launched. Never allowed to affect the launch.
  final void Function(EditorPreset preset, {required bool ok})? onLaunched;

  /// Launcher used to spawn the editor subprocess.
  final EditorLauncher launcher;

  /// Builds the spawn environment (the augmented `PATH`). Defaults to
  /// [cleanEngineEnvironment]; tests inject a deterministic environment so
  /// `PATH` resolution does not depend on the host machine's real `PATH`
  /// (which differs by OS — the CI Windows runner has no `/opt/homebrew/bin`).
  final Map<String, String> Function()? environmentBuilder;

  /// Resolves the configured editor executable to the concrete program
  /// to spawn — falling back to a macOS app-bundle CLI path when the
  /// bare command is not on `PATH`. See [MacOsBundleEditorResolver].
  final MacOsBundleEditorResolver resolver;

  /// Opens [location] in the user's configured editor.
  ///
  /// The spawn is routed through the augmented environment built by
  /// [cleanEngineEnvironment], so a bare-name editor command (`code`,
  /// VS Code's CLI) resolves against Homebrew's bin dirs even when
  /// LintCrux was launched from Finder/Dock — where `launchd` hands the
  /// app the minimal default `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`)
  /// that omits `/opt/homebrew/bin` (and `/usr/local/bin`). This is the
  /// same Finder-`PATH` class that hides the engine binaries; without
  /// the augmentation `code` is invisible and the launch fails with
  /// "Could not launch editor" unless the app was started from a
  /// terminal. If the editor genuinely is not installed / on `PATH`,
  /// the launch still throws and surfaces the clear failure snackbar.
  Future<ClickToSourceResult> openInEditor(SourceLocation location) async {
    final command = commandFor();
    // The last gate before a string the app did not author becomes argv.
    //
    // A `SourceLocation.file` has two untrusted origins: an engine's own
    // stdout — which a design file steers with a `` `line `` directive —
    // and a CXP peer's `request_open_source`, whose `filePath` arrives
    // over a socket. `EditorCommand.render` substitutes per argv element,
    // so there is no shell to inject into, but the *editor's own* option
    // parser is the exposure: the `vim` and `emacs` presets are
    // `['+{line}', '{file}']`, and an argv element starting with `+` is
    // an editor command, not a filename. `vim +42 '+:!curl …'` runs it.
    //
    // An absolute path is the one shape no editor mistakes for an option,
    // and it is what `resolveEngineReportedPath` already guarantees for
    // every parser-produced location. Anything else is refused here — the
    // user sees the same actionable snackbar as a missing editor.
    if (!isAbsoluteSpawnPath(location.file)) {
      final refused = RenderedEditorCommand(
        executable: command.executable,
        arguments: command.render(
          file: location.file,
          line: location.line,
          column: location.column,
        ),
      );
      _report(command.preset, ok: false);
      return ClickToSourceResult(
        success: false,
        command: refused,
        errorMessage:
            'Refusing to open "${location.file}": click-to-source only '
            'opens absolute file paths, and this location did not carry '
            'one.',
      );
    }
    final environment = (environmentBuilder ?? cleanEngineEnvironment)();
    final arguments = command.render(
      file: location.file,
      line: location.line,
      column: location.column,
    );
    var rendered = RenderedEditorCommand(
      executable: command.executable,
      arguments: arguments,
    );
    try {
      // Resolve against the *same* PATH the spawn will use (the augmented
      // one), so a bare-name editor that is not on PATH can fall back to
      // its macOS app-bundle CLI before we attempt the spawn. Inside the
      // try: on Windows an editor nothing on PATH answers to throws here,
      // and is reported exactly as a failed launch is.
      rendered = RenderedEditorCommand(
        executable: resolver.resolve(
          command.executable,
          pathEnvironment: environment['PATH'] ?? Platform.environment['PATH'],
        ),
        arguments: arguments,
      );
      await launcher.launch(
        rendered.executable,
        rendered.arguments,
        environment: environment,
      );
      _report(command.preset, ok: true);
      return ClickToSourceResult(success: true, command: rendered);
    } on ProcessException catch (e) {
      _report(command.preset, ok: false);
      return ClickToSourceResult(
        success: false,
        command: rendered,
        errorMessage: 'Failed to launch ${rendered.executable}: ${e.message}',
      );
    }
  }

  void _report(EditorPreset preset, {required bool ok}) {
    try {
      onLaunched?.call(preset, ok: ok);
    } on Object catch (_) {
      // A counter is never worth a failed click-to-source.
    }
  }
}
