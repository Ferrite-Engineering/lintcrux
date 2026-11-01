// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:isolate';

import 'package:lintcrux/services/engines/cdc/cdc_offload_task.dart';

/// Runs [computation] on a new isolate and hands back its result.
///
/// [computation] and everything it captures must be sendable to an isolate:
/// plain data, no ports, no objects that hold native resources. A computation
/// that is not sendable is not an error: it runs on the calling isolate
/// instead (see [OffloadTask.ranInProcess]), so a caller that is handed an
/// object it cannot control still gets its answer, only without the isolate.
///
/// The result travels back with `Isolate.exit`, which transfers the object
/// graph rather than copying it.
OffloadTask<R> runOffloaded<R>(R Function() computation) =>
    _IsolateTask<R>(computation);

const int _ok = 0;
const int _failed = 1;

final class _Job {
  const _Job(this.computation, this.reply);

  final Object? Function() computation;
  final SendPort reply;
}

/// The isolate's entry point.
void _entry(_Job job) {
  List<Object?> message;
  try {
    message = <Object?>[_ok, job.computation()];
  } on Object catch (e, st) {
    message = <Object?>[_failed, e, st.toString()];
  }
  try {
    Isolate.exit(job.reply, message);
  } on Object catch (e, st) {
    // The value, or the error, could not be sent. Say so in words.
    Isolate.exit(job.reply, <Object?>[
      _failed,
      RemoteError('$e', st.toString()),
      st.toString(),
    ]);
  }
}

final class _IsolateTask<R> implements OffloadTask<R> {
  _IsolateTask(R Function() computation) : _fallback = computation {
    _port = RawReceivePort(_onMessage);
    unawaited(
      Isolate.spawn<_Job>(
        _entry,
        _Job(computation, _port.sendPort),
        onExit: _port.sendPort,
        debugName: 'lintcrux-cdc-analysis',
      ).then(
        (isolate) {
          _isolate = isolate;
          if (_done.isCompleted) isolate.kill(priority: Isolate.immediate);
        },
        onError: (Object _) => _runInProcess(),
      ),
    );
  }

  final R Function() _fallback;
  final Completer<R> _done = Completer<R>();
  late final RawReceivePort _port;
  Isolate? _isolate;
  bool _inProcess = false;

  @override
  Future<R> get result => _done.future;

  @override
  bool get ranInProcess => _inProcess;

  void _onMessage(Object? message) {
    _port.close();
    if (_done.isCompleted) return;
    switch (message) {
      case [final int tag, final Object? value] when tag == _ok:
        _done.complete(value as R);
      case [final int tag, final Object? error, final String stack]
          when tag == _failed:
        _done.completeError(
          error ?? 'unknown error',
          StackTrace.fromString(stack),
        );
      default:
        // The isolate ended without answering.
        _done.completeError(
          StateError('The analysis isolate ended without a result.'),
        );
    }
  }

  /// The computation could not be sent: run it here.
  void _runInProcess() {
    _port.close();
    if (_done.isCompleted) return;
    _inProcess = true;
    unawaited(
      Future<void>(() {
        if (_done.isCompleted) return;
        try {
          _done.complete(_fallback());
        } on Object catch (e, st) {
          _done.completeError(e, st);
        }
      }),
    );
  }

  @override
  void cancel() {
    if (_done.isCompleted) return;
    _port.close();
    _isolate?.kill(priority: Isolate.immediate);
    _done.completeError(const OffloadCancelled());
  }
}
