// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/platform/linux_desktop_identity.dart';

/// The Linux half of "double-clicking a LintCrux file opens it".
///
/// A file manager offers an application only for the MIME types its desktop
/// entry claims, and the entry claimed none, so a double-clicked project went
/// to whatever else handles JSON. One MIME type per registered extension, and
/// the two platforms are checked against each other so neither gains a file
/// type the other does not open.
void main() {
  String cmakeValue(String name) {
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    final match = RegExp('set\\($name "([^"]+)"\\)').firstMatch(cmake);
    if (match == null) throw StateError('linux/CMakeLists.txt sets no $name');
    return match.group(1)!;
  }

  test('the open-core identity matches the Linux runner', () {
    // The GTK runner stamps `APPLICATION_ID` on the window; an entry whose
    // `StartupWMClass` differs leaves the dock showing a generic icon.
    expect(kLintcruxLinuxDesktopApp.appId, cmakeValue('APPLICATION_ID'));
    expect(kLintcruxLinuxDesktopApp.execName, cmakeValue('BINARY_NAME'));
    expect(kLintcruxLinuxDesktopApp.name, 'LintCrux');
  });

  group('the files LintCrux opens', () {
    /// The types the system maps for us, so naming them in the entry offers
    /// LintCrux alongside the editors that already handle them, and the
    /// extensions each one covers. `crux_linux_integration` knows the
    /// suite-wide ones (`application/sarif+json` among them); the HDL types
    /// are LintCrux's own claim about this platform.
    ///
    /// `.vh` sits under Verilog here and under SystemVerilog upstream. The
    /// entry names both types, so a `.vh` file typed either way reaches
    /// LintCrux; what this map decides is only which of our two registered
    /// names accounts for the extension in the coverage check.
    const systemMapped = <String, List<String>>{
      'application/sarif+json': <String>['sarif'],
      'text/x-verilog': <String>['v', 'vh'],
      'text/x-systemverilog': <String>['sv', 'svh'],
      'text/x-vhdl': <String>['vhd', 'vhdl'],
    };

    Set<String> macosExtensions() {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      // From the document-types array to the line that closes it at the
      // plist's own indentation, so the nested arrays inside do not end it.
      final documentTypes = RegExp(
        r'<key>CFBundleDocumentTypes</key>\s*<array>(.*?)\n\t</array>',
        dotAll: true,
      ).firstMatch(plist)!.group(1)!;
      return RegExp(
            r'<key>CFBundleTypeExtensions</key>\s*<array>(.*?)</array>',
            dotAll: true,
          )
          .allMatches(documentTypes)
          .expand(
            (m) => RegExp(
              '<string>([^<]+)</string>',
            ).allMatches(m.group(1)!).map((e) => e.group(1)!),
          )
          .toSet();
    }

    LinuxMimeCoverage coverage() => checkLinuxMimeCoverage(
      kLintcruxLinuxDesktopApp,
      registeredExtensions: macosExtensions(),
      registeredExtensionsOf: systemMapped,
      additionalSystemTypes: systemMapped.keys.toSet(),
    );

    test('every file type macOS registers is accounted for on Linux', () {
      final registered = macosExtensions();
      expect(registered, isNotEmpty);
      final result = coverage();
      expect(
        result.problems,
        isEmpty,
        reason:
            'macOS and Linux disagree on which files LintCrux opens:\n'
            '$result',
      );
    });

    test('the one deliberately unmapped extension is .f, with its reason', () {
      // Not a hole to be filled: `.f` is Fortran to every Linux desktop, and
      // claiming it would take the extension from Fortran editors for
      // everyone who installs LintCrux. The reason travels with the record.
      final unmapped = coverage().deliberatelyUnmapped;
      expect(unmapped.keys, <String>['f']);
      expect(unmapped['f'], contains('text/x-fortran'));
      expect(
        kLintcruxLinuxDesktopApp.claimedTypeNames,
        isNot(contains('text/x-crux-filelist')),
      );
    });

    test('our own document types carry a Kind comment and a parent type', () {
      // The comment is what a file manager shows in its "Kind" column, and
      // the parent is what one that does not know our type falls back to.
      final declared = kLintcruxFileTypes.where((t) => t.isDeclared).toList();
      expect(declared.map((t) => t.name), <String>[
        'application/x-lintcrux-project',
        'application/x-lintcrux-workspace',
        'application/x-lintcrux-session',
        'application/x-edacrux-project',
      ]);
      for (final type in declared) {
        expect(type.comment, isNotEmpty, reason: type.name);
        expect(type.extensions, isNotEmpty, reason: type.name);
        expect(
          type.subClassOf,
          type.name == 'application/x-edacrux-project'
              ? 'application/x-yaml'
              : 'application/json',
          reason: type.name,
        );
      }
      // The suite manifest is one file with one name: this is the Linux
      // spelling of the macOS UTI `app.edacrux.project`, and the other three
      // products use it verbatim.
      expect(
        declared.last.comment,
        'EDACrux design manifest',
      );
    });

    test('the desktop entry names every type, and the package declares '
        'ours', () {
      final entry = buildDesktopEntry(
        kLintcruxLinuxDesktopApp,
        appImagePath: '/home/e/Apps/LintCrux-1.0.0-x86_64.AppImage',
      );
      expect(
        entry,
        contains(
          'MimeType=application/x-lintcrux-project;'
          'application/x-lintcrux-workspace;'
          'application/x-lintcrux-session;'
          'application/x-edacrux-project;'
          'application/sarif+json;'
          'text/x-verilog;text/x-systemverilog;text/x-vhdl;\n',
        ),
      );

      final xml = buildMimePackage(kLintcruxLinuxDesktopApp)!;
      expect(xml, contains('<glob pattern="*.lintcrux"/>'));
      expect(xml, contains('<comment>EDACrux design manifest</comment>'));
      // Never re-declared: the description every SARIF or Verilog file shows
      // on the machine is not ours to replace.
      expect(xml, isNot(contains('application/sarif+json')));
      expect(xml, isNot(contains('text/x-verilog')));
    });
  });

  test('bootstrap integrates the identity it is given, not a fixed one', () {
    // The Pro overlay passes its own identity; a fixed one here would write
    // the open-core entry over it.
    final app = File('lib/app.dart').readAsStringSync();
    expect(
      app,
      contains(
        'maybeIntegrateDesktopEntry(linuxDesktopApp ?? '
        'kLintcruxLinuxDesktopApp)',
      ),
    );
  });
}
