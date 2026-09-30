// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point through which the Pro overlay
/// contributes additional [LocalizationsDelegate]s without forking
/// `LintcruxApp` or `bootstrap`.
///
/// The open-core default returns an empty list — `LintcruxApp.build`
/// concatenates this list with `L10N.localizationsDelegates` and the
/// three Flutter global delegates and passes the combined sequence to
/// `MaterialApp.router`. The overlay's `proOverrides` replaces this
/// provider with one that returns Pro-specific delegates (e.g.
/// `L10NPro.delegate`) so widgets in the Pro repo can resolve their
/// own `Localizations.of<T>` lookup.
///
/// Mirrors WaveCrux's `extraLocalizationsDelegatesProvider`
/// (see wavecrux/lib/plugins/extra_localizations_delegates_provider.dart).
final extraLocalizationsDelegatesProvider =
    Provider<List<LocalizationsDelegate<Object?>>>((_) => const []);
