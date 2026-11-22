// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/services/engines/slang/slang_engine.dart';
import 'package:path/path.dart' as p;

import '../fake_process_runner.dart';

/// slang's JSON diagnostic for [file] (as slang prints it) at [line].
String _error(
  String file,
  int line, {
  String rule = 'multiple-always-assigns',
}) =>
    '[{"severity":"error","message":"m","optionName":"$rule",'
    '"location":"$file:$line:3"}]';

void main() {
  late Directory tmp;

  LintRunRequest request({
    required List<String> sources,
    Map<String, Object?> options = const <String, Object?>{},
  }) => LintRunRequest(
    sourceFiles: sources,
    binary: const EngineBinaryConfig.system(),
    language: HdlLanguage.systemVerilog,
    projectRoot: tmp.path,
    options: options,
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lintcrux_slang_lost_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('asks slang for absolute paths only when a file is outside the '
      'project root, in JSON and in text mode', () async {
    final outside = p.join(p.dirname(tmp.path), 'lintcrux_shared', 's.sv');
    final cases = <String, List<String>>{
      'sources inside the root': <String>[p.join(tmp.path, 'b', 't.sv')],
      'a source outside the root': <String>[p.join(tmp.path, 'a.sv'), outside],
    };
    for (final textMode in <bool>[false, true]) {
      for (final entry in cases.entries) {
        final fake = FakeProcessRunner();
        await SlangEngine(runner: fake)
            .run(
              request(
                sources: entry.value,
                options: <String, Object?>{'textModeFallback': textMode},
              ),
            )
            .toList();
        expect(
          fake.invocations.single.arguments.contains('--diag-abs-paths'),
          entry.key == 'a source outside the root',
          reason: '${entry.key}, textMode=$textMode',
        );
      }
    }
  });

  test(
    'an include path outside the root also asks for absolute paths',
    () async {
      final fake = FakeProcessRunner();
      await SlangEngine(runner: fake)
          .run(
            LintRunRequest(
              sourceFiles: <String>[p.join(tmp.path, 'a.sv')],
              binary: const EngineBinaryConfig.system(),
              language: HdlLanguage.systemVerilog,
              projectRoot: tmp.path,
              includePaths: <String>[p.join(p.dirname(tmp.path), 'ip')],
            ),
          )
          .toList();
      expect(fake.invocations.single.arguments, contains('--diag-abs-paths'));
    },
  );

  test('a finding in a folder beside the first source is reported', () async {
    // Reported relative to where slang ran, which is the project root.
    final fake = FakeProcessRunner()
      ..stdoutLines = <String>[_error('b/t.sv', 4)];
    final violations = await SlangEngine(runner: fake)
        .run(
          request(
            sources: <String>[
              p.join(tmp.path, 'a', 'x.sv'),
              p.join(tmp.path, 'b', 't.sv'),
            ],
          ),
        )
        .toList();
    expect(violations.single.location.file, p.join(tmp.path, 'b', 't.sv'));
    expect(violations.single.ruleId, 'slang/multiple-always-assigns');
  });

  test('a located finding whose path is refused fails the run instead of '
      'vanishing', () async {
    // A path that climbs out of the project root is refused, and what the
    // parser refuses used to leave the run clean.
    final fake = FakeProcessRunner()
      ..stdoutLines = <String>[_error('../elsewhere/t.sv', 4)];
    final run = SlangEngine(
      runner: fake,
    ).run(request(sources: <String>[p.join(tmp.path, 'a.sv')])).toList();
    await expectLater(
      run,
      throwsA(
        isA<EngineRunFailedException>()
            .having((e) => e.engineId, 'engineId', 'slang')
            .having((e) => e.outputExcerpt.join(), 'excerpt', contains('t.sv')),
      ),
    );
  });

  test(
    'findings that did parse are still streamed before the failure',
    () async {
      final fake = FakeProcessRunner()
        ..stdoutLines = <String>[
          '[',
          '{"severity":"error","message":"m","location":"ok.sv:1:1"},',
          '{"severity":"error","message":"m","location":"../x/t.sv:2:1"}',
          ']',
        ];
      final seen = <String>[];
      Object? failure;
      try {
        await for (final v in SlangEngine(runner: fake).run(
          request(sources: <String>[p.join(tmp.path, 'ok.sv')]),
        )) {
          seen.add(v.location.file);
        }
      } on EngineRunFailedException catch (e) {
        failure = e;
      }
      expect(seen, <String>[p.join(tmp.path, 'ok.sv')]);
      expect(failure, isNotNull);
    },
  );

  test('a text-mode finding whose path is refused fails the run', () async {
    final fake = FakeProcessRunner()
      ..stderrLines = <String>[
        '../elsewhere/t.sv:4:3: error: multiple drivers [-Wmultiple-always-assigns]',
      ];
    final run = SlangEngine(runner: fake)
        .run(
          request(
            sources: <String>[p.join(tmp.path, 'a.sv')],
            options: const <String, Object?>{'textModeFallback': true},
          ),
        )
        .toList();
    await expectLater(run, throwsA(isA<EngineRunFailedException>()));
  });

  test('a command-line error from slang fails the run', () async {
    // `error: unknown command line argument` and nothing analysed: a typo in
    // `extraOptions` must not end as a clean run.
    final fake = FakeProcessRunner()
      ..exitCode = 1
      ..stderrLines = <String>[
        "error: unknown command line argument '--allow-toplevel-iface-port'",
      ];
    final run = SlangEngine(
      runner: fake,
    ).run(request(sources: <String>[p.join(tmp.path, 'a.sv')])).toList();
    await expectLater(
      run,
      throwsA(
        isA<EngineRunFailedException>().having(
          (e) => e.outputExcerpt.single,
          'excerpt',
          contains('unknown command line argument'),
        ),
      ),
    );
  });

  test('a note, a banner and a clean run are not failures', () async {
    final fake = FakeProcessRunner()
      ..stdoutLines = <String>[
        'Top level design units:',
        '    top',
        'Build succeeded: 0 errors, 0 warnings',
        '[{"severity":"note","message":"see here","location":"a.sv:1:1"}]',
      ];
    final violations = await SlangEngine(
      runner: fake,
    ).run(request(sources: <String>[p.join(tmp.path, 'a.sv')])).toList();
    expect(violations, hasLength(1));
  });
}
