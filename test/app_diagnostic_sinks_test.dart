// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart';
import 'package:lintcrux/services/logging/severe_log_stderr_sink.dart';
import 'package:logging/logging.dart';

class _Capture implements StreamConsumer<List<int>> {
  final buffer = StringBuffer();

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach((bytes) => buffer.write(utf8.decode(bytes)));

  @override
  Future<void> close() async {}
}

/// A process stdio stream, installed through [IOOverrides], whose bytes land
/// in a [_Capture].
class _StdioStandIn implements Stdout {
  _StdioStandIn(_Capture capture) : _sink = IOSink(capture);

  final IOSink _sink;

  @override
  void write(Object? object) => _sink.write(object);

  @override
  void writeln([Object? object = '']) => _sink.writeln(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);

  @override
  void add(List<int> data) => _sink.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);

  @override
  Future<void> flush() => _sink.flush();

  @override
  Future<void> close() => _sink.close();

  @override
  Future<void> get done => _sink.done;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The uncaught-error path, end to end: what `bootstrap()` attaches must carry
/// a framework error and an uncaught async error to stderr, and put nothing on
/// stdout.
///
/// Until the stderr sink existed, both reached only the issue reporter's
/// in-memory buffer, so on a user's machine they were gone with the session.
/// stdout is off limits: the desktop executable's `--help` and `--version`
/// write there for scripts to read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uncaught framework and async errors reach stderr, and nothing '
      'reaches stdout', () async {
    // The handlers `captureFlutterErrors` chains to. The test binding's own
    // would fail this test for the errors it reports on purpose.
    final previousFlutter = FlutterError.onError;
    final previousDispatcher = PlatformDispatcher.instance.onError;
    FlutterError.onError = (_) {};
    PlatformDispatcher.instance.onError = (_, _) => true;
    addTearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousDispatcher;
    });
    addTearDown(SevereLogStderrSink.instance.detach);

    final out = _Capture();
    final err = _Capture();
    final printed = <String>[];
    final stdoutStandIn = _StdioStandIn(out);
    final stderrStandIn = _StdioStandIn(err);

    await IOOverrides.runZoned(
      () => runZoned(
        () async {
          // No override: the process-wide sink, resolving the process's
          // stderr exactly as `bootstrap()` does.
          attachDiagnosticSinks();
          FlutterError.onError!(
            FlutterErrorDetails(exception: StateError('frame failed')),
          );
          PlatformDispatcher.instance.onError!(
            StateError('async failed'),
            StackTrace.current,
          );
          Logger('lintcrux.test')
            ..warning('below the threshold')
            ..severe('logged directly');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      ),
      stdout: () => stdoutStandIn,
      stderr: () => stderrStandIn,
    );

    final text = err.buffer.toString();
    expect(text, contains('SEVERE flutter: Bad state: frame failed'));
    expect(text, contains('SEVERE flutter: Uncaught: Bad state: async failed'));
    expect(text, contains('SEVERE lintcrux.test: logged directly'));
    expect(text, isNot(contains('below the threshold')));
    expect(out.buffer.toString(), isEmpty, reason: 'nothing on stdout');
    expect(printed, isEmpty, reason: 'print() reaches stdout too');
  });
}
