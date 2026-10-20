// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LintCrux on the shared CXP lifecycle, end to end over real loopback sockets:
// what LintCrux does with what a peer sends (the highlight it applies to the
// table, the editor it opens, the paths it refuses, the project it opens), and
// the acknowledgement the shared runtime sends back. Starting, stopping,
// discovery and the peer list are the shared runtime's own tests.

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/source_location.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/features/remote/providers/cxp_request_handler_provider.dart';
import 'package:lintcrux/features/violations/providers/selected_violation_provider.dart';
import 'package:lintcrux/features/violations/providers/violation_table_provider.dart';
import 'package:lintcrux/services/editor/click_to_source_service.dart';
import 'package:lintcrux/services/editor/editor_command_provider.dart';
import 'package:lintcrux/services/remote/cxp/cxp_project_open_handle.dart';
import 'package:lintcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_cxp_binding.dart';
import 'package:lintcrux/services/remote/cxp/lintcrux_name_resolver.dart';
import 'package:lintcrux/services/violations/in_memory_violation_store.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/host_absolute_path.dart';
import '../../support/host_independent_editor_resolver.dart';
import '../../support/noop_process.dart';
import '../../support/telemetry_test_store.dart';

/// Editor launcher that records its calls and never actually spawns a
/// real editor. `launch` hands back a [NoopProcess] so the surrounding
/// `ClickToSourceService` reports success.
class RecordingLauncher implements EditorLauncher {
  /// Calls received, oldest first. Each entry is `[executable, ...args]`.
  final List<List<String>> calls = <List<String>>[];

  @override
  Future<Process> launch(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    return const NoopProcess();
  }
}

ProviderContainer buildContainer({
  required String manifestDir,
  required InMemoryViolationStore store,
  required RecordingLauncher launcher,
  List<String>? openedProjects,
  CxpProjectOpenHandle? openHandle,
  CxpWorkspaceStore? workspaceStore,
}) {
  return ProviderContainer(
    overrides: <Override>[
      ...telemetryDeclinedOverrides(),
      // The binding, the handler and the transport, as `bootstrap()` installs
      // them (`lintcruxCxpOverrides`), pointed at a temp discovery directory
      // and an OS-chosen port.
      cruxCxpProductBindingProvider.overrideWithValue(kLintcruxCxpBinding),
      cruxCxpLaunchSettingsProvider.overrideWithValue(
        const CruxCxpSettings(enabled: true, port: 0),
      ),
      cruxCxpTransportAvailableProvider.overrideWithValue(true),
      cruxCxpRequestHandlerProvider.overrideWith(LintCruxCxpWrappedHandler.new),
      cruxCxpManifestDirectoryProvider.overrideWith((ref) async => manifestDir),
      if (workspaceStore != null)
        cxpWorkspaceStoreProvider.overrideWithValue(workspaceStore),
      // The projects the user has opened, as `WorkspaceRoot` would publish
      // them. This container mounts no workspace, so without it the
      // production containment rule (CXP §11) would see nothing open and
      // refuse every peer-supplied path. Overriding the HANDLE rather than
      // `cxpPathContainmentProvider` keeps the production roots function in
      // the path under test.
      cxpProjectOpenHandleProvider.overrideWithValue(
        (openHandle ?? CxpProjectOpenHandle())
          ..projectPaths = () =>
              openedProjects ??
              <String>[hostAbsolute('/proj/project.lintcrux')],
      ),
      violationStoreProvider.overrideWithValue(store),
      clickToSourceServiceProvider.overrideWithValue(
        ClickToSourceService(
          commandFor: () => EditorCommand.vsCode,
          launcher: launcher,
          resolver: hostIndependentEditorResolver,
        ),
      ),
    ],
  );
}

Future<void> _pumpUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Predicate not satisfied within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InMemoryViolationStore store;
  late RecordingLauncher launcher;
  ProviderContainer? container;
  LocalCxpClient? client;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = Directory.systemTemp.createTempSync('lintcrux_cxp_test_');
    store = InMemoryViolationStore();
    launcher = RecordingLauncher();
  });

  tearDown(() async {
    if (client != null) {
      try {
        await client!.disconnect();
      } on Object {
        // best effort
      }
    }
    container?.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Starts the runtime and connects a peer called [name] to it. Returns the
  /// acknowledgements the peer receives.
  Future<List<CxpMessage>> connectPeer(String name) async {
    final runtime = await container!.read(cruxCxpRuntimeProvider.future);
    expect(runtime, isNotNull);
    client = LocalCxpClient(
      selfIdentity: PeerIdentity(
        peerId: 'peer-$name',
        productName: name,
        productVersion: '0.5.0',
      ),
    );
    final acks = <CxpMessage>[];
    client!.inbound.listen((m) => acks.add(m.message));
    await client!.connect(
      host: '127.0.0.1',
      port: runtime!.boundPort!,
      token: cxpProcessAuthToken,
    );
    return acks;
  }

  group('LintCrux on the shared CXP runtime', () {
    test('the binding is what LintCrux announces', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final runtime = await container!.read(cruxCxpRuntimeProvider.future);
      expect(runtime!.isAvailable, isTrue);
      expect(runtime.selfIdentity.productName, 'lintcrux');
      expect(
        runtime.selfIdentity.capabilities,
        containsAll(<String>[
          'cxp.accepts:rule',
          'cxp.accepts:source',
          'cxp.accepts:signal',
          'cxp.accepts:instance',
        ]),
      );
    });

    test('end-to-end RequestHighlight rule kind selects the violation '
        'and clears filters', () async {
      const v = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'unused',
        location: SourceLocation(
          file: '/proj/cpu.sv',
          line: 42,
          column: 7,
        ),
      );
      store.replaceFromEngine('verilator', [v]);

      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final acks = await connectPeer('wavecrux');
      container!
          .read(violationTableStateProvider.notifier)
          .toggleSeverity(Severity.error);

      client!.send(
        RequestHighlight(
          element: ElementId(
            kind: ElementKind.rule,
            path: LintCruxNameResolver.encodeViolationAsRulePath(v)!,
          ),
        ),
      );

      await _pumpUntil(() => acks.isNotEmpty);
      expect(acks.single, isA<RequestHighlightAck>());
      expect((acks.single as RequestHighlightAck).honored, isTrue);

      // The handler applied the filter and the selection to the table.
      final table = container!.read(violationTableStateProvider);
      expect(table.severities, isEmpty);
      expect(container!.read(selectedViolationProvider), v);
    });

    test('a RequestHighlight that names nothing here is acknowledged as not '
        'honoured, with a reason', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final acks = await connectPeer('wavecrux');

      client!.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.rule,
            path: 'verilator/NOSUCH@/proj/cpu.sv:1:1',
          ),
        ),
      );

      await _pumpUntil(() => acks.isNotEmpty);
      final ack = acks.single as RequestHighlightAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, isNotEmpty);
    });

    test('one RequestHighlight is acknowledged exactly once', () async {
      const v = Violation(
        engineId: 'verilator',
        ruleId: 'verilator/UNUSEDSIGNAL',
        severity: Severity.warning,
        message: 'unused',
        location: SourceLocation(file: '/proj/cpu.sv', line: 42, column: 7),
      );
      store.replaceFromEngine('verilator', [v]);
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final acks = await connectPeer('netcrux');

      client!.send(
        RequestHighlight(
          element: ElementId(
            kind: ElementKind.rule,
            path: LintCruxNameResolver.encodeViolationAsRulePath(v)!,
          ),
        ),
      );
      await _pumpUntil(() => acks.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(acks, hasLength(1));
    });

    test('end-to-end RequestOpenSource shells out via the launcher', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final acks = await connectPeer('netcrux');

      client!.send(
        RequestOpenSource(
          filePath: hostAbsolute('/proj/cpu.sv'),
          line: 42,
          column: 7,
        ),
      );

      await _pumpUntil(() => acks.isNotEmpty);
      expect(acks.single, isA<RequestOpenSourceAck>());
      expect((acks.single as RequestOpenSourceAck).honored, isTrue);
      expect(launcher.calls, hasLength(1));
    });

    // CXP §11 through the production wiring: the roots are the directories
    // of the projects the user opened (the handle `WorkspaceRoot` publishes),
    // and an absolute path outside them is refused before any editor runs.
    test('refuses a RequestOpenSource outside the opened projects without '
        'launching an editor', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      final acks = await connectPeer('netcrux');

      final outside = hostAbsolute('/etc/passwd');
      client!.send(RequestOpenSource(filePath: outside, line: 1));

      await _pumpUntil(() => acks.isNotEmpty);
      final ack = acks.single as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('outside the directories'));
      // CXP §9.11: the reason never echoes the sender's path back.
      expect(ack.reason, isNot(contains(outside)));
      expect(launcher.calls, isEmpty);
    });

    // `request_open_artifact` through the production wiring. It is held to
    // the floor, not the opened projects: it exists to open a project
    // LintCrux has never opened, which is what "Open in LintCrux Desktop" in
    // VS Code sends (`kCxpOpenArtifactContainment` says why). So a recorded
    // project outside the opened ones is opened too. The route's refusals,
    // and the `crux.design_id` fallback that keeps the roots, are in
    // `cxp_open_artifact_test.dart`.
    //
    // MUTATION: checking the path with `cxpPathContainmentProvider` in
    // `openRequestedArtifact` instead of `kCxpOpenArtifactContainment` makes the
    // outside project refused, and this goes red.
    test('RequestOpenArtifact opens a recorded project inside the opened '
        'projects, and one outside them under the floor', () async {
      final inside = Directory.systemTemp.createTempSync('lintcrux_cxp_in_');
      final outside = Directory.systemTemp.createTempSync('lintcrux_cxp_out_');
      final records = Directory.systemTemp.createTempSync('lintcrux_cxp_ws_');
      addTearDown(() {
        for (final dir in <Directory>[inside, outside, records]) {
          dir.deleteSync(recursive: true);
        }
      });
      final insideProject = File('${inside.path}/project.lintcrux')
        ..writeAsStringSync('{}');
      final outsideProject = File('${outside.path}/project.lintcrux')
        ..writeAsStringSync('{}');
      final workspace = CxpWorkspaceStore(workspaceDirectory: records.path);
      for (final project in <File>[insideProject, outsideProject]) {
        await workspace.upsertArtifact(
          designId: cxpDesignIdForPath(project.path),
          kind: kCxpLintcruxSourceKind,
          path: project.path,
          producer: 'peer',
        );
      }
      final opened = <String>[];
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
        openedProjects: <String>[insideProject.path],
        workspaceStore: workspace,
        openHandle: CxpProjectOpenHandle()
          ..opener = (path) async {
            opened.add(path);
            return true;
          },
      );
      final acks = await connectPeer('simcrux');

      client!.send(
        RequestOpenArtifact(
          designId: cxpDesignIdForPath(outsideProject.path),
          artifactKind: kCxpLintcruxSourceKind,
        ),
      );
      await _pumpUntil(() => acks.isNotEmpty);
      final outsideAck = acks.single as RequestOpenArtifactAck;
      expect(outsideAck.honored, isTrue, reason: outsideAck.reason);
      expect(opened, <String>[outsideProject.path]);

      client!.send(
        RequestOpenArtifact(
          designId: cxpDesignIdForPath(insideProject.path),
          artifactKind: kCxpLintcruxSourceKind,
        ),
      );
      await _pumpUntil(() => acks.length == 2);
      expect((acks.last as RequestOpenArtifactAck).honored, isTrue);
      expect(opened, <String>[outsideProject.path, insideProject.path]);
    });

    // The `crux.design_id` fallback reads records through this store, so it
    // has to carry the rooted rule. (The server screens the wire with the
    // floor: see `kCxpOpenArtifactContainment`.)
    test('the workspace store carries the rooted containment rule', () {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      expect(
        container!.read(cxpWorkspaceStoreProvider).containment,
        same(container!.read(cxpPathContainmentProvider)),
      );
    });

    test('a NotifySelection from a peer is shown in the event log and does '
        'not draw an error response', () async {
      container = buildContainer(
        manifestDir: tempDir.path,
        store: store,
        launcher: launcher,
      );
      container!.listen(cruxCxpEventLogProvider, (_, _) {});
      final acks = await connectPeer('wavecrux');

      client!.send(
        const NotifySelection(
          elements: <ElementId>[
            ElementId(kind: ElementKind.signal, path: 'top.clk'),
          ],
        ),
      );

      await _pumpUntil(
        () => container!
            .read(cruxCxpEventLogProvider)
            .any((e) => e.kind == CrossProbeEventKind.selectionReceived),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(acks.whereType<ErrorResponse>(), isEmpty);
    });
  });
}
