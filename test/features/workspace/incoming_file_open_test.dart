// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/features/project/services/open_project_service.dart';
import 'package:lintcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:lintcrux/features/workspace/providers/workspace_provider.dart';
import 'package:lintcrux/features/workspace/services/incoming_file_kind.dart';
import 'package:lintcrux/features/workspace/services/open_project_in_workspace.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/platform/incoming_file_source.dart';
import 'package:lintcrux/services/workspace/lintcrux_workspace_codec.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/telemetry_test_store.dart';

/// A Finder double-click (or `open -a`, or a drop on the Dock icon) reaches
/// Dart through [IncomingFileSource]. These tests drive that seam with a
/// fake and assert each registered document type lands in the path that
/// already opens it: the one a command-line argument or a menu command
/// takes.
///
/// The native half, `application(_:open:)` in the macOS runner's
/// `AppDelegate.swift`, is verified by building the runner; no test here can
/// launch the app.
void main() {
  group('classifyIncomingFile', () {
    const expected = <String, IncomingFileKind>{
      '/p/top.lintcrux': IncomingFileKind.project,
      '/p/TOP.LINTCRUX': IncomingFileKind.project,
      '/p/soc.crux-project': IncomingFileKind.project,
      '/p/team.lintcrux-workspace': IncomingFileKind.workspace,
      '/p/review.lintcrux-session': IncomingFileKind.session,
      '/p/files.f': IncomingFileKind.filelist,
      '/p/ci.sarif': IncomingFileKind.sarif,
      '/p/top.sv': IncomingFileKind.hdlSource,
      '/p/top.SV': IncomingFileKind.hdlSource,
      '/p/pkg.svh': IncomingFileKind.hdlSource,
      '/p/top.v': IncomingFileKind.hdlSource,
      '/p/defs.vh': IncomingFileKind.hdlSource,
      '/p/top.vhd': IncomingFileKind.hdlSource,
      '/p/top.vhdl': IncomingFileKind.hdlSource,
    };
    for (final entry in expected.entries) {
      test('${entry.key} is ${entry.value.name}', () {
        expect(classifyIncomingFile(entry.key), entry.value);
      });
    }

    test('a file LintCrux does not open is not classified', () {
      expect(classifyIncomingFile('/p/notes.txt'), isNull);
      expect(classifyIncomingFile('/p/data.json'), isNull);
      expect(classifyIncomingFile('/p/noextension'), isNull);
    });

    // Every extension the macOS runner registers must route somewhere, or a
    // double-click on it is accepted by macOS and dropped by the app, which
    // is the defect this seam exists to close.
    // A document type that names a broad system type (every JSON file,
    // every source file) makes Finder offer LintCrux for all of them, and
    // the file-open handler would then refuse each one. Every type the
    // runner claims is one it declares itself, with only extensions it
    // routes, or the one system type that is exactly `.f`.
    test('the macOS runner claims no file type beyond the ones it routes', () {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      final claimed = <String>{
        for (final block in RegExp(
          r'<key>LSItemContentTypes</key>\s*<array>(.*?)</array>',
          dotAll: true,
        ).allMatches(plist))
          for (final m in RegExp(
            '<string>([^<]+)</string>',
          ).allMatches(block.group(1)!))
            m.group(1)!,
      };
      final declared = <String, List<String>>{
        for (final block in RegExp(
          r'<key>UTTypeIdentifier</key>\s*<string>([^<]+)</string>(.*?)'
          r'</dict>\s*</dict>',
          dotAll: true,
        ).allMatches(plist))
          block.group(1)!: [
            for (final m
                in RegExp(
                  '<string>([^<.][^<]*)</string>',
                ).allMatches(
                  block.group(2)!.split('public.filename-extension').last,
                ))
              m.group(1)!,
          ],
      };
      // `.f` is typed by the system, which also gives it `.for`; that one
      // LintCrux refuses with a message.
      const systemTypes = {'public.fortran-source'};
      expect(claimed, isNotEmpty);
      for (final uti in claimed) {
        expect(
          declared.containsKey(uti) || systemTypes.contains(uti),
          isTrue,
          reason:
              'Info.plist claims $uti, which it neither declares nor lists '
              'here as a narrow system type. A broad type such as '
              'public.json offers LintCrux for every such file.',
        );
        for (final ext in declared[uti] ?? const <String>[]) {
          expect(
            classifyIncomingFile('/p/design.$ext'),
            isNotNull,
            reason: '$uti declares .$ext, which nothing routes',
          );
        }
      }
    });

    test('every document type the macOS runner registers is routed', () {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      final types = RegExp(
        r'<key>CFBundleTypeExtensions</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).allMatches(plist);
      final extensions = <String>[
        for (final t in types)
          for (final m in RegExp(
            '<string>([^<]+)</string>',
          ).allMatches(t.group(1)!))
            m.group(1)!,
      ];
      expect(extensions, isNotEmpty);
      for (final ext in extensions) {
        expect(
          classifyIncomingFile('/p/design.$ext'),
          isNotNull,
          reason:
              'macos/Runner/Info.plist registers .$ext, but nothing in '
              'classifyIncomingFile routes it',
        );
      }
    });
  });

  // The native half cannot run in a test, so its contract with this side is
  // checked structurally: the runner overrides the open entry point,
  // registers the plugin once the engine exists, and speaks on the channel
  // names [MacosIncomingFileSource] listens on.
  test('the macOS runner hands file opens to the channels Dart listens on', () {
    final delegate = File(
      'macos/Runner/AppDelegate.swift',
    ).readAsStringSync();
    final window = File(
      'macos/Runner/MainFlutterWindow.swift',
    ).readAsStringSync();
    expect(
      delegate,
      contains(
        'override func application(_ application: NSApplication, '
        'open urls: [URL])',
      ),
    );
    expect(delegate, contains('IncomingFilePlugin.shared.handle(urls: urls)'));
    expect(
      delegate,
      contains('"${MacosIncomingFileSource.methodChannelName}"'),
    );
    expect(delegate, contains('"${MacosIncomingFileSource.eventChannelName}"'));
    expect(delegate, contains('"getInitialFile"'));
    expect(window, contains('IncomingFilePlugin.shared.register(with:'));
  });

  group('MacosIncomingFileSource', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const method = MethodChannel(MacosIncomingFileSource.methodChannelName);
    const events = EventChannel(MacosIncomingFileSource.eventChannelName);

    tearDown(() {
      messenger
        ..setMockMethodCallHandler(method, null)
        ..setMockStreamHandler(events, null);
    });

    test(
      'with no runner handler, nothing was opened and nothing is subscribed',
      () async {
        final source = MacosIncomingFileSource();
        expect(await source.initialFile(), isNull);
        expect(await source.files.isEmpty, isTrue);
      },
    );

    test(
      'with the runner handler, returns the launch file and then streams '
      'later ones',
      () async {
        messenger
          ..setMockMethodCallHandler(method, (call) async {
            expect(call.method, 'getInitialFile');
            return '/designs/top.lintcrux';
          })
          ..setMockStreamHandler(
            events,
            MockStreamHandler.inline(
              onListen: (_, sink) {
                sink
                  ..success('/designs/next.lintcrux-session')
                  ..success('')
                  ..endOfStream();
              },
            ),
          );
        final source = MacosIncomingFileSource();
        expect(await source.initialFile(), '/designs/top.lintcrux');
        expect(await source.files.toList(), [
          '/designs/next.lintcrux-session',
        ]);
      },
    );
  });

  group('LintcruxApp opens what macOS hands it', () {
    late Directory tempDir;
    late _FakeIncomingFiles incoming;
    late _RecordingOpener opener;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      PackageInfo.setMockInitialValues(
        appName: 'lintcrux',
        packageName: 'com.ferrite.lintcrux',
        version: '0.0.0',
        buildNumber: '0',
        buildSignature: '',
      );
      tempDir = await Directory.systemTemp.createTemp('lintcrux_incoming_');
      incoming = _FakeIncomingFiles();
      opener = _RecordingOpener();
    });

    tearDown(() async {
      await incoming.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<void> boot(WidgetTester tester, {String? initialFile}) async {
      incoming.initial = initialFile;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...telemetryDeclinedOverrides(),
            ...lintcruxPhase5Overrides(),
            workspaceServiceProvider.overrideWithValue(
              WorkspaceService(
                codec: const LintcruxWorkspaceCodec(),
                directoryFactory: () async => tempDir,
              ),
            ),
            incomingFileSourceProvider.overrideWithValue(incoming),
            // The SARIF case advances real time; a live CXP server would
            // bind a socket and leave its manifest timer behind.
            cxpServerLifecycleProvider.overrideWith(_StoppedCxpServer.new),
            openProjectInWorkspaceProvider.overrideWithValue((_) => opener),
          ],
          child: const LintcruxApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    L10N l10nOf(WidgetTester tester) =>
        L10N.of(tester.element(find.byType(Navigator).first));

    testWidgets(
      'the project that launched the app opens, as a command-line argument '
      'would',
      (tester) async {
        await boot(tester, initialFile: '/designs/top.lintcrux');
        expect(opener.calls, ['openProject /designs/top.lintcrux']);
      },
    );

    testWidgets('a design manifest opens the project it names', (tester) async {
      await boot(tester, initialFile: '/designs/soc.crux-project');
      expect(opener.calls, ['openProject /designs/soc.crux-project']);
    });

    testWidgets(
      'files opened while running route by kind: workspace as --workspace, '
      'session as --session, project as a positional argument',
      (tester) async {
        await boot(tester);
        expect(opener.calls, isEmpty);

        incoming.add('/w/team.lintcrux-workspace');
        await tester.pumpAndSettle();
        incoming.add('/w/review.lintcrux-session');
        await tester.pumpAndSettle();
        incoming.add('/w/other.lintcrux');
        await tester.pumpAndSettle();

        expect(opener.calls, [
          'openWorkspace /w/team.lintcrux-workspace',
          'openSession /w/review.lintcrux-session',
          'openProject /w/other.lintcrux',
        ]);
      },
    );

    testWidgets(
      'a failed open is reported, the same way the menu command reports it',
      (tester) async {
        opener.projectResult = const OpenProjectFailure('not a project');
        await boot(tester);
        incoming.add('/w/broken.lintcrux');
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'an HDL source with no project open says a project is needed, as File '
      '> Open Sources does',
      (tester) async {
        await boot(tester);
        incoming.add('/w/top.sv');
        await tester.pumpAndSettle();
        expect(
          find.text(l10nOf(tester).openSourcesNoActiveProject),
          findsOneWidget,
        );
        expect(opener.calls, isEmpty);
      },
    );

    testWidgets(
      'a Vivado filelist becomes a project and opens, as --import-filelist '
      'does',
      (tester) async {
        final filelist = File('${tempDir.path}/files.f')
          ..writeAsStringSync('top.sv\n');
        File(
          '${tempDir.path}/top.sv',
        ).writeAsStringSync('module top; endmodule\n');
        await boot(tester);
        incoming.add(filelist.path);
        await tester.pumpAndSettle();
        expect(opener.calls, hasLength(1));
        expect(opener.calls.single, startsWith('openProject '));
        expect(opener.calls.single, endsWith('.lintcrux'));
      },
    );

    testWidgets(
      'a SARIF report opens in the read-only report viewer, as File > '
      'Import SARIF does, without the picker',
      (tester) async {
        // Spelled with `/` on every host. On Windows that makes a mixed
        // path, which the viewer's title must still reduce to the file
        // name.
        final report = File('${tempDir.path}/ci.sarif')
          ..writeAsBytesSync(
            File(
              'test/fixtures/sarif/verilator_basic.sarif.json',
            ).readAsBytesSync(),
          );
        await boot(tester);
        incoming.add(report.path);
        // The report is read from disk, which only completes on the real
        // event loop: advance real time until the viewer shows it.
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (find.text('ci.sarif').evaluate().isEmpty) {
          if (DateTime.now().isAfter(deadline)) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text('ci.sarif'), findsWidgets);
        expect(opener.calls, isEmpty);
      },
    );

    testWidgets('a file LintCrux does not open is refused with a message', (
      tester,
    ) async {
      await boot(tester);
      incoming.add('/w/notes.txt');
      await tester.pumpAndSettle();
      expect(
        find.text(l10nOf(tester).incomingFileNotSupported('notes.txt')),
        findsOneWidget,
      );
      expect(opener.calls, isEmpty);
    });
  });
}

class _FakeIncomingFiles implements IncomingFileSource {
  String? initial;
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  void add(String path) => _controller.add(path);

  Future<void> close() => _controller.close();

  @override
  Future<String?> initialFile() async => initial;

  @override
  Stream<String> get files => _controller.stream;
}

/// Records which opener entry point each file reached, and answers without
/// touching the disk.
class _RecordingOpener implements OpenProjectInWorkspace {
  final List<String> calls = <String>[];
  OpenProjectResult projectResult = const OpenProjectFailure('recorded');

  @override
  Future<OpenProjectResult> openProject(String rawPath) async {
    calls.add('openProject $rawPath');
    return projectResult;
  }

  @override
  Future<OpenProjectResult> openSession(String path) async {
    calls.add('openSession $path');
    return const OpenProjectFailure('recorded');
  }

  @override
  Future<String?> openWorkspace(String path) async {
    calls.add('openWorkspace $path');
    return null;
  }

  @override
  Ref get ref => throw UnimplementedError();

  @override
  ProviderContainer Function(crux.TabId tabId) get tabsForId =>
      throw UnimplementedError();
}

class _StoppedCxpServer extends CxpServerLifecycle {
  @override
  Future<CxpServerLifecycleState> build() async =>
      const CxpServerLifecycleState(running: false, boundPort: null);
}
