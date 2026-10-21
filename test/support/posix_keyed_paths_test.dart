// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_io/crux_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/clean_engine_environment.dart';
import 'package:path/path.dart' as p;

import 'posix_keyed_paths.dart';

/// The Windows spellings are literals, so these run on a Linux or macOS host
/// and prove what the Windows leg of CI would otherwise be the only one to
/// find.
void main() {
  group('posixKey', () {
    test('leaves a posix path alone', () {
      expect(posixKey('/p/sw'), '/p/sw');
    });

    test('drops the drive and turns backslashes into slashes', () {
      expect(posixKey(r'D:\p\sw'), '/p/sw');
    });

    test('reads a rooted Windows path with no drive', () {
      expect(posixKey(r'\p\sw'), '/p/sw');
      expect(posixKey(r'\images'), '/images');
    });

    test('accepts mixed separators and folds dot segments', () {
      expect(posixKey(r'C:\p/rtl\..\sw'), '/p/sw');
    });

    test('keeps a relative path relative', () {
      expect(posixKey(r'sw\img'), 'sw/img');
    });
  });

  group('the yosys working directory, as the host spells it', () {
    // The product joins and normalises through package:path in the host's
    // style, so the host's spelling of /p/sw is what it returns. These
    // build that spelling with the Windows context, which any host has.
    test('a Windows join of a rooted path and an option reads as /p/sw', () {
      final windows = p.windows.normalize(p.windows.join('/p', 'sw'));
      expect(windows, r'\p\sw');
      expect(posixKey(windows), '/p/sw');
    });

    test(
      'a Windows absolute option with a trailing slash reads as /images',
      () {
        final windows = p.windows.normalize('/images/');
        expect(windows, r'\images');
        expect(posixKey(windows), '/images');
      },
    );
  });

  group('search paths', () {
    test('join and split round-trip with either separator', () {
      for (final separator in [':', ';']) {
        final joined = joinSearchPath([
          '/usr/bin',
          '/bin',
        ], separator: separator);
        expect(joined, '/usr/bin$separator/bin');
        expect(splitSearchPath(joined, separator: separator), [
          '/usr/bin',
          '/bin',
        ]);
      }
    });

    test('a Windows PATH is read on semicolons, not colons', () {
      // The colon in a drive letter is not a separator, which is why a PATH
      // built for one host reads as a single entry on the other.
      const path = r'C:\Windows;C:\Tools\yosys\bin';
      expect(splitSearchPath(path, separator: ';'), [
        r'C:\Windows',
        r'C:\Tools\yosys\bin',
      ]);
      expect(splitSearchPath(path, separator: ':'), hasLength(3));
    });

    test('appending to a Windows PATH keeps the caller entries first', () {
      final base = joinSearchPath(['/usr/bin', '/bin'], separator: ';');
      final result = appendMissingPathDirs(
        base,
        [r'C:\Tools\yosys\bin'],
        separator: ';',
        caseInsensitive: true,
      );
      final entries = splitSearchPath(result!, separator: ';');
      expect(entries.first, '/usr/bin');
      expect(entries, contains(r'C:\Tools\yosys\bin'));
    });

    test('the engine environment never rewrites the caller PATH order', () {
      final base = joinSearchPath(['/usr/bin', '/bin']);
      final env = cleanEngineEnvironment({'PATH': base});
      final entries = splitSearchPath(env['PATH']!);
      expect(entries.take(2), ['/usr/bin', '/bin']);
    });
  });
}
