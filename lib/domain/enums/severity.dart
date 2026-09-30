// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Unified severity scale across all wrapped lint engines.
///
/// Each engine's native severity vocabulary (Verilator `%Warning`,
/// Verible `severity: warning`, Slang `error` / `warning` / `note`, GHDL
/// `warning` / `error`, Yosys `Warning:` / `Error:`) is normalized to one
/// of these five values during parsing so the violation table can sort
/// and filter without engine-specific knowledge.
///
/// The order is significant — UI components rely on
/// `Severity.values.indexOf` to render the filter chip row left-to-right
/// from highest to lowest severity, and the `compareTo` extension below
/// provides a stable ordering for table sort columns. Do not reorder
/// without updating `severityCompare` and any persisted user filter
/// presets.
enum Severity {
  /// Fatal — the engine could not complete (e.g. syntax error that
  /// aborts parsing, missing include file). Always surfaced regardless
  /// of user filters; cannot be waived.
  fatal,

  /// Error — the engine produced a definite defect (e.g. multiply-driven
  /// net, undefined module). The CI gate default rejects any error.
  error,

  /// Warning — likely defect or methodology violation (e.g.
  /// `WIDTHTRUNC`, `UNUSEDSIGNAL`, missing default in `case`). The bulk
  /// of real-world lint output sits here.
  warning,

  /// Note — informational hint that may be useful but is rarely
  /// actionable (e.g. style preference, naming suggestion). Hidden by
  /// default in the filter chip row.
  note,

  /// None — the engine emitted output that doesn't map to any of the
  /// above (e.g. parser couldn't classify the line). Surfaced only when
  /// the user enables "show unclassified" in diagnostics. Reserved for
  /// log lines that survived parsing but had no usable severity field.
  none,
}

/// Stable comparator: fatal < error < warning < note < none. Suitable
/// for `List.sort` when grouping highest-severity violations first.
int severityCompare(Severity a, Severity b) => a.index.compareTo(b.index);
