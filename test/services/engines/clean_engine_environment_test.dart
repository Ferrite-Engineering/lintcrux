// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/services/engines/clean_engine_environment.dart';

/// The NO_COLOR contract: every engine subprocess is
/// spawned with color suppression injected so TTY-detecting engines emit
/// plain diagnostics the parsers can read.
void main() {
  group('cleanEngineEnvironment', () {
    test('injects NO_COLOR=1 and TERM=dumb with no base', () {
      final env = cleanEngineEnvironment();
      expect(env['NO_COLOR'], '1');
      expect(env['TERM'], 'dumb');
    });

    test('preserves caller-supplied entries', () {
      final env = cleanEngineEnvironment(<String, String>{
        'PATH': '/usr/bin',
        'CUSTOM': 'x',
      });
      // The caller's PATH is preserved; macOS appends the Homebrew bin
      // dirs (never shadowing existing entries), so assert containment
      // rather than exact equality.
      expect(env['PATH'], contains('/usr/bin'));
      expect(env['CUSTOM'], 'x');
      expect(env['NO_COLOR'], '1');
      expect(env['TERM'], 'dumb');
    });

    test('color-suppression keys always win over the base', () {
      // A caller (or inherited config) cannot re-enable color.
      final env = cleanEngineEnvironment(<String, String>{
        'NO_COLOR': '0',
        'TERM': 'xterm-256color',
      });
      expect(env['NO_COLOR'], '1');
      expect(env['TERM'], 'dumb');
    });

    test('appends Homebrew bin dirs to PATH on macOS, leaves it alone '
        'elsewhere', () {
      final env = cleanEngineEnvironment(<String, String>{'PATH': '/usr/bin'});
      if (Platform.isMacOS) {
        // Finder/Dock-launched GUI apps miss the shell PATH; the augmented
        // PATH must expose Homebrew engines like verilator, appended after
        // the caller's own entries.
        expect(env['PATH'], '/usr/bin:/opt/homebrew/bin:/usr/local/bin');
      } else if (Platform.isWindows) {
        // Windows appends the persistent registry PATH (machine-specific),
        // so the caller's entry is preserved as the leading segment.
        expect(env['PATH'], anyOf(equals('/usr/bin'), startsWith('/usr/bin;')));
      } else {
        // No augmentation on Linux — the caller's PATH passes through
        // untouched.
        expect(env['PATH'], '/usr/bin');
      }
    });

    test('exposes each Homebrew bin dir as a discrete, resolvable PATH '
        'entry from a Finder-style minimal PATH (macOS)', () {
      // Regression: a Finder/Dock launch inherits launchd's minimal
      // PATH (no Homebrew). The augmented PATH must contain each Homebrew
      // dir as its OWN `:`-delimited entry — not fused into a neighbor — or
      // the availability probe (`<engine> --version`, which spawns through
      // this same env) still reports Homebrew engines "not available".
      final env = cleanEngineEnvironment(<String, String>{
        'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
      });
      if (Platform.isMacOS) {
        final entries = env['PATH']!.split(':');
        expect(entries, contains('/opt/homebrew/bin'));
        expect(entries, contains('/usr/local/bin'));
        // No malformed fused entry (the `Platform.pathSeparator` bug).
        expect(entries.every((e) => !e.contains('//')), isTrue);
      } else if (Platform.isWindows) {
        // Windows splits on ';', so this POSIX-style value is a single
        // segment; the registry PATH is appended after it.
        expect(
          env['PATH'],
          anyOf(
            equals('/usr/bin:/bin:/usr/sbin:/sbin'),
            startsWith('/usr/bin:/bin:/usr/sbin:/sbin;'),
          ),
        );
      } else {
        expect(env['PATH'], '/usr/bin:/bin:/usr/sbin:/sbin');
      }
    });

    test('does not duplicate a Homebrew dir already on PATH (macOS)', () {
      final env = cleanEngineEnvironment(<String, String>{
        'PATH': '/opt/homebrew/bin:/usr/bin',
      });
      if (Platform.isMacOS) {
        // /opt/homebrew/bin is already present, so only /usr/local/bin is
        // appended.
        expect(env['PATH'], '/opt/homebrew/bin:/usr/bin:/usr/local/bin');
      } else if (Platform.isWindows) {
        expect(
          env['PATH'],
          anyOf(
            equals('/opt/homebrew/bin:/usr/bin'),
            startsWith('/opt/homebrew/bin:/usr/bin;'),
          ),
        );
      } else {
        expect(env['PATH'], '/opt/homebrew/bin:/usr/bin');
      }
    });
  });
}
