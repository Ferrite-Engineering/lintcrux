// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:lintcrux/domain/interfaces/violation_store.dart';
import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/sarif/streaming_sarif_reader.dart';

/// Loads a SARIF document into a [ViolationStore] from either a local
/// file (web upload / desktop file picker) or a remote URL (web
/// `?sarif=<url>` query parameter).
///
/// The loader is the single entry point for SARIF ingestion outside
/// the engine-orchestration path. It is used by:
///
///   * The web read-only mode's "Open SARIF" file picker and the
///     auto-fetch of the `?sarif=<url>` query parameter.
///   * The desktop "Import SARIF report" flow (when a user wants to
///     view a CI-generated SARIF without re-running the engines).
///
/// All ingestion goes through [StreamingSarifReader]. The file path
/// ([loadFromXFile]) streams chunks from disk via `XFile.openRead()`, so
/// peak memory stays bounded by one chunk plus the largest single
/// `results[*]` object — independent of document size. (The remote path
/// [loadFromUrl] is bounded only by the response size, since `http.get`
/// buffers the whole body.) Once parsed, each run's violations are
/// wholesale-replaced into the store via [ViolationStore.replaceFromEngine]
/// so the existing reactive UI path renders them without modification.
///
/// Cancellation: callers cancel an in-flight load (e.g. user opened a
/// different file mid-load) by calling [cancelCurrent]. The streaming
/// reader's subscription is torn down, the underlying byte source is
/// released, and the pending `Future` rejects with a "load cancelled"
/// [SarifLoadException].
class SarifFileLoader {
  /// Creates a [SarifFileLoader] using the standard `http.Client` for
  /// remote fetches.
  SarifFileLoader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  StreamSubscription<StreamingSarifEvent>? _active;
  bool _cancelled = false;

  /// Cancels any in-flight load. Safe to call when no load is active.
  Future<void> cancelCurrent() async {
    _cancelled = true;
    final s = _active;
    _active = null;
    if (s != null) {
      await s.cancel();
    }
  }

  /// Reads [file] as a SARIF document and replaces every contained
  /// run's violations into [store]. Returns the parsed [SarifReport]
  /// so callers can surface metadata (engine list, run timestamps).
  ///
  /// Throws [SarifLoadException] on read or parse failure.
  Future<SarifReport> loadFromXFile(
    XFile file, {
    required ViolationStore store,
  }) async {
    try {
      // Stream the file straight into the reader instead of
      // `readAsBytes()` (which held the whole document in memory before a
      // single byte was parsed). On desktop `openRead()` pulls chunks from
      // disk; peak memory stays bounded by one chunk + the largest single
      // results object.
      return await _ingest(
        // `openRead()` is typed `Stream<Uint8List>`; cast to the reader's
        // `Stream<List<int>>` so its `utf8.decoder` transform binds against
        // `List<int>` (a `Stream<Uint8List>` fails that transform's runtime
        // element-type check).
        file.openRead().cast<List<int>>(),
        store: store,
        source: file.name,
      );
    } on SarifLoadException {
      rethrow;
    } catch (e) {
      throw SarifLoadException(
        'failed to read ${file.name}: $e',
        cause: e,
      );
    }
  }

  /// Fetches [url] as a SARIF document via HTTP GET. Used by the web
  /// `?sarif=<url>` auto-load flow.
  ///
  /// The URL must use the `https` (or `http` for local dev) scheme,
  /// point at a server that returns the document with a 2xx status
  /// code, and (when cross-origin to the deployed web app) include
  /// CORS headers permitting the LintCrux origin. CI artifact hosts
  /// that expose pre-signed S3 URLs or `Access-Control-Allow-Origin:
  /// *` work out of the box.
  ///
  /// Throws [SarifLoadException] on network failure, non-2xx status,
  /// or parse failure.
  Future<SarifReport> loadFromUrl(
    Uri url, {
    required ViolationStore store,
  }) async {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw SarifLoadException(
        'URL scheme must be http or https, got "${url.scheme}"',
      );
    }
    try {
      final response = await _client.get(url);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SarifLoadException(
          'remote returned HTTP ${response.statusCode}',
        );
      }
      return await _ingest(
        Stream<List<int>>.value(response.bodyBytes),
        store: store,
        source: url.toString(),
      );
    } on SarifLoadException {
      rethrow;
    } catch (e) {
      throw SarifLoadException(
        'failed to fetch $url: $e',
        cause: e,
      );
    }
  }

  /// Reads a SARIF document directly from a UTF-8 [json] string.
  /// Convenience for tests and for any future copy-paste-from-clipboard
  /// ingestion path.
  Future<SarifReport> loadFromString(
    String json, {
    required ViolationStore store,
    String source = '<string>',
  }) async {
    return _ingest(
      Stream<List<int>>.value(utf8.encode(json)),
      store: store,
      source: source,
    );
  }

  Future<SarifReport> _ingest(
    Stream<List<int>> bytes, {
    required ViolationStore store,
    required String source,
  }) async {
    _cancelled = false;
    const reader = StreamingSarifReader();
    final runs = <_RunAccumulator>[];

    final completer = Completer<SarifReport>();
    // `cancelOnError: true` so a mid-stream parse failure tears the
    // subscription (and the whole `utf8.decoder`/byte-source pipeline
    // underneath it) down immediately. Without it the subscription
    // outlived the completed `Future`: the malformed error was delivered,
    // the `Future` rejected, but the underlying streaming-reader
    // generator was left suspended in its `finally { await iter.cancel() }`
    // with the subscription still open. That dangling subscription
    // re-entered the zone's stream machinery on the *next* load — the
    // source of the "Cannot add event while adding stream" harness abort
    // and the web viewer's forever-spinning malformed load.
    final sub = reader
        .stream(bytes)
        .listen(
          (event) {
            if (_cancelled) return;
            switch (event) {
              case StreamingSarifHeader():
                // Header metadata is informational; the writer side
                // reconstructs schema/version on round-trip.
                break;
              case StreamingSarifRunStart():
                runs.add(_RunAccumulator(event));
              case StreamingSarifViolation():
                if (runs.isEmpty) return;
                runs.last.violations.add(event.violation);
              case StreamingSarifRunEnd():
                if (runs.isEmpty) return;
                final acc = runs.last;
                store.replaceFromEngine(
                  acc.start.engineId,
                  List<Violation>.unmodifiable(acc.violations),
                );
            }
          },
          onError: (Object e, StackTrace st) {
            if (!completer.isCompleted) {
              completer.completeError(
                SarifLoadException(
                  'failed to parse $source: $e',
                  cause: e,
                ),
                st,
              );
            }
          },
          onDone: () {
            if (_cancelled) {
              if (!completer.isCompleted) {
                completer.completeError(
                  const SarifLoadException('load cancelled'),
                );
              }
              return;
            }
            if (!completer.isCompleted) {
              completer.complete(_buildReport(runs));
            }
          },
          cancelOnError: true,
        );
    _active = sub;
    try {
      return await completer.future;
    } finally {
      if (identical(_active, sub)) _active = null;
      // Always tear the subscription down. On the success / done path this
      // is a no-op; on the error path (and any early return) it guarantees
      // the streaming reader and its byte source are released before this
      // method's `Future` settles, so nothing survives into the next load.
      await sub.cancel();
    }
  }

  SarifReport _buildReport(List<_RunAccumulator> runs) {
    return SarifReport(
      runs: <Run>[
        for (final r in runs) r.toRun(),
      ],
    );
  }

  /// Closes the underlying HTTP client. Call from your provider's
  /// dispose handler so the client doesn't leak.
  void dispose() {
    _client.close();
  }
}

class _RunAccumulator {
  _RunAccumulator(this.start);

  final StreamingSarifRunStart start;
  final List<Violation> violations = <Violation>[];

  Run toRun() {
    return Run(
      id: start.runId,
      engineId: start.engineId,
      engineVersion: start.engineVersion,
      startedAt: start.startedAt,
      finishedAt: start.finishedAt,
      violations: List<Violation>.unmodifiable(violations),
      success: start.success,
      exitCode: start.exitCode,
      errorMessage: start.errorMessage,
    );
  }
}

/// Thrown by [SarifFileLoader] when ingestion fails. Wraps the raw
/// exception so the UI can surface a single user-facing message.
class SarifLoadException implements Exception {
  /// Creates a [SarifLoadException].
  const SarifLoadException(this.message, {this.cause});

  /// English-only failure description suitable for snackbar text.
  final String message;

  /// Underlying error (network failure, JSON parse error). Preserved
  /// for diagnostic logs.
  final Object? cause;

  @override
  String toString() => 'SarifLoadException: $message';
}
