// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Logger name used for trend-ingestion diagnostics.
///
/// The Pro SQLite trend store logs under the same name as the open-core
/// ingestion listener, so a log reader sees the whole ingest path on one
/// channel.
///
/// This constant lives in its own Flutter-free library rather than
/// alongside `trendIngestDiagnosticsSinkProvider`, because the Pro
/// trend store is reachable from a headless binary. Importing the
/// provider file — even with a `show kTrendIngestLogName` — pulls
/// `flutter_riverpod`, and therefore `dart:ui`, into the dependency
/// graph, which makes AOT compilation of a CLI entrypoint fail with an
/// opaque kernel crash (`type 'InvalidType' is not a subtype of type
/// 'FunctionType'`). Splitting the constant out is the whole fix.
library;

/// The log name for the trend ingestion path.
const String kTrendIngestLogName = 'lintcrux.trends';
