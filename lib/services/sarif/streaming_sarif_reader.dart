// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/sarif/sarif_reader.dart';

/// Reads a SARIF 2.1.0 document as a token stream rather than loading
/// the whole document into memory at once.
///
/// Each `runs[*].results[*]` object is extracted from the input as a
/// self-contained JSON blob, decoded to a `Map<String, dynamic>`, and
/// promoted to a [Violation] via the same field-mapping logic as
/// [SarifReader.parseResult]. Once a result has been emitted, its
/// backing JSON substring is released for garbage collection — so a
/// SARIF document with 100,000 results does not need 100,000-result-
/// worth of decoded `Map` instances resident at once.
///
/// Bounded-memory contract: at any point in the stream lifecycle the
/// reader holds at most a single in-flight buffer of unconsumed input
/// text (~chunk size, typically 64 KiB) plus the structural state of
/// the surrounding run (engine id, version, invocation metadata). The
/// individual extracted result objects are materialized one at a time
/// and discarded by the consumer between events. Compare to the
/// non-streaming [SarifReader.read], which constructs a single root
/// `Map<String, dynamic>` for the entire document — fine for small
/// reports, prohibitive at the 100k-violation tier.
///
/// The streaming reader is intentionally a drop-in replacement for the
/// existing reader for the common case: callers that want a
/// [SarifReport] at the end can use [readAll] and get the same typed
/// model. Callers that want per-violation streaming (the web read-only
/// dashboard, the round-trip property tests) consume [stream]
/// directly.
///
/// Cancellation: the [Stream] returned by [stream] honors subscription
/// cancellation — closing the subscription cuts off the underlying
/// byte source, releases the in-flight buffer, and never emits another
/// event. The desktop "user opened a different file" flow relies on
/// this: closing the previous file's stream stops reading instantly,
/// no matter how large the file was.
///
/// What this reader does *not* do (matches [SarifReader] semantics so
/// the swap is invisible to callers):
///   - JSON-schema validation beyond what the parser naturally
///     requires (top-level object, `runs` is an array, each
///     `results[*]` is an object).
///   - Lossless preservation of whitespace or key ordering inside the
///     original document. Round-trip via the existing writer is
///     structurally equivalent, not byte-equivalent.
///
/// Implementation note: SARIF documents are deeply nested JSON
/// objects. A full streaming JSON parser is overkill given the
/// document shape is fixed and only one path actually grows unbounded
/// (`runs[].results[]`). The reader uses a structural scanner that
/// locates `results` arrays inside each `runs[]` element, extracts
/// complete object substrings from inside them, and decodes each
/// substring with the standard `jsonDecode`. The remaining metadata
/// (`version`, `$schema`, `tool.driver.*`, `invocations[]`) is small
/// per-run and decoded with `jsonDecode` over its own bounded
/// substring.
class StreamingSarifReader {
  /// Creates a streaming reader. The reader is stateless across calls.
  const StreamingSarifReader();

  /// Reads the entire document into a [SarifReport]. Convenience for
  /// callers that don't need per-violation streaming. The streaming
  /// implementation still applies — peak memory is bounded by the
  /// chunk size plus the accumulating run/violation lists themselves.
  ///
  /// Throws [SarifReadException] on malformed input.
  Future<SarifReport> readAll(Stream<List<int>> bytes) async {
    final report = _ReportBuilder();
    await for (final event in stream(bytes)) {
      switch (event) {
        case StreamingSarifHeader():
          report
            ..version = event.version
            ..schema = event.schema;
        case StreamingSarifRunStart():
          report.startRun(event);
        case StreamingSarifViolation():
          report.addViolation(event.violation);
        case StreamingSarifRunEnd():
          report.endRun();
      }
    }
    return report.build();
  }

  /// Stream of [StreamingSarifEvent]s describing the document. The
  /// emission order is:
  ///
  ///   1. Exactly one [StreamingSarifHeader] event with the top-level
  ///      `version` / `$schema` strings.
  ///   2. For each `runs[]` entry, one [StreamingSarifRunStart],
  ///      zero-or-more [StreamingSarifViolation], and one
  ///      [StreamingSarifRunEnd] in that order.
  ///
  /// The stream closes when the document is fully consumed.
  /// Subscription cancellation aborts the read promptly without
  /// throwing.
  Stream<StreamingSarifEvent> stream(Stream<List<int>> bytes) {
    final scanner = _SarifScanner();
    return scanner.scan(bytes);
  }
}

/// Base class for events emitted by [StreamingSarifReader.stream].
sealed class StreamingSarifEvent {
  const StreamingSarifEvent();
}

/// The top-level SARIF document header (`version`, `$schema`). Emitted
/// exactly once, before any [StreamingSarifRunStart].
class StreamingSarifHeader extends StreamingSarifEvent {
  /// Creates a header event.
  const StreamingSarifHeader({required this.version, required this.schema});

  /// `version` field of the SARIF document.
  final String version;

  /// `$schema` field of the SARIF document.
  final String schema;
}

/// Marks the start of a `runs[*]` entry. Emitted once per run, before
/// any [StreamingSarifViolation] for that run.
class StreamingSarifRunStart extends StreamingSarifEvent {
  /// Creates a run-start event.
  const StreamingSarifRunStart({
    required this.engineId,
    required this.engineVersion,
    required this.startedAt,
    required this.finishedAt,
    required this.success,
    required this.runIndex,
    required this.runId,
    this.exitCode,
    this.errorMessage,
  });

  /// `tool.driver.name`, lowercased.
  final String engineId;

  /// `tool.driver.version`.
  final String engineVersion;

  /// First invocation's `startTimeUtc`.
  final DateTime startedAt;

  /// First invocation's `endTimeUtc`.
  final DateTime finishedAt;

  /// `executionSuccessful`.
  final bool success;

  /// `exitCode`, if present.
  final int? exitCode;

  /// `exitCodeDescription`, if present.
  final String? errorMessage;

  /// Index of this run in the document's `runs[]` array.
  final int runIndex;

  /// `automationDetails.id` if present, else `run-<engineId>-<runIndex>`.
  final String runId;
}

/// One `results[*]` entry, already promoted to a [Violation].
class StreamingSarifViolation extends StreamingSarifEvent {
  /// Creates a violation event.
  const StreamingSarifViolation({
    required this.runIndex,
    required this.violation,
  });

  /// Which run this violation belongs to.
  final int runIndex;

  /// The decoded violation.
  final Violation violation;
}

/// Marks the end of a `runs[*]` entry. Always paired with the
/// corresponding [StreamingSarifRunStart].
class StreamingSarifRunEnd extends StreamingSarifEvent {
  /// Creates a run-end event.
  const StreamingSarifRunEnd({required this.runIndex});

  /// Which run just ended.
  final int runIndex;
}

// ─── Internal builders & scanner ──────────────────────────────────────

/// Accumulator that turns a stream of events back into a [SarifReport]
/// for callers that ultimately want the full typed model.
class _ReportBuilder {
  String version = '2.1.0';
  String schema = 'https://json.schemastore.org/sarif-2.1.0.json';
  final List<Run> _runs = <Run>[];
  StreamingSarifRunStart? _current;
  final List<Violation> _violations = <Violation>[];

  void startRun(StreamingSarifRunStart e) {
    _current = e;
    _violations.clear();
  }

  void addViolation(Violation v) {
    _violations.add(v);
  }

  void endRun() {
    final c = _current;
    if (c == null) return;
    _runs.add(
      Run(
        id: c.runId,
        engineId: c.engineId,
        engineVersion: c.engineVersion,
        startedAt: c.startedAt,
        finishedAt: c.finishedAt,
        violations: List<Violation>.unmodifiable(_violations),
        success: c.success,
        exitCode: c.exitCode,
        errorMessage: c.errorMessage,
      ),
    );
    _current = null;
    _violations.clear();
  }

  SarifReport build() {
    // Defensive close — if the stream terminated mid-run we still want
    // a usable report rather than silently dropping the last run.
    if (_current != null) endRun();
    return SarifReport(version: version, schema: schema, runs: _runs);
  }
}

/// Structural scanner that walks the document character-by-character
/// to identify the boundaries of `runs[]` and `results[]` entries and
/// hands off each entry to the field-mapper as a self-contained JSON
/// substring.
///
/// The scanner buffers input in chunks of the underlying byte source's
/// natural size (typically 64 KiB on file reads) and discards any text
/// that lies before the current cursor whenever a refill happens — so
/// memory consumption stays bounded regardless of document size.
class _SarifScanner {
  String _text = '';
  int _cursor = 0;

  Stream<StreamingSarifEvent> scan(Stream<List<int>> bytes) async* {
    final decoded = bytes.transform<String>(utf8.decoder);
    final iter = StreamIterator<String>(decoded);
    try {
      // Phase A: accumulate enough text to locate the top-level header
      // fields (version, $schema) and the start of the `runs` array.
      await _appendUntilContains(iter, '"runs"');

      yield _parseHeader();

      // Phase B: locate the `runs` array opening bracket, then walk
      // it element-by-element, yielding events per run.
      await _advanceUntil(iter, '[');
      _expect('[');
      var runIndex = 0;
      while (true) {
        await _skipWhitespace(iter);
        final p = _peekChar();
        if (p == ']') {
          _consumeChar(); // close runs
          break;
        }
        if (p == ',') {
          _consumeChar();
          continue;
        }
        yield* _scanOneRun(iter, runIndex);
        runIndex++;
      }
    } finally {
      await iter.cancel();
    }
  }

  /// Scans one element of the `runs[]` array and yields its events.
  Stream<StreamingSarifEvent> _scanOneRun(
    StreamIterator<String> iter,
    int runIndex,
  ) async* {
    // The run starts at `{`. We need to extract its header fields
    // (engine id, version, invocations) without buffering the full
    // run, then yield each `results[]` entry as we encounter it.
    await _advanceUntil(iter, '{');
    _expect('{');

    // Track the depth into the run so we know when we exit it.
    var depth = 1;
    // Snapshot of the metadata fields we want to yield as the
    // run-start event. We keep accumulating until we have all of them
    // OR we hit the `results` key (whichever comes first).
    final metadata = <String, dynamic>{};
    StreamingSarifRunStart? runStart;
    var sawResults = false;

    while (depth > 0) {
      await _skipWhitespace(iter);
      final c = _peekChar();
      if (c == '}') {
        _consumeChar();
        depth--;
        continue;
      }
      if (c == ',') {
        _consumeChar();
        continue;
      }

      // Parse one "key": value pair.
      final key = await _readJsonString(iter);
      await _skipWhitespace(iter);
      _expect(':');
      await _skipWhitespace(iter);

      if (key == 'results') {
        // Yield run-start before any violation. If metadata is
        // incomplete (rare) we still emit a sensible event.
        runStart ??= _buildRunStart(metadata, runIndex);
        yield runStart;
        sawResults = true;

        // Walk the results array, yielding one violation per entry.
        await _ensureCurrentChunk(iter);
        _expect('[');
        while (true) {
          await _skipWhitespace(iter);
          final p = _peekChar();
          if (p == ']') {
            _consumeChar();
            break;
          }
          if (p == ',') {
            _consumeChar();
            continue;
          }
          final objText = await _readJsonValue(iter);
          final Object? decoded;
          try {
            decoded = jsonDecode(objText);
          } on FormatException catch (e) {
            // Wrap raw JSON errors so malformed input surfaces as the
            // reader's typed rejection instead of a
            // leaked FormatException the ingest layer can't classify.
            throw SarifReadException(
              'malformed `results[*]` object: ${e.message}',
            );
          }
          if (decoded is! Map<String, dynamic>) {
            throw const SarifReadException(
              '`results[*]` must be a JSON object',
            );
          }
          final violation = SarifReader.parseResult(
            decoded,
            runStart.engineId,
            pathHint: 'runs[$runIndex].results[*]',
          );
          yield StreamingSarifViolation(
            runIndex: runIndex,
            violation: violation,
          );
        }
        continue;
      }

      // Non-results field. Read the JSON value into a string, decode
      // it, and stash under the key.
      final valueText = await _readJsonValue(iter);
      metadata[key] = jsonDecode(valueText);
    }

    // If the run had no `results` key, we still need to emit a
    // run-start before run-end.
    if (!sawResults) {
      runStart ??= _buildRunStart(metadata, runIndex);
      yield runStart;
    }
    yield StreamingSarifRunEnd(runIndex: runIndex);
  }

  StreamingSarifRunStart _buildRunStart(
    Map<String, dynamic> metadata,
    int runIndex,
  ) {
    final tool = metadata['tool'];
    var engineId = 'unknown';
    var engineVersion = '';
    if (tool is Map<String, dynamic>) {
      final driver = tool['driver'];
      if (driver is Map<String, dynamic>) {
        engineId = (driver['name'] as String?)?.toLowerCase() ?? 'unknown';
        engineVersion = (driver['version'] as String?) ?? '';
      }
    }

    var startedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    var finishedAt = startedAt;
    int? exitCode;
    var success = true;
    String? errorMessage;
    final invocations = metadata['invocations'];
    if (invocations is List && invocations.isNotEmpty) {
      final first = invocations.first;
      if (first is Map<String, dynamic>) {
        final st = first['startTimeUtc'];
        if (st is String) {
          startedAt = DateTime.tryParse(st)?.toUtc() ?? startedAt;
        }
        final et = first['endTimeUtc'];
        if (et is String) {
          finishedAt = DateTime.tryParse(et)?.toUtc() ?? startedAt;
        } else {
          finishedAt = startedAt;
        }
        final ex = first['exitCode'];
        if (ex is int) exitCode = ex;
        final ok = first['executionSuccessful'];
        if (ok is bool) success = ok;
        final err = first['exitCodeDescription'];
        if (err is String) errorMessage = err;
      }
    }

    final details = metadata['automationDetails'];
    var runId = 'run-$engineId-$runIndex';
    if (details is Map<String, dynamic>) {
      final id = details['id'];
      if (id is String && id.isNotEmpty) runId = id;
    }

    return StreamingSarifRunStart(
      runIndex: runIndex,
      engineId: engineId,
      engineVersion: engineVersion,
      startedAt: startedAt,
      finishedAt: finishedAt,
      success: success,
      exitCode: exitCode,
      errorMessage: errorMessage,
      runId: runId,
    );
  }

  // ─── Header parsing ─────────────────────────────────────────────────

  StreamingSarifHeader _parseHeader() {
    // We've buffered enough text to contain `"runs"`. Extract the
    // top-level `version` and `$schema` fields using regex against the
    // buffered prefix — this is allowed because both fields appear
    // outside `runs[]` and the SARIF schema places them at depth 1.
    final versionMatch = RegExp(r'"version"\s*:\s*"([^"]*)"').firstMatch(_text);
    final schemaMatch = RegExp(r'"\$schema"\s*:\s*"([^"]*)"').firstMatch(_text);
    final version = versionMatch?.group(1) ?? '2.1.0';
    final schema =
        schemaMatch?.group(1) ??
        'https://json.schemastore.org/sarif-2.1.0.json';
    return StreamingSarifHeader(version: version, schema: schema);
  }

  // ─── Low-level helpers ──────────────────────────────────────────────

  Future<void> _appendUntilContains(
    StreamIterator<String> iter,
    String needle,
  ) async {
    if (_text.indexOf(needle, _cursor) >= 0) return;
    // Accumulate into a StringBuffer and search only the boundary window —
    // the trailing `needle.length - 1` chars of what we've seen plus each new
    // chunk — instead of re-scanning (and, via `_swapBuffer`, re-copying) the
    // whole growing prefix on every chunk. The old
    // `_text = _text + chunk` per chunk was O(prefix²) once the region before
    // `needle` spanned many chunks (a large top-level object preceding
    // `runs`, exposed once the loader streams the file in chunks).
    final overlap = needle.length - 1;
    String lastChars(String s) {
      if (overlap <= 0) return '';
      return s.length <= overlap ? s : s.substring(s.length - overlap);
    }

    final buf = StringBuffer(_text);
    var tail = lastChars(_text);
    while (true) {
      if (!await iter.moveNext()) {
        throw SarifReadException('unexpected end of input before `$needle`');
      }
      final chunk = iter.current;
      buf.write(chunk);
      final window = tail.isEmpty ? chunk : '$tail$chunk';
      if (window.contains(needle)) break;
      tail = lastChars(window);
    }
    _text = buf.toString();
  }

  Future<void> _advanceUntil(
    StreamIterator<String> iter,
    String openChar,
  ) async {
    while (true) {
      if (_cursor >= _text.length) {
        if (!await _refill(iter)) {
          throw SarifReadException(
            'unexpected end of input before `$openChar`',
          );
        }
        continue;
      }
      if (_text[_cursor] == openChar) return;
      _cursor++;
    }
  }

  void _expect(String ch) {
    if (_cursor >= _text.length || _text[_cursor] != ch) {
      throw SarifReadException(
        'expected `$ch` at cursor $_cursor, '
        "got '${_cursor < _text.length ? _text[_cursor] : '<eof>'}'",
      );
    }
    _cursor++;
  }

  String _peekChar() {
    if (_cursor >= _text.length) return ' ';
    return _text[_cursor];
  }

  void _consumeChar() {
    if (_cursor < _text.length) _cursor++;
  }

  Future<void> _skipWhitespace(StreamIterator<String> iter) async {
    while (true) {
      while (_cursor < _text.length) {
        final c = _text.codeUnitAt(_cursor);
        if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
          _cursor++;
        } else {
          return;
        }
      }
      if (!await _refill(iter)) return;
    }
  }

  Future<void> _ensureCurrentChunk(StreamIterator<String> iter) async {
    if (_cursor < _text.length) return;
    await _refill(iter);
  }

  /// Pulls more text from [iter] into the buffer, discarding text
  /// before the cursor so memory stays bounded.
  Future<bool> _refill(StreamIterator<String> iter) async {
    if (!await iter.moveNext()) return false;
    _swapBuffer(iter.current);
    return true;
  }

  void _swapBuffer(String more) {
    if (_cursor == 0) {
      _text = _text + more;
    } else {
      _text = _text.substring(_cursor) + more;
      _cursor = 0;
    }
  }

  /// Reads a JSON string starting at the current cursor (which must
  /// point at `"`). Returns the decoded string value. Handles escapes.
  Future<String> _readJsonString(StreamIterator<String> iter) async {
    await _ensureCurrentChunk(iter);
    if (_peekChar() != '"') {
      throw SarifReadException(
        "expected '\"' at start of JSON string, got '${_peekChar()}'",
      );
    }
    _consumeChar();
    final out = StringBuffer();
    while (true) {
      if (_cursor >= _text.length) {
        if (!await _refill(iter)) {
          throw const SarifReadException(
            'unexpected end of input inside JSON string',
          );
        }
      }
      final c = _text[_cursor];
      _cursor++;
      if (c == '"') break;
      if (c == r'\') {
        if (_cursor >= _text.length) {
          if (!await _refill(iter)) {
            throw const SarifReadException(
              'unexpected end of input inside escape',
            );
          }
        }
        final esc = _text[_cursor];
        _cursor++;
        switch (esc) {
          case '"':
            out.write('"');
          case r'\':
            out.write(r'\');
          case '/':
            out.write('/');
          case 'b':
            out.write('\b');
          case 'f':
            out.write('\f');
          case 'n':
            out.write('\n');
          case 'r':
            out.write('\r');
          case 't':
            out.write('\t');
          case 'u':
            // 4 hex digits.
            final hex = StringBuffer();
            for (var i = 0; i < 4; i++) {
              if (_cursor >= _text.length) {
                if (!await _refill(iter)) {
                  throw const SarifReadException(
                    'unexpected end of input inside unicode escape',
                  );
                }
              }
              hex.write(_text[_cursor]);
              _cursor++;
            }
            out.writeCharCode(int.parse(hex.toString(), radix: 16));
          default:
            out.write(esc);
        }
      } else {
        out.write(c);
      }
    }
    return out.toString();
  }

  /// Reads a complete JSON value (object, array, string, number,
  /// `true`/`false`/`null`) starting at the cursor and returns its
  /// raw textual form. The cursor lands one past the value's last
  /// character.
  Future<String> _readJsonValue(StreamIterator<String> iter) async {
    await _ensureCurrentChunk(iter);
    final first = _peekChar();
    if (first == '{' || first == '[') {
      return await _readBalanced(iter, first);
    }
    if (first == '"') {
      return await _readStringRaw(iter);
    }
    // Number / true / false / null — read until a structural char.
    final out = StringBuffer();
    while (true) {
      if (_cursor >= _text.length) {
        if (!await _refill(iter)) break;
      }
      final c = _text[_cursor];
      if (c == ',' ||
          c == ']' ||
          c == '}' ||
          c == ' ' ||
          c == '\t' ||
          c == '\n' ||
          c == '\r') {
        break;
      }
      out.write(c);
      _cursor++;
    }
    return out.toString();
  }

  Future<String> _readBalanced(
    StreamIterator<String> iter,
    String open,
  ) async {
    final close = open == '{' ? '}' : ']';
    final out = StringBuffer();
    var depth = 0;
    var inString = false;
    var escape = false;
    while (true) {
      if (_cursor >= _text.length) {
        if (!await _refill(iter)) {
          throw const SarifReadException(
            'unexpected end of input inside JSON value',
          );
        }
      }
      final c = _text[_cursor];
      out.write(c);
      _cursor++;
      if (inString) {
        if (escape) {
          escape = false;
        } else if (c == r'\') {
          escape = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return out.toString();
      }
    }
  }

  /// Reads a JSON string and returns its raw textual form (including
  /// the surrounding quotes). The cursor advances past the closing
  /// quote.
  Future<String> _readStringRaw(StreamIterator<String> iter) async {
    final out = StringBuffer()..write('"');
    _consumeChar();
    var escape = false;
    while (true) {
      if (_cursor >= _text.length) {
        if (!await _refill(iter)) {
          throw const SarifReadException(
            'unexpected end of input inside JSON string',
          );
        }
      }
      final c = _text[_cursor];
      out.write(c);
      _cursor++;
      if (escape) {
        escape = false;
        continue;
      }
      if (c == r'\') {
        escape = true;
        continue;
      }
      if (c == '"') return out.toString();
    }
  }
}
