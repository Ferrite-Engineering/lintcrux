// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// What a project's `projectId` may look like: letters, digits, `.`, `_` and
/// `-`, 1 to 64 characters.
///
/// The one string anything that spans machines keys a project by, so it is
/// held to a set that needs no quoting anywhere (a URL, a SQL literal, a file
/// name, a CI variable). The project file codec applies it to the file's
/// `projectId` key.
final RegExp kProjectIdPattern = RegExp(r'^[A-Za-z0-9._-]{1,64}$');

/// The sentence a rejected `projectId` ends with.
const String kProjectIdRule =
    'Use 1 to 64 letters, digits, ".", "_" or "-", for example "soc-top".';
