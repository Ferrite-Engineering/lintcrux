// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:lintcrux/services/engines/cdc/cdc_offload_task.dart';

/// Runs [computation] on the calling isolate, after the current event.
///
/// The platform this file is built for has no isolates to hand it to.
OffloadTask<R> runOffloaded<R>(R Function() computation) =>
    _InProcessTask<R>(computation);

final class _InProcessTask<R> implements OffloadTask<R> {
  _InProcessTask(R Function() computation) {
    unawaited(
      Future<void>(() {
        if (_done.isCompleted) return;
        try {
          _done.complete(computation());
        } on Object catch (e, st) {
          _done.completeError(e, st);
        }
      }),
    );
  }

  final Completer<R> _done = Completer<R>();

  @override
  Future<R> get result => _done.future;

  @override
  bool get ranInProcess => true;

  @override
  void cancel() {
    if (!_done.isCompleted) _done.completeError(const OffloadCancelled());
  }
}
