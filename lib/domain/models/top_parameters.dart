// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The rules a top-level parameter override follows, in one place: the
// project file's `parameters` map and the command line's `--param` both
// check against them, so a value one accepts every engine accepts.

/// A parameter name: a plain Verilog identifier.
final RegExp kParameterNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_$]*$');

/// A parameter value: one token of letters, digits and `_ ' . + -`. That is
/// a number (`1`, `-4`, `8'hff`, `32'd100`) or an identifier, which is what
/// Verilator and Slang take after `-G<name>=` and Yosys after
/// `hierarchy -chparam <name>`.
///
/// White space, quotes and `;` are refused: a string value needs quoting of
/// its own in each of those readers, and a value that could split a command
/// line or a Yosys script is not one any engine should be handed.
final RegExp kParameterValuePattern = RegExp(r"^[A-Za-z0-9_'.+-]+$");

/// Why a parameter override was refused, in words the user can act on, or
/// `null` when [name] and [value] are both acceptable.
String? parameterProblem(String name, String value) {
  if (!kParameterNamePattern.hasMatch(name)) {
    return 'parameter name "$name" is not a Verilog identifier';
  }
  if (!kParameterValuePattern.hasMatch(value)) {
    return 'parameter "$name" has the value "$value": a value must be a '
        "number (1, 8'hff) or an identifier, without spaces or quotes";
  }
  return null;
}
