// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/enums/constraint_format.dart';
import 'package:lintcrux/domain/enums/severity.dart';
import 'package:lintcrux/services/engines/cdc/cdc_source_span.dart';
import 'package:lintcrux/services/engines/constraints/constraint_model.dart';
import 'package:lintcrux/services/engines/yosys/yosys_elaboration.dart';
import 'package:path/path.dart' as p;

// Pure Dart: no Flutter, no dart:io. The six checks the `constraints` engine
// makes over parsed constraint files and the top module's ports.

/// One parsed constraint file.
class ParsedConstraintFile {
  /// Creates the pair.
  const ParsedConstraintFile({
    required this.path,
    required this.format,
    required this.result,
  });

  /// The file's absolute path.
  final String path;

  /// Its format.
  final ConstraintFormat format;

  /// What reading it produced.
  final ConstraintParseResult result;
}

/// One finding of a check, before it becomes a `Violation`.
class ConstraintFinding {
  /// Creates a finding.
  const ConstraintFinding({
    required this.ruleId,
    required this.severity,
    required this.message,
    this.file,
    this.line = 1,
    this.column = 1,
    this.declaration,
    this.port,
    this.pin,
  });

  /// The rule's local id, without the `constraints/` prefix.
  final String ruleId;

  /// The rule's default severity.
  final Severity severity;

  /// What is wrong, in a sentence.
  final String message;

  /// The constraint file the finding sits in, or `null` when it sits on
  /// [declaration].
  final String? file;

  /// 1-based line in [file].
  final int line;

  /// 1-based column in [file].
  final int column;

  /// The port's declaration in the RTL, for a finding that sits there.
  final CdcSourceSpan? declaration;

  /// The port the finding is about, for the `raw` map.
  final String? port;

  /// The pin the finding is about, for the `raw` map.
  final String? pin;
}

/// Local ids of the six rules, as `lib/data/rules/constraints.json` lists
/// them.
abstract final class ConstraintRuleIds {
  /// A constraint names a port the top module does not have.
  static const String unknownPort = 'unknown-port';

  /// A top-level port has no pin.
  static const String unconstrainedPort = 'unconstrained-port';

  /// A constraint names a bit the port does not have.
  static const String bitOutOfRange = 'bit-out-of-range';

  /// A second port is put on a pin another port already has.
  static const String pinReused = 'pin-reused';

  /// A port or bus bit is put on two different pins.
  static const String portReassigned = 'port-reassigned';

  /// A line no reader recognised.
  static const String unparsedLine = 'unparsed-line';
}

/// The longest list of bits one `unconstrained-port` message spells out.
const int kMaxListedBits = 16;

/// Checks [files] against [ports], the ports of the module [topModule].
///
/// Findings come back in file order, then the unconstrained ports in
/// declaration order. Pins and ports are compared within one format: a pin
/// number in a `.pcf` and one in a `.cst` belong to different devices.
List<ConstraintFinding> checkConstraints({
  required List<ElaboratedPort> ports,
  required List<ParsedConstraintFile> files,
  required String topModule,
}) {
  final byName = <String, ElaboratedPort>{
    for (final port in ports) port.name: port,
  };
  final findings = <ConstraintFinding>[];

  // Per format: the first owner of each pin, the first pin of each port bit,
  // and which bits have a pin at all.
  final pinOwners = <ConstraintFormat, Map<String, _Placement>>{};
  final firstPins = <ConstraintFormat, Map<String, _Placement>>{};
  final placed = <ConstraintFormat, Map<String, Set<int?>>>{};

  for (final file in files) {
    final owners = pinOwners.putIfAbsent(file.format, () => {});
    final pins = firstPins.putIfAbsent(file.format, () => {});
    final placedBits = placed.putIfAbsent(file.format, () => {});
    final name = p.basename(file.path);

    for (final entry in file.result.entries) {
      ConstraintFinding at(
        String ruleId,
        Severity severity,
        String message, {
        String? pin,
      }) => ConstraintFinding(
        ruleId: ruleId,
        severity: severity,
        message: message,
        file: file.path,
        line: entry.line,
        column: entry.column,
        port: entry.port,
        pin: pin ?? entry.pin,
      );

      final resolved = _resolve(entry, byName);
      switch (resolved) {
        case _Unknown():
          final bus = byName[entry.port];
          findings.add(
            at(
              ConstraintRuleIds.unknownPort,
              Severity.error,
              bus != null && bus.isBus && entry.bit == null
                  ? '`${entry.port}` is a ${bus.width}-bit bus in `$topModule`, '
                        'so a constraint has to name a bit, such as '
                        '`${entry.port}[${bus.indexRange.$2}]`.'
                  : 'Port `${entry.written}` is not a port of `$topModule`.'
                        '${_didYouMean(entry.port, byName.keys)}',
            ),
          );
        case _OutOfRange(:final port):
          findings.add(
            at(
              ConstraintRuleIds.bitOutOfRange,
              Severity.error,
              port.isBus
                  ? '`${entry.written}` is out of range: `${port.name}` is '
                        'declared ${_range(port)}.'
                  : '`${entry.written}` is out of range: `${port.name}` is a '
                        'single bit.',
            ),
          );
        case _Resolved(:final port, :final key, :final bit):
          final pin = entry.pin;
          if (pin == null) break;
          final here = _Placement(
            key: key,
            pin: pin,
            file: file.path,
            line: entry.line,
          );
          final owner = owners[pin];
          if (owner == null) {
            owners[pin] = here;
          } else if (owner.key != key) {
            findings.add(
              at(
                ConstraintRuleIds.pinReused,
                Severity.error,
                'Pin `$pin` is already used by `${owner.key}` '
                '(${_where(owner, file.path, name)}); `$key` cannot share it.',
              ),
            );
          }
          final earlier = pins[key];
          if (earlier == null) {
            pins[key] = here;
          } else if (earlier.pin != pin) {
            findings.add(
              at(
                ConstraintRuleIds.portReassigned,
                Severity.warning,
                '`$key` is placed on pin `$pin` here and on pin '
                '`${earlier.pin}` (${_where(earlier, file.path, name)}).',
              ),
            );
          }
          placedBits.putIfAbsent(port.name, () => <int?>{}).add(bit);
      }
    }

    for (final unparsed in file.result.unparsed) {
      findings.add(
        ConstraintFinding(
          ruleId: ConstraintRuleIds.unparsedLine,
          severity: Severity.note,
          message:
              'Line not recognised, so it was not checked: '
              '`${unparsed.text}`.',
          file: file.path,
          line: unparsed.line,
          column: unparsed.column,
        ),
      );
    }
  }

  // The ports with no pin, once per format, so a project with a `.pcf` and a
  // `.cst` is judged against each.
  final formats = <ConstraintFormat>[];
  for (final file in files) {
    if (!formats.contains(file.format)) formats.add(file.format);
  }
  for (final format in formats) {
    final group = <ParsedConstraintFile>[
      for (final f in files)
        if (f.format == format) f,
    ];
    final where = group.length == 1
        ? p.basename(group.first.path)
        : 'any of the ${group.length} ${format.extension} files';
    final placedBits = placed[format] ?? const <String, Set<int?>>{};
    for (final port in ports) {
      final have = placedBits[port.name] ?? const <int?>{};
      final missing = <int>[
        for (final index in port.indexes)
          if (!have.contains(port.isBus ? index : null)) index,
      ];
      if (port.isBus ? missing.isEmpty : have.isNotEmpty) continue;
      findings.add(
        ConstraintFinding(
          ruleId: ConstraintRuleIds.unconstrainedPort,
          severity: Severity.warning,
          message: _unconstrainedMessage(port, missing, where),
          file: group.first.path,
          declaration: port.declaration,
          port: port.name,
        ),
      );
    }
  }
  return findings;
}

String _unconstrainedMessage(
  ElaboratedPort port,
  List<int> missing,
  String where,
) {
  if (!port.isBus) return 'Port `${port.name}` has no pin in $where.';
  if (missing.length == port.width) {
    return 'Port `${port.name}` (${port.width} bits) has no pin in $where.';
  }
  final shown = missing.take(kMaxListedBits).join(', ');
  final more = missing.length > kMaxListedBits
      ? ' and ${missing.length - kMaxListedBits} more'
      : '';
  return 'Bit${missing.length == 1 ? '' : 's'} $shown$more of port '
      '`${port.name}` ${missing.length == 1 ? 'has' : 'have'} no pin in '
      '$where.';
}

String _range(ElaboratedPort port) {
  final (low, high) = port.indexRange;
  return port.upto ? '[$low:$high]' : '[$high:$low]';
}

String _where(_Placement placement, String currentFile, String currentName) {
  final line = 'line ${placement.line}';
  return placement.file == currentFile
      ? '$line of $currentName'
      : '$line of ${p.basename(placement.file)}';
}

class _Placement {
  const _Placement({
    required this.key,
    required this.pin,
    required this.file,
    required this.line,
  });

  final String key;
  final String pin;
  final String file;
  final int line;
}

sealed class _Resolution {
  const _Resolution();
}

final class _Unknown extends _Resolution {
  const _Unknown();
}

final class _OutOfRange extends _Resolution {
  const _OutOfRange(this.port);
  final ElaboratedPort port;
}

final class _Resolved extends _Resolution {
  const _Resolved(this.port, this.key, this.bit);
  final ElaboratedPort port;

  /// How the port bit is written: `led[3]` for a bus, `clk` for a scalar.
  final String key;

  /// The bit index for a bus, `null` for a scalar.
  final int? bit;
}

/// Which port bit [entry] names.
///
/// nextpnr treats a one-bit wire as a scalar, so `x[0]` names a one-bit `x`;
/// it names the cells of a bus as `led[3]`, so a bus named with no index
/// matches no cell.
_Resolution _resolve(ConstraintEntry entry, Map<String, ElaboratedPort> ports) {
  // A port whose own name contains brackets (a Verilog escaped identifier)
  // is the name as written.
  final literal = ports[entry.written];
  if (literal != null && entry.bit != null) {
    return _Resolved(literal, literal.name, null);
  }
  final port = ports[entry.port];
  if (port == null) return const _Unknown();
  final bit = entry.bit;
  if (port.isBus) {
    if (bit == null) return const _Unknown();
    if (!port.hasIndex(bit)) return _OutOfRange(port);
    return _Resolved(port, '${port.name}[$bit]', bit);
  }
  if (bit == null || bit == port.offset) {
    return _Resolved(port, port.name, null);
  }
  return _OutOfRange(port);
}

/// A suggestion when exactly one port is within edit distance 2 of [name],
/// ignoring case; empty otherwise.
String _didYouMean(String name, Iterable<String> candidates) {
  final lower = name.toLowerCase();
  String? best;
  var count = 0;
  for (final candidate in candidates) {
    if (_distance(lower, candidate.toLowerCase()) <= 2) {
      best = candidate;
      count++;
    }
  }
  return count == 1 ? ' Did you mean `$best`?' : '';
}

int _distance(String a, String b) {
  if (a == b) return 0;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
