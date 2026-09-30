// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:lintcrux/domain/models/violation.dart';

/// Maps LintCrux's natural element references into and out of canonical
/// CXP [ElementId] form so the receive-side handlers can act on inbound
/// `RequestHighlight` and `RequestOpenSource` messages without leaking
/// engine-specific shape across the wire.
///
/// LintCrux participates as a *receive-focused* CXP peer. The element kinds
/// this resolver handles fall into two groups:
///
/// 1. **Owned by LintCrux.** The product *originates* references for
///    these kinds and can resolve them back to local objects.
///    - [ElementKind.rule]: a single violation site, encoded as
///      `"<engineId>/<ruleId>@<file>:<line>[:<column>]"`. The encoding
///      matches `ViolationTableState.idOf` so the receive-side filter
///      handler can compute the same key from the local violation set
///      and find the unique matching row.
///    - [ElementKind.source]: a free-form source-code location encoded
///      as `"<file>:<line>[:<column>]"`. LintCrux's source preview pane
///      and the violation table both surface source locations, so this
///      is a natural local concept.
///
/// 2. **Recognised but not owned.** LintCrux receives these from peers
///    (WaveCrux, NetCrux, SimCrux) and routes them onto the violation
///    table's filter dimensions. The resolver stores them as canonical
///    paths and returns the path verbatim from [toLocal] because
///    LintCrux does not keep a private name space for signals or
///    modules — its handlers consume the canonical string directly to
///    filter the violation list.
///    - [ElementKind.signal]: a hierarchical signal path, e.g.
///      `"top.cpu.alu.sum[31:0]"`. WaveCrux's resolver is the
///      authoritative producer; LintCrux uses the path verbatim to
///      filter the violation table by signal context (best-effort
///      substring match against violation messages and rule context).
///    - [ElementKind.instance]: a hierarchical module / instance path
///      (`"top.cpu.alu"`). Used to filter the violation table to
///      entries whose source file or message context name the module.
///
/// Every other [ElementKind] returns `null` from both directions —
/// LintCrux cannot represent waveform markers, breakpoints, tests, or
/// netlist objects in its own surface. Inbound requests targeting those
/// kinds get a `RequestHighlightAck(honored: false, reason: "...")`
/// from the receive-side handler.
///
/// [ElementKind] is an *open* wire type, so a peer may name a kind this
/// build has never heard of (`kind.known == null`). That case is treated
/// identically to a recognised-but-unowned kind: declined with `null`,
/// acked as not honored, never thrown. Forward compatibility is the
/// whole point of the type being open — a newer peer must not be able to
/// crash an older LintCrux by naming a kind it postdates.
///
/// The resolver is stateless and thread-safe; one instance is shared
/// across the inbound dispatch loop and any outbound emit paths.
class LintCruxNameResolver implements NameResolver {
  /// Const constructor — there is no state.
  const LintCruxNameResolver();

  @override
  ElementId? toCanonical({
    required ElementKind kind,
    required String local,
  }) {
    if (local.isEmpty) return null;
    switch (kind.known) {
      case KnownElementKind.rule:
      case KnownElementKind.source:
      case KnownElementKind.signal:
      case KnownElementKind.instance:
        return ElementId(kind: kind, path: local);
      case KnownElementKind.scope:
      case KnownElementKind.net:
      case KnownElementKind.port:
      case KnownElementKind.marker:
      case KnownElementKind.test:
      case KnownElementKind.breakpoint:
      // A kind defined by a protocol revision or a peer product newer
      // than this build. LintCrux cannot represent it locally, which is
      // exactly the answer `null` already gives for the known kinds it
      // does not own — so an unrecognised kind is declined, not fatal.
      case null:
        return null;
    }
  }

  @override
  String? toLocal(ElementId id) {
    if (id.path.isEmpty) return null;
    switch (id.kind.known) {
      case KnownElementKind.rule:
      case KnownElementKind.source:
      case KnownElementKind.signal:
      case KnownElementKind.instance:
        return id.path;
      case KnownElementKind.scope:
      case KnownElementKind.net:
      case KnownElementKind.port:
      case KnownElementKind.marker:
      case KnownElementKind.test:
      case KnownElementKind.breakpoint:
      // Unrecognised kind — see [toCanonical]. Declined, not fatal.
      case null:
        return null;
    }
  }

  /// Encodes a [Violation] into the canonical [ElementKind.rule] form
  /// the resolver round-trips.
  ///
  /// Matches the format produced by `ViolationTableState.idOf` —
  /// `"<engineId>/<ruleId>@<file>:<line>:<column>"`. Note that
  /// `Violation.ruleId` is already `"<engineId>/<localRuleId>"` per the
  /// open-core domain contract, so the canonical path round-trips through
  /// JSON without losing the engine namespace.
  ///
  /// Returns `null` when the violation lacks a usable source location
  /// (line `< 1`). All canonical paths must be stable across runs, so
  /// the encoding cannot fall back to a positional surrogate.
  static String? encodeViolationAsRulePath(Violation v) {
    if (v.location.line < 1) return null;
    return '${v.ruleId}@${v.location.file}'
        ':${v.location.line}:${v.location.column}';
  }

  /// Encodes a `(file, line, column?)` triple into the canonical
  /// [ElementKind.source] form.
  ///
  /// Mirrors the file/line/column substitution that
  /// `EditorCommand.render` consumes, so a `RequestOpenSource` handler
  /// can hand the parsed triple directly to the existing
  /// click-to-source service without any conversion logic in between.
  ///
  /// Returns `null` for `line < 1`.
  static String? encodeSourcePath({
    required String file,
    required int line,
    int? column,
  }) {
    if (line < 1) return null;
    if (column == null) return '$file:$line';
    return '$file:$line:$column';
  }

  /// Parses a canonical [ElementKind.rule] path into its
  /// `(ruleId, file, line, column)` parts.
  ///
  /// Returns `null` for malformed input — missing `@`, missing
  /// `file:line:column`, non-positive line/column, or empty `ruleId`.
  /// The encoding produced by [encodeViolationAsRulePath] always carries
  /// a column, so the parser is strict about it. Callers (the
  /// receive-side filter handler) use the returned tuple to find the
  /// matching row in the violation set; an unparseable path is rejected
  /// with an ack carrying `honored: false`.
  static ParsedRulePath? parseRulePath(String path) {
    final atIndex = path.indexOf('@');
    if (atIndex <= 0 || atIndex == path.length - 1) return null;
    final ruleId = path.substring(0, atIndex);
    final remainder = path.substring(atIndex + 1);
    final parsed = parseSourcePath(remainder);
    if (parsed == null) return null;
    final column = parsed.column;
    if (column == null) return null;
    return ParsedRulePath(
      ruleId: ruleId,
      file: parsed.file,
      line: parsed.line,
      column: column,
    );
  }

  /// Parses a canonical [ElementKind.source] path into its
  /// `(file, line, column?)` parts.
  ///
  /// Returns `null` for malformed input. The grammar is
  /// `"<file>:<line>"` or `"<file>:<line>:<column>"`. Files containing
  /// `:` are supported because the parser splits from the right: the
  /// last `:` (or last two) is the line/column boundary, and everything
  /// before is the file path. This matches engine-output convention
  /// (Verilator, Verible, GHDL all emit `path:line:col` regardless of
  /// embedded `:`).
  static ParsedSourcePath? parseSourcePath(String path) {
    final lastColon = path.lastIndexOf(':');
    if (lastColon <= 0 || lastColon == path.length - 1) return null;
    final firstSegment = path.substring(0, lastColon);
    final lastSegment = path.substring(lastColon + 1);

    // Probe whether the last segment is the column and the segment
    // before is the line.
    final maybeColumn = int.tryParse(lastSegment);
    final priorColon = firstSegment.lastIndexOf(':');
    if (maybeColumn != null && priorColon > 0) {
      final lineSegment = firstSegment.substring(priorColon + 1);
      final maybeLine = int.tryParse(lineSegment);
      if (maybeLine != null && maybeLine >= 1 && maybeColumn >= 1) {
        final file = firstSegment.substring(0, priorColon);
        if (file.isEmpty || file.startsWith(':')) return null;
        return ParsedSourcePath(
          file: file,
          line: maybeLine,
          column: maybeColumn,
        );
      }
    }

    // Otherwise treat the last segment as the line.
    final lineOnly = int.tryParse(lastSegment);
    if (lineOnly == null || lineOnly < 1) return null;
    if (firstSegment.isEmpty || firstSegment.startsWith(':')) return null;
    return ParsedSourcePath(
      file: firstSegment,
      line: lineOnly,
    );
  }
}

/// Result of [LintCruxNameResolver.parseRulePath].
class ParsedRulePath {
  /// Creates a parsed rule-path triple.
  const ParsedRulePath({
    required this.ruleId,
    required this.file,
    required this.line,
    required this.column,
  });

  /// Engine-namespaced rule identifier (e.g. `"verilator/UNUSEDSIGNAL"`).
  final String ruleId;

  /// Absolute file path component.
  final String file;

  /// 1-based line number.
  final int line;

  /// 1-based column number.
  final int column;
}

/// Result of [LintCruxNameResolver.parseSourcePath].
class ParsedSourcePath {
  /// Creates a parsed source triple.
  const ParsedSourcePath({
    required this.file,
    required this.line,
    this.column,
  });

  /// Absolute file path component.
  final String file;

  /// 1-based line number.
  final int line;

  /// 1-based column number, or `null` when the path encoded `file:line`
  /// without a column.
  final int? column;
}
