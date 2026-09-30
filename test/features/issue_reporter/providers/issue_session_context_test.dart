// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/engine_config/providers/engine_versions_provider.dart';
import 'package:lintcrux/features/issue_reporter/providers/issue_session_context.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// A realistically populated session: a project rooted at a real-looking
/// absolute path, with source files, and violations carrying real file
/// locations. Every one of those strings is a path the report must not leak.
const _projectRoot = '/Users/jane/work/soc-top';
const _sourceA = '/Users/jane/work/soc-top/rtl/uart_tx.sv';
const _sourceB = '/Users/jane/work/soc-top/rtl/axi_arbiter.sv';
const _windowsSource = r'C:\Users\jane\work\soc-top\rtl\clkgen.vhd';

const _project = LintProject(
  name: 'soc-top',
  rootPath: _projectRoot,
  sourceFiles: [_sourceA, _sourceB, _windowsSource],
  enabledEngineIds: ['verilator', 'verible'],
);

Violation _violation({
  required String engineId,
  required String ruleId,
  required Severity severity,
  required String file,
  int line = 42,
}) => Violation(
  engineId: engineId,
  ruleId: ruleId,
  severity: severity,
  message: 'Signal is not used: $file:$line',
  location: SourceLocation(file: file, line: line, column: 7),
);

final _violations = <Violation>[
  _violation(
    engineId: 'verilator',
    ruleId: 'verilator/UNUSEDSIGNAL',
    severity: Severity.warning,
    file: _sourceA,
  ),
  _violation(
    engineId: 'verilator',
    ruleId: 'verilator/WIDTHTRUNC',
    severity: Severity.error,
    file: _sourceB,
    line: 118,
  ),
  _violation(
    engineId: 'verible',
    ruleId: 'verible/line-length',
    severity: Severity.note,
    file: _windowsSource,
    line: 9,
  ),
];

ProviderContainer _container({
  bool loaded = true,
  Map<String, String> versions = const {
    'verilator': 'Verilator 5.022 2024-07-01 rev v5.022',
    'verible': 'v0.0-3752-g8b9f4d0',
  },
}) {
  final store = InMemoryViolationStore();
  if (loaded) {
    store
      ..replaceFromEngine(
        'verilator',
        _violations.where((v) => v.engineId == 'verilator').toList(),
      )
      ..replaceFromEngine(
        'verible',
        _violations.where((v) => v.engineId == 'verible').toList(),
      );
  }
  final container = ProviderContainer(
    overrides: [
      violationStoreProvider.overrideWith((ref) {
        ref.onDispose(store.dispose);
        return store;
      }),
      currentProjectProvider.overrideWith(CurrentProjectNotifier.new),
      engineVersionsProvider.overrideWith((ref) async => versions),
      // The binding the app installs, so the snapshot under test is the one
      // the reporter reads.
      cruxIssueSessionContextProvider.overrideWith(
        buildLintcruxIssueSessionContext,
      ),
    ],
  );
  if (loaded) {
    container.read(currentProjectProvider.notifier).load(_project);
  }
  addTearDown(container.dispose);
  return container;
}

/// Renders the Session State markdown exactly the way the reporter does.
String _renderSessionBody(CruxIssueSessionContext context) {
  const service = CruxIssueReporterService(
    config: CruxIssueReporterConfig(
      productName: 'LintCrux',
      repositorySlug: 'Ferrite-Engineering/lintcrux',
    ),
  );
  return service
      .buildSessionCategory(title: 'Session State', context: context)
      .markdownBody;
}

Future<CruxIssueSessionContext> _snapshot(ProviderContainer container) async {
  // Warm the version probe exactly as `LintcruxIssueReporter.open` does, so
  // the snapshot under test is the one a real report carries.
  await container.read(engineVersionsProvider.future);
  return await container.read(cruxIssueSessionContextProvider);
}

void main() {
  group('buildLintcruxIssueSessionContext — privacy contract', () {
    test(
      'PRIVACY: a Session State body carries no file paths',
      () async {
        // The assertion `crux_issue_reporter` makes over a synthetic
        // contributor, repeated here over the REAL LintCrux contributor and a
        // realistically populated session. LintCrux is the highest-risk
        // consumer in the suite: violations carry `location.file` and a line
        // number natively, the project carries `rootPath` and a source-file
        // list, and the table filters carry user-typed text. A single one of
        // those reaching the body would publish a user's filesystem layout to
        // a public issue tracker.
        final container = _container();
        final body = _renderSessionBody(await _snapshot(container));

        expect(body, isNotEmpty);
        expect(body, isNot(contains('/')));
        expect(body, isNot(contains(r'\')));
      },
    );

    test('PRIVACY: no fragment of any real path survives', () async {
      final container = _container();
      final body = _renderSessionBody(await _snapshot(container));

      for (final leak in <String>[
        _projectRoot,
        _sourceA,
        _sourceB,
        _windowsSource,
        'soc-top',
        'uart_tx',
        'axi_arbiter',
        'clkgen',
        '.sv',
        '.vhd',
        'Users',
        'jane',
      ]) {
        expect(
          body,
          isNot(contains(leak)),
          reason: '"$leak" leaked into the Session State body',
        );
      }
    });

    test(
      'PRIVACY: a user-typed rule filter is reported as a flag, never as text',
      () async {
        final container = _container();
        container
            .read(violationTableStateProvider.notifier)
            .setRuleSubstring('/Users/jane/secret_project/top.sv');

        final body = _renderSessionBody(await _snapshot(container));
        expect(body, contains('Rule text filter set:** yes'));
        expect(body, isNot(contains('secret_project')));
        expect(body, isNot(contains('/')));
      },
    );

    test(
      'PRIVACY: an engine that prints its install prefix is scrubbed',
      () async {
        final container = _container(
          versions: const {
            'verilator': 'Verilator 5.022 (built from /opt/jane/src/verilator)',
            'verible': r'verible C:\tools\verible\v0.0-3752 build',
          },
        );
        final body = _renderSessionBody(await _snapshot(container));
        expect(body, isNot(contains('/')));
        expect(body, isNot(contains(r'\')));
        // The useful part survives the scrub.
        expect(body, contains('Verilator 5.022'));
      },
    );

    test('scrubEngineVersionForReport drops path-shaped tokens', () {
      expect(
        scrubEngineVersionForReport('Verilator 5.022 /opt/x/verilator'),
        'Verilator 5.022',
      );
      expect(
        scrubEngineVersionForReport(r'verible C:\tools\verible v0.0-3752'),
        'verible v0.0-3752',
      );
      // Only the first line is considered.
      expect(
        scrubEngineVersionForReport('slang version 6.0\nbuilt at /tmp/slang'),
        'slang version 6.0',
      );
      // A value that is nothing but a path degrades to a placeholder rather
      // than to the empty string, so the field never reads as blank. The
      // placeholder is the suite-shared `CruxIssueFallback.unavailable`,
      // not a LintCrux spelling: a maintainer reads four products' reports
      // side by side, so the vocabulary is worth having in one place.
      expect(
        scrubEngineVersionForReport('/opt/only/a/path'),
        CruxIssueFallback.unavailable,
      );
      // Long banners are truncated with an ellipsis, not silently cut.
      expect(scrubEngineVersionForReport('x' * 200), endsWith('…'));
    });
  });

  group('buildLintcruxIssueSessionContext — content', () {
    test('reports engine versions, which is why the field exists', () async {
      final container = _container();
      final body = _renderSessionBody(await _snapshot(container));
      expect(body, contains('Verilator 5.022'));
      expect(body, contains('v0.0-3752-g8b9f4d0'));
    });

    test('an unprobed engine reads "(not detected)", never blank', () async {
      final container = _container(versions: const {});
      final body = _renderSessionBody(await _snapshot(container));
      expect(body, contains('verilator (not detected)'));
      expect(body, contains('verible (not detected)'));
    });

    test('reports violation counts by severity', () async {
      final container = _container();
      final snapshot = await _snapshot(container);
      final total = snapshot.fields.firstWhere(
        (f) => f.label == 'Violations total',
      );
      expect(total.value, '3');

      final bySeverity = snapshot.fields.firstWhere(
        (f) => f.label == 'Violations by severity',
      );
      expect(bySeverity.value, contains('error 1'));
      expect(bySeverity.value, contains('warning 1'));
      expect(bySeverity.value, contains('note 1'));
    });

    test('reports distinct firing rules as a count', () async {
      final container = _container();
      final snapshot = await _snapshot(container);
      expect(
        snapshot.fields
            .firstWhere((f) => f.label == 'Distinct rules firing')
            .value,
        '3',
      );
    });

    test('reports source-file count without naming a file', () async {
      final container = _container();
      final snapshot = await _snapshot(container);
      expect(
        snapshot.fields.firstWhere((f) => f.label == 'Source files').value,
        '3',
      );
    });

    test('an empty session still contributes a usable snapshot', () async {
      final container = _container(loaded: false);
      final snapshot = await _snapshot(container);
      expect(snapshot.isNotEmpty, isTrue);
      expect(
        snapshot.fields.firstWhere((f) => f.label == 'Project loaded').value,
        'no',
      );
      expect(
        snapshot.fields.firstWhere((f) => f.label == 'Violations total').value,
        '0',
      );
      expect(_renderSessionBody(snapshot), isNot(contains('/')));
    });

    test('carries the attributes the Pro overlay reads', () async {
      final container = _container();
      final snapshot = await _snapshot(container);
      expect(snapshot.attributes['projectLoaded'], isTrue);
      expect(snapshot.attributes['violationCount'], 3);
      expect(snapshot.attributes['waiverCount'], 0);
      expect(snapshot.attributes['enabledEngineCount'], 2);
    });
  });
}
