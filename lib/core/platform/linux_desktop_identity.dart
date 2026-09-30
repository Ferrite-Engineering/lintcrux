// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_linux_integration/crux_linux_integration.dart';

/// The open-core build's freedesktop identity, installed as a host
/// `.desktop` entry when it runs from an AppImage.
///
/// [LinuxDesktopApp.appId] and [LinuxDesktopApp.execName] must equal
/// `APPLICATION_ID` and `BINARY_NAME` in `linux/CMakeLists.txt`: the GTK
/// runner sets the window's app id from the former, and a `.desktop` entry
/// whose `StartupWMClass` differs is not matched to the window. `bootstrap`
/// takes the identity as a parameter so the Pro overlay passes its own.
/// Not `const`: the declared file types below are built by a factory that
/// refuses a type the system already maps, and that check runs at
/// construction.
final LinuxDesktopApp kLintcruxLinuxDesktopApp = LinuxDesktopApp(
  appId: 'com.ferriteengineering.lintcrux',
  name: 'LintCrux',
  comment: 'Multi-engine HDL lint aggregator',
  execName: 'lintcrux',
  fileTypes: kLintcruxFileTypes,
);

/// The files LintCrux opens — the Linux half of the document types
/// `macos/Runner/Info.plist` registers.
///
/// A file manager types a file first and looks for handlers second, so a
/// name in the desktop entry earns nothing unless something maps files to
/// it. Each entry here says which of the two applies:
///
/// * **declared** — LintCrux's own document formats, which no system knows.
///   The extensions, the comment a file manager shows in its "Kind" column
///   and the parent type are installed as a shared-mime-info package, and
///   the type is named in the entry. The three JSON-shaped documents
///   sub-class `application/json`, so a file manager that does not know our
///   type still shows something sensible; the suite manifest sub-classes
///   `application/x-yaml` for the same reason. The manifest's name follows
///   the macOS UTI the same file carries, `app.edacrux.project`, because all
///   four products open it and one file should not end up with four names.
/// * **registered** — types the system already maps: the HDL sources and a
///   SARIF report. Named in the entry so LintCrux is offered alongside the
///   editors, and never re-declared, which would replace the description
///   every file of that type shows on the machine.
///
///   Two details about those upstream types. `.vh` is SystemVerilog's
///   there, not Verilog's — the mapping in the coverage guard says Verilog,
///   which is harmless because the entry names both types, so a `.vh` typed
///   either way still reaches LintCrux. And a distribution whose
///   shared-mime-info predates the SystemVerilog addition maps `.sv` to
///   nothing, so such a file types as plain text and LintCrux is not
///   offered for it. That is the cost of not declaring a type that is
///   somebody else's, and it is the right cost: declaring `text/x-*` for
///   HDL sources would replace what every editor's files show on the
///   machine.
/// * **unmapped** — `.f`. Every Linux desktop types it as `text/x-fortran`,
///   and a filelist is a niche use of that extension: claiming it would take
///   `.f` from Fortran editors for everyone who installs LintCrux, which is
///   the overclaim the macOS document types avoided. A `.f` filelist is
///   opened from inside the app (`File → Import Vivado Filelist…`, or
///   `--import-filelist`); a double-clicked one goes to the user's Fortran
///   editor. Recorded rather than omitted so the next reader finds a
///   decision instead of a hole.
///
/// `test/static/linux_desktop_identity_test.dart` checks this list against
/// the macOS document types with `checkLinuxMimeCoverage`, so neither
/// platform can gain a file type the other does not open.
final List<LinuxMimeType> kLintcruxFileTypes = <LinuxMimeType>[
  LinuxMimeType.declared(
    name: 'application/x-lintcrux-project',
    comment: 'LintCrux project',
    extensions: const <String>['lintcrux'],
    subClassOf: 'application/json',
  ),
  LinuxMimeType.declared(
    name: 'application/x-lintcrux-workspace',
    comment: 'LintCrux workspace',
    extensions: const <String>['lintcrux-workspace'],
    subClassOf: 'application/json',
  ),
  LinuxMimeType.declared(
    name: 'application/x-lintcrux-session',
    comment: 'LintCrux session',
    extensions: const <String>['lintcrux-session'],
    subClassOf: 'application/json',
  ),
  LinuxMimeType.declared(
    name: 'application/x-edacrux-project',
    comment: 'EDACrux design manifest',
    extensions: const <String>['crux-project'],
    subClassOf: 'application/x-yaml',
  ),
  const LinuxMimeType.registered('application/sarif+json'),
  const LinuxMimeType.registered('text/x-verilog'),
  const LinuxMimeType.registered('text/x-systemverilog'),
  const LinuxMimeType.registered('text/x-vhdl'),
  LinuxMimeType.unmapped(
    extensions: const <String>['f'],
    reason:
        'Every Linux desktop types .f as text/x-fortran, and a filelist is a '
        'niche use of that extension. Claiming it would take .f from Fortran '
        'editors for everyone who installs LintCrux, and a vendor type with '
        'no glob matches no file, so there would be nothing to claim it with '
        'either. A filelist is opened from inside the app.',
  ),
];
