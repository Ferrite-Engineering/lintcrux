// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:path/path.dart' as p;

/// [posixAbsolute] (`/proj/rtl/cpu.sv`) spelled as an absolute path on the
/// host running the test.
///
/// CXP's path floor (`CxpPathContainment`) accepts a path only when it is
/// absolute *and* names its root. On Windows `/proj/rtl/cpu.sv` names no
/// drive, so the floor refuses it as `file_path must be an absolute path` —
/// correctly: a receiver cannot know which drive the sender meant. A test
/// that sends a made-up absolute path to prove some other rule (the roots,
/// the editor hand-off) has to spell it the way the host spells an absolute
/// path, or on Windows it only ever proves the floor.
///
/// POSIX hosts get [posixAbsolute] back unchanged. Windows hosts get the
/// same segments under the system temp directory, which exists on every
/// runner: containment resolves the deepest existing prefix of a path
/// through the filesystem, so a path hung off a real directory is judged
/// the same way `/proj/...` is judged on POSIX, whatever the drive layout.
///
/// Roots and the paths checked against them must both come through here,
/// so they share a spelling.
String hostAbsolute(String posixAbsolute) {
  if (!p.posix.isAbsolute(posixAbsolute)) {
    throw ArgumentError.value(
      posixAbsolute,
      'posixAbsolute',
      'must be a POSIX absolute path',
    );
  }
  if (!Platform.isWindows) return posixAbsolute;
  return p.joinAll(<String>[
    Directory.systemTemp.path,
    'lintcrux_host_absolute',
    ...p.posix.split(posixAbsolute).skip(1),
  ]);
}
