// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/hdl_language.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/interfaces/lint_engine.dart';
import 'package:lintcrux/domain/models/diagnostics/diagnostics_report.dart';
import 'package:lintcrux/domain/models/engine_binary_override.dart';
import 'package:lintcrux/domain/models/engine_config.dart';
import 'package:lintcrux/domain/models/engine_run_status.dart';
import 'package:lintcrux/domain/models/lint_project.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:lintcrux/features/engine_config/providers/engine_versions_provider.dart';
import 'package:lintcrux/features/run/providers/lint_run_notifier.dart';
import 'package:lintcrux/features/settings/providers/app_settings_provider.dart';
import 'package:lintcrux/services/engines/bundled_binary_resolver.dart';
import 'package:lintcrux/services/engines/engine_registry.dart';
import 'package:lintcrux/services/engines/engine_registry_provider.dart';
import 'package:lintcrux/services/persistence/engine_binary_overrides_settings_provider.dart';
import 'package:lintcrux/services/project/current_project_provider.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEngine implements LintEngine {
  _FakeEngine(this.id);
  @override
  final String id;
  @override
  String get displayName => id;
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    supportedLanguages: {HdlLanguage.systemVerilog},
  );
  @override
  Future<String?> detectVersion(EngineBinaryConfig config) async => null;
  @override
  Stream<Violation> run(LintRunRequest request) async* {}
  @override
  Stream<Violation> runIncremental(
    LintRunRequest request,
    Set<String> changedFiles,
  ) => run(request);
  @override
  void cancel() {}
}

class _SeedProjectNotifier extends CurrentProjectNotifier {
  _SeedProjectNotifier(this._seed);
  final LintProject? _seed;

  @override
  LintProject? build() => _seed;
}

class _SeedRunStateNotifier extends LintRunNotifier {
  _SeedRunStateNotifier(this._seed);
  final LintRunState _seed;

  @override
  LintRunState build() => _seed;
}

Violation _v(String engineId, String rule, Severity severity) => Violation(
  engineId: engineId,
  ruleId: '$engineId/$rule',
  severity: severity,
  message: 'msg',
  location: const SourceLocation(file: '/proj/a.sv', line: 1, column: 1),
);

const _project = LintProject(
  name: 'demo',
  rootPath: '/proj',
  sourceFiles: ['/proj/a.sv', '/proj/b.sv'],
);

/// Overrides for a tab with [_project] open over two fake engines, where
/// the version probe answered for [versions] only.
List<Override> _tabOverrides({
  LintRunState runState = LintRunState.idle,
  Map<String, String> versions = const {'verilator': 'Verilator 5.022'},
  Map<String, EngineBinaryOverride> binaries = const {},
}) => [
  engineRegistryProvider.overrideWithValue(
    EngineRegistry([_FakeEngine('verilator'), _FakeEngine('verible')]),
  ),
  currentProjectProvider.overrideWith(() => _SeedProjectNotifier(_project)),
  lintRunProvider.overrideWith(() => _SeedRunStateNotifier(runState)),
  violationStoreProvider.overrideWithValue(
    InMemoryViolationStore()..replaceFromEngine('verilator', [
      _v('verilator', 'UNUSED', Severity.warning),
      _v('verilator', 'UNUSED2', Severity.warning),
      _v('verilator', 'WIDTH', Severity.error),
    ]),
  ),
  engineVersionsProvider.overrideWith((ref) async => versions),
  launchEngineBinaryOverridesProvider.overrideWithValue(binaries),
];

EngineDiagnostics _engine(TabDiagnosticsReport report, String id) =>
    report.engines.singleWhere((e) => e.engineId == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('buildTabDiagnosticsReport / tabDiagnosticsReportProvider', () {
    test('returns null when no project is loaded', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(tabDiagnosticsReportProvider), isNull);
    });

    test(
      'assembles per-engine durations, binaries, probed versions and '
      'per-severity counts from the live providers',
      () async {
        final startedAt = DateTime(2026, 7, 1, 12);
        final completedAt = startedAt.add(const Duration(milliseconds: 250));
        final container = ProviderContainer(
          overrides: _tabOverrides(
            runState: LintRunState(
              statuses: {
                'verilator': EngineRunStatus(
                  engineId: 'verilator',
                  phase: EngineRunPhase.completed,
                  startedAt: startedAt,
                  completedAt: completedAt,
                ),
                'verible': EngineRunStatus.idle('verible'),
              },
            ),
            binaries: const {
              'verilator': EngineBinaryOverride(
                source: EngineBinarySource.custom,
                path: '/opt/verilator/bin/verilator',
              ),
            },
          ),
        );
        addTearDown(container.dispose);
        await container.read(engineVersionsProvider.future);

        final report = container.read(tabDiagnosticsReportProvider)!;
        expect(report.projectPath, '/proj');
        expect(report.sourceFileCount, 2);
        expect(report.lastRunWallMs, 250);
        expect(report.engines.map((e) => e.engineId), [
          'verilator',
          'verible',
        ]);

        final verilator = _engine(report, 'verilator');
        expect(verilator.binary, 'custom: /opt/verilator/bin/verilator');
        expect(verilator.version, 'Verilator 5.022');
        expect(verilator.durationMs, 250);
        expect(verilator.severityCounts, {
          Severity.warning: 2,
          Severity.error: 1,
        });

        // Never started, no custom binary, and the probe got nothing.
        final verible = _engine(report, 'verible');
        expect(verible.binary, 'PATH');
        expect(verible.version, kEngineNotDetected);
        expect(verible.durationMs, isNull);
        expect(verible.severityCounts, isEmpty);
      },
    );

    test(
      'the engine lines no longer hard-code "system PATH" or a runtime-probe '
      'placeholder, and an engine that did not run reports no duration',
      () async {
        final container = ProviderContainer(overrides: _tabOverrides());
        addTearDown(container.dispose);
        await container.read(engineVersionsProvider.future);

        final text = container
            .read(tabDiagnosticsReportProvider)!
            .toPlainText();
        expect(text, isNot(contains('system PATH')));
        expect(text, isNot(contains('probe at runtime')));
        expect(text, isNot(contains('duration: 0 ms')));
        expect(text, isNot(contains('Last run wall time: 0 ms')));
        expect(text, isNot(contains('Last run')));
        expect(text, contains('version: Verilator 5.022'));
      },
    );

    test(
      'before the version probe resolves the version line is absent, not a '
      'placeholder',
      () {
        final container = ProviderContainer(overrides: _tabOverrides());
        addTearDown(container.dispose);

        final report = container.read(tabDiagnosticsReportProvider)!;
        expect(report.engines.every((e) => e.version == null), isTrue);
      },
    );

    test('in the browser no binary or version is reported', () async {
      final container = ProviderContainer(
        overrides: [
          ..._tabOverrides(),
          engineVersionProbingSupportedProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final report = container.read(tabDiagnosticsReportProvider)!;
      expect(report.engines.every((e) => e.binary == null), isTrue);
      expect(report.engines.every((e) => e.version == null), isTrue);
    });

    test(
      'a run still in flight (no completedAt) is timed against "now" '
      'rather than left at zero duration',
      () {
        final startedAt = DateTime.now().subtract(
          const Duration(milliseconds: 40),
        );
        final container = ProviderContainer(
          overrides: _tabOverrides(
            runState: LintRunState(
              isRunning: true,
              statuses: {
                'verilator': EngineRunStatus(
                  engineId: 'verilator',
                  phase: EngineRunPhase.running,
                  startedAt: startedAt,
                ),
              },
            ),
          ),
        );
        addTearDown(container.dispose);

        final report = container.read(tabDiagnosticsReportProvider)!;
        final ms = _engine(report, 'verilator').durationMs;
        expect(ms, greaterThan(0));
        expect(report.lastRunWallMs, ms);
      },
    );
  });

  group('describeEngineBinary', () {
    test('custom names the configured path', () {
      expect(
        describeEngineBinary(
          'slang',
          const EngineBinaryConfig(
            source: EngineBinarySource.custom,
            path: '/tools/slang',
          ),
        ),
        'custom: /tools/slang',
      );
    });

    test('auto-detect is a PATH lookup', () {
      expect(
        describeEngineBinary('slang', const EngineBinaryConfig.system()),
        'PATH',
      );
    });

    test(
      'bundled names the shipped binary it found, under the binary id the '
      'engine runs (CDC runs Yosys), and says when it fell back to PATH',
      () {
        final root = Directory.systemTemp.createTempSync('lc_bundled_');
        addTearDown(() => root.deleteSync(recursive: true));
        final resolver = BundledBinaryResolver(overrideRoot: root.path);
        expect(
          describeEngineBinary(
            'cdc',
            const EngineBinaryConfig.bundled(),
            resolver: resolver,
          ),
          'PATH (no bundled binary found)',
        );

        final platformDir = _platformDirFor(root.path);
        if (platformDir == null) return;
        final exe = File(
          p.join(platformDir, Platform.isWindows ? 'yosys.exe' : 'yosys'),
        )..createSync(recursive: true);
        expect(
          describeEngineBinary(
            'cdc',
            const EngineBinaryConfig.bundled(),
            resolver: resolver,
          ),
          'bundled: ${exe.path}',
        );
      },
    );
  });

  group('buildAppDiagnosticsReport / appDiagnosticsReportProvider', () {
    test(
      "reports the process's resident memory and the active tab's count",
      () {
        final container = ProviderContainer(
          overrides: [
            violationStoreProvider.overrideWithValue(
              InMemoryViolationStore()..replaceFromEngine('verilator', [
                _v('verilator', 'UNUSED', Severity.warning),
                _v('verilator', 'WIDTH', Severity.error),
              ]),
            ),
            residentMemoryReaderProvider.overrideWithValue(
              () => 64 * 1024 * 1024,
            ),
          ],
        );
        addTearDown(container.dispose);

        final report = container.read(appDiagnosticsReportProvider);
        expect(report.activeTabViolationCount, 2);
        expect(report.residentMemoryBytes, 64 * 1024 * 1024);
        expect(report.toPlainText(), contains('Resident memory: 64.0 MiB'));
      },
    );

    test('the default reader measures this process', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final rss = container
          .read(appDiagnosticsReportProvider)
          .residentMemoryBytes;
      expect(rss, isNotNull);
      expect(rss, greaterThan(0));
    });

    test('where memory cannot be read, the line is absent, not 0', () {
      final container = ProviderContainer(
        overrides: [residentMemoryReaderProvider.overrideWithValue(() => null)],
      );
      addTearDown(container.dispose);
      final text = container.read(appDiagnosticsReportProvider).toPlainText();
      expect(text, isNot(contains('memory')));
      expect(text, isNot(contains('0.0 MiB')));
    });

    test('an empty store reports zero violations', () {
      final container = ProviderContainer(
        overrides: [
          violationStoreProvider.overrideWithValue(InMemoryViolationStore()),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(appDiagnosticsReportProvider).activeTabViolationCount,
        0,
      );
    });
  });

  group('diagnosticsEnabledProvider', () {
    test('is always on when the build mode forces it (debug, profile)', () {
      final container = ProviderContainer(
        overrides: [
          diagnosticsForcedByBuildModeProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(appSettingsProvider).diagnosticsEnabled, isFalse);
      expect(container.read(diagnosticsEnabledProvider), isTrue);
    });

    test(
      'in a release build it follows the Settings switch, off by default',
      () {
        final container = ProviderContainer(
          overrides: [
            diagnosticsForcedByBuildModeProvider.overrideWithValue(false),
          ],
        );
        addTearDown(container.dispose);
        expect(container.read(diagnosticsEnabledProvider), isFalse);

        container
            .read(appSettingsProvider.notifier)
            .setDiagnosticsEnabled(enabled: true);
        expect(container.read(diagnosticsEnabledProvider), isTrue);

        container
            .read(appSettingsProvider.notifier)
            .setDiagnosticsEnabled(enabled: false);
        expect(container.read(diagnosticsEnabledProvider), isFalse);
      },
    );
  });

  test(
    'no diagnostics source fills a line with a stand-in: no hard-coded heap '
    'or frame rate, no "system PATH", no runtime-probe or unknown '
    'placeholder, no zero default for a duration',
    () {
      const files = [
        'lib/domain/models/diagnostics/diagnostics_report.dart',
        'lib/features/diagnostics/providers/diagnostics_providers.dart',
        'lib/features/diagnostics/widgets/app_diagnostics_dialog.dart',
        'lib/features/diagnostics/widgets/tab_diagnostics_drawer.dart',
      ];
      final banned = <Pattern>[
        RegExp(r'HeapBytes:\s*0\b'),
        RegExp('framesPerSecond|FPS:'),
        'system PATH',
        'probe at runtime',
        '(unknown)',
        RegExp(r'\?\?\s*0\}\s*ms'),
        RegExp(r'durations?\[\w+\]\s*=\s*0\b'),
      ];
      for (final path in files) {
        final source = File(path).readAsStringSync();
        for (final pattern in banned) {
          expect(
            pattern.allMatches(source),
            isEmpty,
            reason:
                '$path contains "$pattern": a diagnostics line must be '
                'measured or absent',
          );
        }
      }
    },
  );
}

/// The directory [BundledBinaryResolver] probes under [root] on this host,
/// or null on a host it does not support.
String? _platformDirFor(String root) {
  if (Platform.isMacOS) return p.join(root, 'macos-universal');
  if (Platform.isLinux) return p.join(root, 'linux-x86_64');
  if (Platform.isWindows) return p.join(root, 'windows-x86_64');
  return null;
}
