// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Reader for Vivado-style `.f` filelists.
///
/// `.f` files are a long-standing convention in the Verilog tool
/// ecosystem (Vivado, Quartus, ModelSim, Verilator) for declaring a
/// project's source set, include paths, and `+define+` flags in a
/// single text file. The shape is line-oriented:
///
/// ```text
/// // Comment (also # comment)
/// +incdir+/abs/or/relative/include/path
/// +define+WIDTH=8
/// +define+DEBUG
/// path/to/source.sv
/// /absolute/path/to/source.v
/// -f other.f          // recursive include of another .f
/// $RTL_HOME/top.sv    // environment-variable expansion
/// ```
///
/// Conventions LintCrux honors:
///
/// * **Comments**: `//` and `#` start a line comment. Inline comments
///   are not supported (matches Vivado/Verilator); the whole line is
///   discarded the moment one of those tokens appears at the start of
///   a token. Leading-whitespace + `//` is also a comment.
/// * **Environment variables**: `$NAME` and `${NAME}` expand from the
///   current process environment (or the [environment] override).
///   Undefined names expand to the empty string — matches Verilator's
///   `--file-list` behavior.
/// * **Recursive `-f`**: `-f other.f` reads the named filelist and
///   inlines its declarations at the current position. The
///   `recursionGuard` deduplicates and rejects cycles with a clear
///   [FilelistImportException].
/// * **Path normalization**: every emitted source / include path is
///   normalized via `p.normalize`. Relative paths resolve against the
///   directory of the `.f` file that declared them — recursive
///   includes resolve against the *inner* file's directory, matching
///   Verilator.
///
/// The reader produces an [ImportedFilelist] aggregate that the
/// "Import Vivado Filelist" wizard / CLI hand off to
/// `ProjectFileCodec` for `.lintcrux` emission.
class FilelistReader {
  /// Creates a [FilelistReader].
  ///
  /// [environment] overrides `Platform.environment` for env-var
  /// expansion — used by tests to drive deterministic substitution.
  const FilelistReader({Map<String, String>? environment})
    : _environmentOverride = environment;

  final Map<String, String>? _environmentOverride;

  Map<String, String> get _environment =>
      _environmentOverride ?? Platform.environment;

  /// Reads [filelistPath] (and any recursive `-f` includes it
  /// references) into an [ImportedFilelist].
  ///
  /// Throws [FilelistImportException] for I/O errors, cycle detection,
  /// or malformed `-f` references (missing file, etc.). Unknown tokens
  /// outside the documented set above are treated as source-file
  /// paths.
  ImportedFilelist read(String filelistPath) {
    final aggregate = _Aggregate();
    final visited = <String>{};
    _readInto(filelistPath, aggregate, visited);
    return aggregate.build();
  }

  void _readInto(
    String filelistPath,
    _Aggregate out,
    Set<String> visited,
  ) {
    final canonical = _canonicalize(filelistPath);
    if (visited.contains(canonical)) {
      throw FilelistImportException(
        'cycle detected via recursive `-f` include: "$canonical"',
      );
    }
    visited.add(canonical);
    final file = File(canonical);
    if (!file.existsSync()) {
      throw FilelistImportException(
        'filelist not found: "$canonical"',
      );
    }
    final List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } on FileSystemException catch (e) {
      throw FilelistImportException(
        'could not read filelist "$canonical": ${e.message}',
      );
    }

    final dir = p.dirname(canonical);

    for (final rawLine in lines) {
      final line = _stripComment(rawLine).trim();
      if (line.isEmpty) continue;
      // Tokenize on whitespace so `-f other.f` and `+define+X=Y`
      // both work. Conservative — we don't try to parse complex
      // quoted strings.
      final tokens = line.split(RegExp(r'\s+'));
      for (var i = 0; i < tokens.length; i++) {
        final token = _expandEnv(tokens[i]);
        if (token.isEmpty) continue;
        if (token == '-f' || token == '-F') {
          if (i + 1 >= tokens.length) {
            throw FilelistImportException(
              '"-f" must be followed by a path (in "$canonical")',
            );
          }
          final next = _expandEnv(tokens[i + 1]);
          final inner = p.isAbsolute(next) ? next : p.join(dir, next);
          _readInto(p.normalize(inner), out, visited);
          // Advance past the consumed argument.
          i += 1;
          continue;
        }
        if (token.startsWith('+incdir+')) {
          final tail = token.substring('+incdir+'.length);
          // Vivado allows `+` separation of multiple paths within one
          // +incdir+ token (e.g. `+incdir+/a+/b`). Match that.
          for (final inc in tail.split('+')) {
            if (inc.isEmpty) continue;
            out.includePaths.add(_resolvePath(inc, dir));
          }
          continue;
        }
        if (token.startsWith('+define+')) {
          final tail = token.substring('+define+'.length);
          // Multiple defines per token: `+define+A=1+B=2`.
          for (final define in tail.split('+')) {
            if (define.isEmpty) continue;
            final eq = define.indexOf('=');
            if (eq < 0) {
              out.defines[define] = '';
            } else {
              out.defines[define.substring(0, eq)] = define.substring(eq + 1);
            }
          }
          continue;
        }
        // Tokens starting with `+` or `-` that don't match the
        // documented forms above are silently dropped — they are
        // tool-specific options (Verilator vs. ModelSim vs. Vivado)
        // and round-tripping them through a generic importer is
        // a category error.
        if (token.startsWith('+') || token.startsWith('-')) continue;
        // Source-file path.
        out.sourceFiles.add(_resolvePath(token, dir));
      }
    }
  }

  static String _stripComment(String line) {
    // Strip `// …` or `# …` trailing comments. We do honor inline
    // comments after the `//` token because Vivado tolerates them
    // (`top.sv  // primary source file`). `#` is treated the same
    // way as a courtesy.
    final slashSlash = line.indexOf('//');
    final hash = line.indexOf('#');
    var cut = -1;
    if (slashSlash >= 0) cut = slashSlash;
    if (hash >= 0 && (cut < 0 || hash < cut)) cut = hash;
    if (cut < 0) return line;
    return line.substring(0, cut);
  }

  String _expandEnv(String token) {
    if (!token.contains(r'$')) return token;
    final buf = StringBuffer();
    var i = 0;
    while (i < token.length) {
      final c = token[i];
      if (c == r'$') {
        // ${NAME}
        if (i + 1 < token.length && token[i + 1] == '{') {
          final end = token.indexOf('}', i + 2);
          if (end > 0) {
            final name = token.substring(i + 2, end);
            buf.write(_environment[name] ?? '');
            i = end + 1;
            continue;
          }
        }
        // $NAME — name = letters / digits / underscore
        var j = i + 1;
        while (j < token.length &&
            (RegExp('[A-Za-z0-9_]').hasMatch(token[j]))) {
          j++;
        }
        if (j > i + 1) {
          final name = token.substring(i + 1, j);
          buf.write(_environment[name] ?? '');
          i = j;
          continue;
        }
      }
      buf.write(c);
      i++;
    }
    return buf.toString();
  }

  String _resolvePath(String path, String baseDir) {
    if (p.isAbsolute(path)) return p.normalize(path);
    return p.normalize(p.join(baseDir, path));
  }

  static String _canonicalize(String path) {
    return p.normalize(p.absolute(path));
  }
}

/// Result of [FilelistReader.read]. Order is preserved — relevant for
/// engines that care about source ordering (Verilog `define`
/// resolution).
@immutable
class ImportedFilelist {
  /// Creates an [ImportedFilelist].
  const ImportedFilelist({
    required this.sourceFiles,
    required this.includePaths,
    required this.defines,
  });

  /// Source-file paths in declaration order (post-cycle-flat).
  final List<String> sourceFiles;

  /// `+incdir+` paths in declaration order.
  final List<String> includePaths;

  /// `+define+` keys mapped to values. Empty value === flag-style
  /// `+define+DEBUG` (no `=` clause).
  final Map<String, String> defines;
}

/// Mutable aggregate the recursive reader writes into.
class _Aggregate {
  final List<String> sourceFiles = <String>[];
  final List<String> includePaths = <String>[];
  final Map<String, String> defines = <String, String>{};

  ImportedFilelist build() => ImportedFilelist(
    sourceFiles: List<String>.unmodifiable(sourceFiles),
    includePaths: List<String>.unmodifiable(includePaths),
    defines: Map<String, String>.unmodifiable(defines),
  );
}

/// Thrown by [FilelistReader] for any malformed `.f` input.
class FilelistImportException implements Exception {
  /// Creates a [FilelistImportException].
  const FilelistImportException(this.message);

  /// English-only description suitable for snackbar / stderr.
  final String message;

  @override
  String toString() => 'FilelistImportException: $message';
}
