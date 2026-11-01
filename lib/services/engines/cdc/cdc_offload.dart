// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Runs a computation off the calling isolate, where the platform has
/// isolates, so the UI isolate keeps drawing frames while it works.
///
/// The conditional export keeps `dart:isolate` out of the web build: where
/// `dart:io` is absent the stub runs the computation in place, which is what
/// the browser build did before.
library;

export 'cdc_offload_stub.dart' if (dart.library.io) 'cdc_offload_io.dart';
export 'cdc_offload_task.dart';
