// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:path/path.dart' as p;

/// The pin-constraint formats the `constraints` engine reads, one per
/// nextpnr family.
enum ConstraintFormat {
  /// Lattice iCE40, read by nextpnr-ice40: `set_io`.
  pcf('.pcf', 'PCF'),

  /// Lattice ECP5, read by nextpnr-ecp5: `LOCATE COMP`, `IOBUF PORT`.
  lpf('.lpf', 'LPF'),

  /// Gowin, read by nextpnr-himbaechel: `IO_LOC`, `IO_PORT`.
  cst('.cst', 'CST');

  const ConstraintFormat(this.extension, this.edamFileType);

  /// The lowercase file extension, with its dot.
  final String extension;

  /// The Edalize `file_type` that names this format in an EDAM file.
  final String edamFileType;

  /// The format of the file at [path] by its extension, or `null` for any
  /// other extension. Never a guess.
  static ConstraintFormat? fromPath(String path) {
    final ext = p.extension(path).toLowerCase();
    for (final format in values) {
      if (format.extension == ext) return format;
    }
    return null;
  }

  /// The format an EDAM `file_type` names, or `null`.
  ///
  /// Edalize compares the string exactly (`f["file_type"] == "PCF"`), so this
  /// does too.
  static ConstraintFormat? fromEdamFileType(String fileType) {
    for (final format in values) {
      if (format.edamFileType == fileType) return format;
    }
    return null;
  }

  /// Every extension [fromPath] accepts, for messages.
  static String get extensionList => values.map((f) => f.extension).join(', ');
}
