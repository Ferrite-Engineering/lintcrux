// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `p.relative` answers in the HOST's separator, which is right for a
// path about to be opened and wrong for every path about to be written
// into an artifact somebody else reads — a SARIF uri, the `--ci` stdout
// listing, the committed waiver audit trail.
//
// The context is injected so the Windows behaviour is proved here, on
// the macOS/Linux CI boxes, rather than only on the Sunday-only Windows
// job — which is how `rtl\cpu.sv` reached a committed audit trail in the
// first place.

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/core/util/portable_path.dart';
import 'package:path/path.dart' as p;

void main() {
  group('portableRelativePath', () {
    test('a Windows host answers with forward slashes', () {
      expect(
        portableRelativePath(
          r'C:\proj\rtl\cpu.sv',
          r'C:\proj',
          context: p.windows,
        ),
        'rtl/cpu.sv',
      );
    });

    test('a POSIX host answers identically', () {
      expect(
        portableRelativePath('/proj/rtl/cpu.sv', '/proj', context: p.posix),
        'rtl/cpu.sv',
      );
    });

    test('the two platforms agree, which is the whole point', () {
      expect(
        portableRelativePath(
          r'C:\proj\rtl\sub\cpu.sv',
          r'C:\proj',
          context: p.windows,
        ),
        portableRelativePath(
          '/proj/rtl/sub/cpu.sv',
          '/proj',
          context: p.posix,
        ),
      );
    });

    test('a file directly in the root keeps its bare name', () {
      expect(
        portableRelativePath(r'C:\proj\top.sv', r'C:\proj', context: p.windows),
        'top.sv',
      );
    });

    test('defaults to the host context', () {
      // Whatever the host is, the answer is `/`-separated.
      expect(portableRelativePath(p.join('a', 'b', 'c.sv'), 'a'), 'b/c.sv');
    });
  });

  // A `.lintcrux` project is committed from one host and opened on another,
  // so the file has to read the same under both path styles. Each case names
  // its style, so every host runs both.
  group('portableProjectEntry', () {
    final windows = p.Context(style: p.Style.windows);
    const winDir = r'C:\Users\Dev\Designs\CPU';
    const posixDir = '/home/dev/designs/cpu';

    test('writes / on a Windows host', () {
      expect(
        portableProjectEntry(
          r'C:\Users\Dev\Designs\CPU\rtl\top.sv',
          winDir,
          context: windows,
        ),
        'rtl/top.sv',
      );
      expect(
        portableProjectEntry(
          r'C:\Users\Dev\Designs\IP\fifo.sv',
          winDir,
          context: windows,
        ),
        '../IP/fifo.sv',
      );
    });

    test('writes the same entry on a POSIX host', () {
      expect(
        portableProjectEntry(
          '$posixDir/rtl/top.sv',
          posixDir,
          context: p.posix,
        ),
        'rtl/top.sv',
      );
      expect(
        portableProjectEntry(
          '/home/dev/designs/ip/fifo.sv',
          posixDir,
          context: p.posix,
        ),
        '../ip/fifo.sv',
      );
    });

    test('keeps a file on another Windows drive absolute', () {
      expect(
        portableProjectEntry(
          r'D:\Shared\IP\fifo.sv',
          winDir,
          context: windows,
        ),
        r'D:\Shared\IP\fifo.sv',
      );
    });

    test('an entry already relative only has its separators normalised', () {
      expect(
        portableProjectEntry(r'rtl\top.sv', winDir, context: windows),
        'rtl/top.sv',
      );
      expect(
        portableProjectEntry('rtl/top.sv', posixDir, context: p.posix),
        'rtl/top.sv',
      );
    });

    test('a Windows-absolute entry seen under POSIX rules is left alone', () {
      expect(
        portableProjectEntry(r'C:\proj\top.sv', posixDir, context: p.posix),
        r'C:\proj\top.sv',
      );
    });
  });

  group('projectEntryForReading', () {
    final windows = p.Context(style: p.Style.windows);

    test('POSIX rules read a backslash in a relative entry as a separator', () {
      expect(
        projectEntryForReading(r'rtl\sub\top.sv', context: p.posix),
        'rtl/sub/top.sv',
      );
      expect(
        projectEntryForReading(r'..\ip\fifo.sv', context: p.posix),
        '../ip/fifo.sv',
      );
    });

    test('POSIX rules leave / entries and absolute POSIX paths alone', () {
      expect(
        projectEntryForReading('rtl/top.sv', context: p.posix),
        'rtl/top.sv',
      );
      expect(
        projectEntryForReading(r'/opt/we\ird/f.sv', context: p.posix),
        r'/opt/we\ird/f.sv',
      );
    });

    test('POSIX rules leave Windows-absolute entries alone', () {
      expect(
        projectEntryForReading(r'C:\proj\top.sv', context: p.posix),
        r'C:\proj\top.sv',
      );
      expect(
        projectEntryForReading(r'\\srv\ip\f.sv', context: p.posix),
        r'\\srv\ip\f.sv',
      );
    });

    test('Windows rules take either separator as it is', () {
      expect(
        projectEntryForReading(r'rtl\top.sv', context: windows),
        r'rtl\top.sv',
      );
      expect(
        projectEntryForReading('rtl/top.sv', context: windows),
        'rtl/top.sv',
      );
    });
  });
}
