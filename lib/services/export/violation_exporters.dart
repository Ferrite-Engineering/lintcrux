// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:lintcrux/domain/models/run.dart';
import 'package:lintcrux/domain/models/sarif_report.dart';
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/sarif/sarif_writer.dart';

/// Stateless violation exporters: JSON, CSV, HTML.
///
/// SARIF export is already first-class in `SarifWriter`. The
/// three secondary formats covered here are user conveniences:
///
/// - **JSON** — flat dump of every field on every violation, matching
///   the canonical [Violation] shape. Good for piping into ad-hoc
///   scripts that don't want to deal with SARIF's wider schema.
/// - **CSV** — one row per violation, columns matching the table:
///   severity, engine, rule, file, line, column, message, suppressed.
///   Designed for spreadsheet workflows.
/// - **HTML** — self-contained static dashboard with a sortable table,
///   filter chips, severity color cells. No external JS framework
///   dependency; the small amount of interactivity ships inline.
class ViolationExporters {
  /// Creates a [ViolationExporters].
  const ViolationExporters();

  /// Encodes [violations] as a SARIF 2.1.0 document.
  ///
  /// Groups violations by `engineId` and emits one SARIF `run` per
  /// engine. Reuses [SarifWriter] for the heavy lifting — the
  /// per-run scaffolding (id, timestamps, success flag) is synthesized
  /// here because the exporter operates on a violation list rather
  /// than a live [Run].
  String toSarif(
    Iterable<Violation> violations, {
    DateTime? exportTime,
  }) {
    final now = exportTime ?? DateTime.now();
    final byEngine = <String, List<Violation>>{};
    for (final v in violations) {
      (byEngine[v.engineId] ??= <Violation>[]).add(v);
    }
    final runs = <Run>[
      for (final entry in byEngine.entries)
        Run(
          id: 'export-${entry.key}-${now.microsecondsSinceEpoch}',
          engineId: entry.key,
          engineVersion: '',
          startedAt: now,
          finishedAt: now,
          violations: entry.value,
        ),
    ];
    final report = SarifReport(runs: runs);
    return const SarifWriter().write(report);
  }

  /// Encodes [violations] as a JSON array. The shape is a stable
  /// per-violation map (`engineId`, `ruleId`, `severity`, `message`,
  /// `location`, `relatedLocations`, `suppressed`, `raw`).
  String toJson(Iterable<Violation> violations) {
    final list = <Map<String, dynamic>>[
      for (final v in violations)
        <String, dynamic>{
          'engineId': v.engineId,
          'ruleId': v.ruleId,
          'severity': v.severity.name,
          'message': v.message,
          'location': <String, dynamic>{
            'file': v.location.file,
            'line': v.location.line,
            'column': v.location.column,
          },
          'relatedLocations': <Map<String, dynamic>>[
            for (final loc in v.relatedLocations)
              <String, dynamic>{
                'file': loc.file,
                'line': loc.line,
                'column': loc.column,
              },
          ],
          'suppressed': v.isSuppressed,
          if (v.raw.isNotEmpty) 'raw': v.raw,
        },
    ];
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// Encodes [violations] as a CSV document with header row.
  ///
  /// RFC 4180-style quoting: fields containing commas, double quotes,
  /// or newlines are wrapped in double quotes; internal double quotes
  /// are escaped by doubling.
  String toCsv(Iterable<Violation> violations) {
    final buf = StringBuffer()
      ..writeln(
        'severity,engine,rule,file,line,column,message,suppressed',
      );
    for (final v in violations) {
      buf
        ..write(_csvField(v.severity.name))
        ..write(',')
        ..write(_csvField(v.engineId))
        ..write(',')
        ..write(_csvField(v.ruleId))
        ..write(',')
        ..write(_csvField(v.location.file))
        ..write(',')
        ..write(v.location.line)
        ..write(',')
        ..write(v.location.column)
        ..write(',')
        ..write(_csvField(v.message))
        ..write(',')
        ..writeln(v.isSuppressed ? 'true' : 'false');
    }
    return buf.toString();
  }

  static String _csvField(String s) {
    final needsQuote = s.contains(',') || s.contains('"') || s.contains('\n');
    if (!needsQuote) return s;
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
  }

  /// Encodes [violations] as a self-contained HTML dashboard.
  ///
  /// The output is a single HTML file with inline CSS + a tiny JS
  /// snippet that wires column-header sorting and severity-filter
  /// toggles. No external network dependencies — the file works
  /// offline and can be attached to email or pasted into a code
  /// review as a single static artifact.
  String toHtml(
    Iterable<Violation> violations, {
    String? title,
  }) {
    final list = violations.toList(growable: false);
    final ts = DateTime.now().toIso8601String();
    final docTitle = title ?? 'LintCrux export';
    final rowsHtml = StringBuffer();
    for (final v in list) {
      final sev = v.severity.name;
      final suppressedClass = v.isSuppressed ? ' lc-suppressed' : '';
      final row =
          '<tr class="lc-sev-$sev$suppressedClass" '
          'data-severity="$sev" '
          'data-engine="${_htmlAttr(v.engineId)}"> '
          '<td class="lc-sev-cell">$sev</td> '
          '<td>${_htmlText(v.engineId)}</td> '
          '<td>${_htmlText(v.ruleId)}</td> '
          '<td>${_htmlText(v.location.file)}</td> '
          '<td>${v.location.line}</td> '
          '<td>${v.location.column}</td> '
          '<td>${_htmlText(v.message)}</td>'
          '</tr>';
      rowsHtml.writeln(row);
    }
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${_htmlText(docTitle)}</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
         margin: 24px; color: #1a1a1a; }
  h1 { font-size: 18px; margin: 0 0 4px 0; }
  .lc-meta { font-size: 12px; color: #666; margin-bottom: 16px; }
  .lc-chips { margin-bottom: 12px; }
  .lc-chip { display: inline-block; padding: 4px 10px; margin: 0 6px 4px 0;
             border: 1px solid #ccc; border-radius: 12px; cursor: pointer;
             font-size: 12px; user-select: none; }
  .lc-chip.lc-on { background: #1a1a1a; color: #fff; border-color: #1a1a1a; }
  table { border-collapse: collapse; width: 100%; font-size: 12px; }
  th, td { padding: 6px 8px; border-bottom: 1px solid #eee; text-align: left;
           vertical-align: top; }
  th { cursor: pointer; background: #f7f7f7; user-select: none; }
  .lc-sev-fatal td.lc-sev-cell  { color: #b22222; font-weight: bold; }
  .lc-sev-error td.lc-sev-cell  { color: #d32f2f; font-weight: bold; }
  .lc-sev-warning td.lc-sev-cell { color: #f57c00; }
  .lc-sev-note td.lc-sev-cell   { color: #1976d2; }
  .lc-sev-none td.lc-sev-cell   { color: #888; }
  .lc-suppressed { opacity: 0.5; text-decoration: line-through; }
</style>
</head>
<body>
<h1>${_htmlText(docTitle)}</h1>
<div class="lc-meta">${list.length} violations · exported $ts</div>
<div class="lc-chips" id="lc-chips">
  <span class="lc-chip lc-on" data-sev="fatal">fatal</span>
  <span class="lc-chip lc-on" data-sev="error">error</span>
  <span class="lc-chip lc-on" data-sev="warning">warning</span>
  <span class="lc-chip lc-on" data-sev="note">note</span>
  <span class="lc-chip lc-on" data-sev="none">none</span>
</div>
<table id="lc-table">
<thead><tr>
  <th data-key="severity">Severity</th>
  <th data-key="engine">Engine</th>
  <th data-key="rule">Rule</th>
  <th data-key="file">File</th>
  <th data-key="line">Line</th>
  <th data-key="column">Col</th>
  <th data-key="message">Message</th>
</tr></thead>
<tbody>
$rowsHtml
</tbody>
</table>
<script>
  const chips = document.querySelectorAll('#lc-chips .lc-chip');
  const tbody = document.querySelector('#lc-table tbody');
  const enabled = new Set(['fatal','error','warning','note','none']);
  function applyFilter() {
    for (const tr of tbody.querySelectorAll('tr')) {
      tr.style.display = enabled.has(tr.dataset.severity) ? '' : 'none';
    }
  }
  for (const chip of chips) {
    chip.addEventListener('click', () => {
      const sev = chip.dataset.sev;
      if (enabled.has(sev)) { enabled.delete(sev); chip.classList.remove('lc-on'); }
      else { enabled.add(sev); chip.classList.add('lc-on'); }
      applyFilter();
    });
  }
  let sortKey = null; let sortAsc = true;
  for (const th of document.querySelectorAll('#lc-table th')) {
    th.addEventListener('click', () => {
      const k = th.dataset.key;
      if (sortKey === k) { sortAsc = !sortAsc; } else { sortKey = k; sortAsc = true; }
      const idx = Array.from(th.parentElement.children).indexOf(th);
      const rows = Array.from(tbody.querySelectorAll('tr'));
      rows.sort((a, b) => {
        const av = a.children[idx].textContent;
        const bv = b.children[idx].textContent;
        const an = Number(av), bn = Number(bv);
        const cmp = !isNaN(an) && !isNaN(bn)
            ? an - bn
            : av.localeCompare(bv);
        return sortAsc ? cmp : -cmp;
      });
      for (const r of rows) tbody.appendChild(r);
    });
  }
</script>
</body>
</html>
''';
  }

  static String _htmlText(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _htmlAttr(String s) => _htmlText(s).replaceAll('"', '&quot;');
}
