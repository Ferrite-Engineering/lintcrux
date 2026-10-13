// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The per-launch options macOS defines for every application.
///
/// `open -a LintCrux --args -AppleLanguages '(ko)' -AppleLocale ko_KR` is a
/// standard way to launch any Mac app under another language, and Xcode and
/// the system add options of their own (`-NSDocumentRevisionsDebugMode YES`,
/// the legacy `-psn_0_…` process serial number). They reach the app through
/// `argv`, and the desktop app shares its strict argument parser with the
/// headless binary, where an unknown option is a usage error by design. Left
/// in place they made the app print its usage and exit 64 before a window
/// opened, which from the Dock looks like the app flashing and not opening.
///
/// [stripMacosLaunchOptions] removes them for the desktop front door. The
/// headless binary keeps refusing them: nothing launches it that way.
library;

/// Matches a user-defaults style option: a single dash, the `Apple` or `NS`
/// prefix, then a capitalised name. Two dashes never match, so LintCrux's
/// own `--no-restore` and friends are untouched.
final RegExp _defaultsOption = RegExp(r'^-(?:Apple|NS)[A-Z][A-Za-z0-9_]*$');

/// Legacy Launch Services process serial number. Carries no value.
const String _processSerialPrefix = '-psn_';

/// [args] without the options macOS defines for every app.
///
/// Each `-Apple…` / `-NS…` option takes exactly one value, which is removed
/// with it whatever it looks like; `-psn_…` stands alone. Order of the
/// remaining arguments is preserved.
List<String> stripMacosLaunchOptions(List<String> args) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (_defaultsOption.hasMatch(arg)) {
      // Skip the value as well; a trailing option with no value is dropped
      // alone.
      i++;
      continue;
    }
    if (arg.startsWith(_processSerialPrefix)) continue;
    out.add(arg);
  }
  return out;
}
