// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io' show File, FileSystemException;

import 'package:meta/meta.dart';

/// Where a SystemVerilog source first declares or imports a package.
@immutable
class SvPackageUse {
  /// Creates a use.
  const SvPackageUse({
    required this.file,
    required this.line,
    required this.packageName,
    required this.isDeclaration,
  });

  /// The source file, as the request names it.
  final String file;

  /// 1-based line.
  final int line;

  /// The package's name.
  final String packageName;

  /// `true` for `package <name>;`, `false` for `import <name>::`.
  final bool isDeclaration;

  /// The construct as written: `package cdc_types_pkg` or
  /// `import cdc_types_pkg::`.
  String get construct =>
      isDeclaration ? 'package $packageName' : 'import $packageName::';
}

final RegExp _packageDeclaration = RegExp(r'^\s*package\s+([A-Za-z_]\w*)\s*;');
final RegExp _packageImport = RegExp(r'\bimport\s+([A-Za-z_]\w*)\s*::');

/// The first package declaration or import in [paths], in list order, or
/// `null` when none of them has one.
///
/// Read line by line from disk, never as one whole-file string: the files are
/// a design's, and one can be large. A `//` comment is ignored; a block
/// comment is not parsed, so a package named only inside one still counts.
/// That errs toward the "needs the slang frontend" answer, which is the one
/// asked for only after Yosys has already refused the design. A file that
/// cannot be read is skipped.
Future<SvPackageUse?> findSvPackageUse(Iterable<String> paths) async {
  for (final path in paths) {
    var lineNumber = 0;
    try {
      final lines = File(path)
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());
      await for (final raw in lines) {
        lineNumber++;
        final comment = raw.indexOf('//');
        final line = comment < 0 ? raw : raw.substring(0, comment);
        if (_packageDeclaration.firstMatch(line) case final RegExpMatch m) {
          return SvPackageUse(
            file: path,
            line: lineNumber,
            packageName: m.group(1)!,
            isDeclaration: true,
          );
        }
        if (_packageImport.firstMatch(line) case final RegExpMatch m) {
          return SvPackageUse(
            file: path,
            line: lineNumber,
            packageName: m.group(1)!,
            isDeclaration: false,
          );
        }
      }
    } on FileSystemException {
      continue;
    }
  }
  return null;
}
