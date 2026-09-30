// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_yosys/crux_yosys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/yosys/yosys_engine_support.dart';

void main() {
  group('yosysExecutableFor', () {
    test('Custom returns the configured path', () {
      expect(
        yosysExecutableFor(
          const EngineBinaryConfig(
            source: EngineBinarySource.custom,
            path: '/opt/y/bin/yosys',
          ),
        ),
        '/opt/y/bin/yosys',
      );
    });

    test('Custom with no path falls back to the PATH default', () {
      expect(
        yosysExecutableFor(
          const EngineBinaryConfig(
            source: EngineBinarySource.custom,
            path: '',
          ),
        ),
        isNull,
      );
    });

    test('Auto-detect is the PATH default', () {
      expect(yosysExecutableFor(const EngineBinaryConfig.system()), isNull);
    });

    test('Bundled with no bundled binary falls back to PATH', () {
      expect(
        yosysExecutableFor(
          const EngineBinaryConfig(source: EngineBinarySource.bundled),
          resolver: const BundledBinaryResolver(
            overrideRoot: '/nonexistent/lintcrux-bundle',
          ),
        ),
        isNull,
      );
    });
  });

  group('yosysRunException', () {
    test('a launch failure is an unavailable engine', () {
      const result = YosysRunFailure(
        kind: YosysFailureKind.launch,
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'Could not run the executable "yosys": No such file',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: result),
        isA<EngineNotAvailableException>(),
      );
    });

    test('a rejected request is a failed run, not a missing binary', () {
      const result = YosysRunFailure(
        kind: YosysFailureKind.invalidRequest,
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'Invalid Yosys request: Path must not contain quotes',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: result),
        isA<EngineRunFailedException>(),
      );
    });

    test('the kind decides a launch failure, not the stderr wording', () {
      // A launch failure whose message does not open with the runner's
      // usual prefix is still a missing binary...
      const launch = YosysRunFailure(
        kind: YosysFailureKind.launch,
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'spawn failed',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: launch),
        isA<EngineNotAvailableException>(),
      );

      // ...and a failure of another kind that happens to carry that prefix
      // is not.
      const unreadable = YosysRunFailure(
        kind: YosysFailureKind.outputUnreadable,
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'Could not run the executable "yosys"',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: unreadable),
        isA<EngineRunFailedException>(),
      );
    });

    test('a failure built without a kind keeps its exit-code meaning', () {
      // `YosysRunFailure.kind` derives -1 as a launch failure when none is
      // given, so a test double written before the field existed still
      // reads as a missing binary.
      const result = YosysRunFailure(
        exitCode: YosysRunner.launchFailureExitCode,
        stdout: '',
        stderr: 'Could not run the executable "yosys": No such file',
      );
      expect(
        yosysRunException(engineId: 'yosys', result: result),
        isA<EngineNotAvailableException>(),
      );
    });

    for (final (kind, exitCode, reason) in <(YosysFailureKind, int, String)>[
      (
        YosysFailureKind.invalidRequest,
        YosysRunner.launchFailureExitCode,
        'request could not be turned into a yosys script',
      ),
      (
        YosysFailureKind.outputUnreadable,
        YosysRunner.launchFailureExitCode,
        'JSON output could not be read back',
      ),
      (YosysFailureKind.noOutput, 0, 'without writing its JSON output'),
      (YosysFailureKind.nonZeroExit, 1, 'without a parseable diagnostic'),
    ]) {
      test('${kind.name} is a failed run that says which failure it was', () {
        final result = YosysRunFailure(
          kind: kind,
          exitCode: exitCode,
          stdout: '',
          stderr: 'detail',
        );
        expect(
          yosysRunException(
            engineId: 'yosys',
            result: result,
            executable: '/opt/y/bin/yosys',
          ),
          isA<EngineRunFailedException>()
              .having((e) => e.exitCode, 'exitCode', exitCode)
              .having((e) => e.reason, 'reason', contains(reason))
              .having((e) => e.outputExcerpt, 'outputExcerpt', ['detail'])
              .having(
                (e) => e.resolvedPath,
                'resolvedPath',
                '/opt/y/bin/yosys',
              ),
        );
      });
    }

    test('a timeout carries its budget', () {
      const result = YosysRunTimeout(
        budget: Duration(seconds: 5),
        stdout: '',
        stderr: '',
      );
      expect(
        yosysRunException(engineId: 'cdc', result: result),
        isA<EngineTimedOutException>().having(
          (e) => e.timeout,
          'timeout',
          const Duration(seconds: 5),
        ),
      );
    });

    test('a non-zero exit keeps the first stderr lines', () {
      const result = YosysRunFailure(exitCode: 1, stdout: '', stderr: 'a\n\nb');
      expect(
        yosysRunException(engineId: 'yosys', result: result),
        isA<EngineRunFailedException>().having(
          (e) => e.outputExcerpt,
          'outputExcerpt',
          ['a', 'b'],
        ),
      );
    });
  });

  group('isYosysDesignFailure', () {
    test('only a non-zero Yosys exit is a verdict on the design', () {
      for (final kind in YosysFailureKind.values) {
        final result = YosysRunFailure(
          kind: kind,
          exitCode: kind == YosysFailureKind.nonZeroExit ? 1 : -1,
          stdout: '',
          stderr: '',
        );
        expect(
          isYosysDesignFailure(result),
          kind == YosysFailureKind.nonZeroExit,
          reason: kind.name,
        );
      }
    });

    test('a success, a timeout and a cancellation are not', () {
      expect(
        isYosysDesignFailure(
          const YosysRunSuccess(rawJson: '{}', stdout: '', stderr: ''),
        ),
        isFalse,
      );
      expect(
        isYosysDesignFailure(
          const YosysRunTimeout(
            budget: Duration(seconds: 1),
            stdout: '',
            stderr: '',
          ),
        ),
        isFalse,
      );
      expect(
        isYosysDesignFailure(const YosysRunCancelled(stdout: '', stderr: '')),
        isFalse,
      );
    });
  });
}
