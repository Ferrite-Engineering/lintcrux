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
}
