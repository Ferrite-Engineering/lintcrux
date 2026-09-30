// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';

/// Riverpod provider exposing the app-wide [SarifFileLoader].
///
/// One instance per `ProviderScope` lifetime so the underlying
/// `http.Client` is reused across file loads. Disposal closes the
/// client.
final Provider<SarifFileLoader> sarifFileLoaderProvider =
    Provider<SarifFileLoader>((ref) {
      final loader = SarifFileLoader();
      ref.onDispose(loader.dispose);
      return loader;
    });
