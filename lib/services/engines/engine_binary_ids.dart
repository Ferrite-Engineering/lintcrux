// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Engines that have no binary of their own and run another engine's.
///
/// CDC is LintCrux's own analysis over a Yosys-elaborated netlist: the only
/// process it starts is `yosys`. Its binary therefore comes from the Yosys
/// binary settings — Settings > Engines > Yosys check, and `--yosys-path` —
/// rather than from a CDC setting that would have to be kept in step with
/// Yosys by hand.
const Map<String, String> _kSharedBinaryEngineIds = <String, String>{
  'cdc': 'yosys',
};

/// The engine id whose binary configuration [engineId] runs with.
///
/// Identity for every engine that starts its own tool.
String binaryEngineIdFor(String engineId) =>
    _kSharedBinaryEngineIds[engineId] ?? engineId;

/// Whether [engineId] has a binary configuration of its own.
///
/// Settings > Engines shows a binary row only for these, so a user is never
/// offered a path that the engine does not read.
bool hasOwnBinary(String engineId) => binaryEngineIdFor(engineId) == engineId;
