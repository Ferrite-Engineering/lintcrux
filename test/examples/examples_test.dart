// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/project/project_file_codec.dart';
import 'package:lintcrux/services/project/project_path_resolver.dart';
import 'package:lintcrux/services/run/engine_run_planner.dart';
import 'package:lintcrux/services/sarif/sarif_reader.dart';
import 'package:path/path.dart' as p;

/// Guards for the shipped `examples/` projects.
///
/// The examples exist because LintCrux had nothing a new user could open:
/// no example project, and the only `.lintcrux` files in the repo lived
/// under `test/fixtures/`, which reads as internal scaffolding. Something a
/// person is told to open must actually open.
///
/// **Existence is not loadability.** Every assertion below goes through
/// the real `ProjectFileCodec`, the real `resolveProjectPaths` and the
/// real `EngineRunPlanner` — the same three the desktop open flow and the
/// headless CLI use. A guard that asserted `File(...).existsSync()` would
/// pass on a `.lintcrux` that names a source file nobody committed, which
/// is precisely the failure a first-run user would hit.
void main() {
  final examplesRoot = Directory(p.join(Directory.current.path, 'examples'));

  List<Directory> discover() =>
      examplesRoot
          .listSync()
          .whereType<Directory>()
          .where((d) => File(p.join(d.path, 'project.lintcrux')).existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  group('examples/', () {
    test('ships at least two openable projects, plus a README', () {
      expect(examplesRoot.existsSync(), isTrue);
      expect(File(p.join(examplesRoot.path, 'README.md')).existsSync(), isTrue);
      final found = discover().map((d) => p.basename(d.path)).toSet();
      expect(
        found,
        containsAll(<String>['getting-started', 'vhdl-getting-started']),
      );
    });

    for (final dir in discover()) {
      final name = p.basename(dir.path);
      group(name, () {
        late final LintProject authored;
        late final LintProject resolved;

        setUpAll(() {
          final raw = File(
            p.join(dir.path, 'project.lintcrux'),
          ).readAsStringSync();
          // Decoding is the first thing the GUI does with a picked file.
          authored = const ProjectFileCodec().decode(raw);
          // …and this is the second. A project that decodes but resolves
          // to paths nobody can open is still a broken example.
          resolved = resolveProjectPaths(authored, dir.path);
        });

        test('is authored portably (relative root, bare source names)', () {
          // A committed example must not carry the author's checkout
          // layout. `rootPath: "."` plus bare filenames is the form the
          // resolver documents as portable.
          expect(
            p.isAbsolute(authored.rootPath),
            isFalse,
            reason: 'rootPath must be relative so the example travels',
          );
          for (final f in authored.sourceFiles) {
            expect(p.isAbsolute(f), isFalse, reason: '$f must be relative');
          }
          expect(authored.name, isNotEmpty);
          expect(authored.sourceFiles, isNotEmpty);
        });

        test('every declared source resolves to a file that exists', () {
          expect(resolved.rootPath, dir.path);
          for (final f in resolved.sourceFiles) {
            expect(
              File(f).existsSync(),
              isTrue,
              reason:
                  '$name declares source "$f" which is not committed — the '
                  'example would open to an empty project',
            );
          }
          for (final d in resolved.includePaths) {
            expect(Directory(d).existsSync(), isTrue, reason: d);
          }
        });

        test('names only engines LintCrux actually registers', () {
          final registered = defaultEngineRegistry().engineIds.toSet();
          for (final id in authored.enabledEngineIds) {
            expect(
              registered,
              contains(id),
              reason:
                  '$name enables engine "$id", which no build of LintCrux '
                  'has — the run would fail with "Unknown engine id"',
            );
          }
        });

        test('the run planner routes every source to at least one engine', () {
          // The gap this closes: an example whose `language` and whose
          // `enabledEngineIds` disagree plans zero work and reports
          // "No engine had a compatible source file", which reads to a
          // new user as "this tool does nothing".
          final plan = const EngineRunPlanner().plan(
            project: resolved,
            registry: defaultEngineRegistry(),
            binaryConfigFor: (_) => const EngineBinaryConfig.system(),
          );
          expect(plan.unknownEngineIds, isEmpty);
          expect(
            plan.pairs,
            isNotEmpty,
            reason: '$name plans no engine run at all',
          );
          final routed = <String>{
            for (final pair in plan.pairs) ...pair.request.sourceFiles,
          };
          for (final f in resolved.sourceFiles) {
            expect(
              routed,
              contains(f),
              reason:
                  '$name declares "$f" but the language router hands it to '
                  'no enabled engine',
            );
          }
        });

        test('declares a language the source extensions agree with', () {
          const vhdlExtensions = <String>{'.vhd', '.vhdl'};
          for (final f in resolved.sourceFiles) {
            final isVhdl = vhdlExtensions.contains(p.extension(f));
            expect(
              isVhdl,
              authored.language == HdlLanguage.vhdl,
              reason: '$name declares ${authored.language.name} but ships $f',
            );
          }
        });
      });
    }

    group('getting-started/report.sarif', () {
      final reportPath = p.join(
        examplesRoot.path,
        'getting-started',
        'report.sarif',
      );

      test('exists — it is the no-toolchain entry point', () {
        expect(
          File(reportPath).existsSync(),
          isTrue,
          reason:
              'regenerate with ./tool/regen_example_report.sh — this file '
              'is what a user with no engine installed opens',
        );
      });

      test('parses through the real SarifReader and carries findings', () {
        final report = const SarifReader().read(
          File(reportPath).readAsStringSync(),
        );
        expect(report.runs, isNotEmpty);
        final violations = <String>[
          for (final run in report.runs)
            for (final v in run.violations) v.ruleId,
        ];
        expect(
          violations,
          isNotEmpty,
          reason: 'a report with nothing in it demonstrates nothing',
        );
        // The findings must be the example's own, not some other capture.
        expect(
          violations.toSet(),
          containsAll(<String>[
            'verilator/LATCH',
            'verilator/UNUSEDSIGNAL',
            'verilator/UNDRIVEN',
          ]),
        );
      });

      test('carries no absolute path from the machine that generated it', () {
        // `--sarif` writes originalUriBaseIds as an absolute file:// URI.
        // Committing that leaks a home directory and makes the report
        // machine-specific; regen_example_report.sh rebases it.
        final doc =
            jsonDecode(File(reportPath).readAsStringSync())
                as Map<String, dynamic>;
        for (final run in (doc['runs'] as List).cast<Map<String, dynamic>>()) {
          final bases = run['originalUriBaseIds'] as Map<String, dynamic>?;
          if (bases == null) continue;
          for (final entry in bases.entries) {
            final uri = (entry.value as Map<String, dynamic>)['uri'] as String;
            expect(
              uri.startsWith('file://'),
              isFalse,
              reason:
                  'originalUriBaseIds[${entry.key}] = "$uri" is an absolute '
                  'host path — run ./tool/regen_example_report.sh',
            );
          }
        }
        expect(
          File(reportPath).readAsStringSync().contains('/Users/'),
          isFalse,
        );
      });

      test('every cited artifact is a file the example ships', () {
        final doc =
            jsonDecode(File(reportPath).readAsStringSync())
                as Map<String, dynamic>;
        final dir = p.join(examplesRoot.path, 'getting-started');
        for (final run in (doc['runs'] as List).cast<Map<String, dynamic>>()) {
          for (final result
              in (run['results'] as List? ?? const <dynamic>[])
                  .cast<Map<String, dynamic>>()) {
            for (final loc
                in (result['locations'] as List).cast<Map<String, dynamic>>()) {
              final artifact =
                  (loc['physicalLocation']
                          as Map<String, dynamic>)['artifactLocation']
                      as Map<String, dynamic>;
              final uri = artifact['uri'] as String;
              expect(
                File(p.join(dir, uri)).existsSync(),
                isTrue,
                reason: 'report.sarif cites "$uri", which is not committed',
              );
            }
          }
        }
      });
    });
  });
}
