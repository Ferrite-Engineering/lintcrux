// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lintcrux/core/platform/web_mode.dart';

/// Source description for whatever SARIF document the web viewer is
/// currently rendering.
///
/// A small reactive record so the web viewer's app-bar subtitle, the
/// "currently viewing" badge, and the empty-state messaging all stay
/// in sync without re-reading the loader's last-result tuple.
sealed class WebSarifSource {
  const WebSarifSource();
}

/// No SARIF has been loaded yet — the landing-screen empty state
/// renders.
class WebSarifSourceEmpty extends WebSarifSource {
  /// Creates the empty source.
  const WebSarifSourceEmpty();
}

/// SARIF was loaded from a local file picked through the browser
/// upload sheet. [name] is the file's basename (no path is available
/// on web).
class WebSarifSourceFile extends WebSarifSource {
  /// Creates a file source.
  const WebSarifSourceFile(this.name);

  /// The picked file's basename (e.g. `report.sarif.json`).
  final String name;
}

/// SARIF was fetched from a remote URL — either supplied via the
/// `?sarif=<url>` query parameter or pasted into the URL input.
class WebSarifSourceUrl extends WebSarifSource {
  /// Creates a URL source.
  const WebSarifSourceUrl(this.url);

  /// The fetched URL.
  final Uri url;
}

/// Loader state for the in-flight read attempt.
class WebSarifLoadState {
  /// Creates a [WebSarifLoadState].
  const WebSarifLoadState({
    this.source = const WebSarifSourceEmpty(),
    this.isLoading = false,
    this.errorMessage,
    this.violationCount = 0,
  });

  /// Empty default — nothing loaded, nothing in flight.
  static const WebSarifLoadState idle = WebSarifLoadState();

  /// Which source the latest successful load came from.
  final WebSarifSource source;

  /// True while a load is in flight.
  final bool isLoading;

  /// Most recent load failure, or `null` on success.
  final String? errorMessage;

  /// Number of violations in the last successful load.
  final int violationCount;

  /// Returns a copy with overridden fields.
  WebSarifLoadState copyWith({
    WebSarifSource? source,
    bool? isLoading,
    String? errorMessage,
    int? violationCount,
    bool clearError = false,
  }) {
    return WebSarifLoadState(
      source: source ?? this.source,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      violationCount: violationCount ?? this.violationCount,
    );
  }
}

/// Reactive notifier tracking the web viewer's loaded SARIF state.
class WebSarifSourceNotifier extends Notifier<WebSarifLoadState> {
  @override
  WebSarifLoadState build() => WebSarifLoadState.idle;

  /// Marks the start of a load operation.
  void markLoading() {
    state = state.copyWith(isLoading: true, clearError: true);
  }

  /// Records a successful load.
  void markLoaded(WebSarifSource source, {required int violationCount}) {
    state = WebSarifLoadState(
      source: source,
      violationCount: violationCount,
    );
  }

  /// Records a load failure.
  void markFailed(String message) {
    state = state.copyWith(isLoading: false, errorMessage: message);
  }
}

/// Provider exposing the web SARIF source state.
final NotifierProvider<WebSarifSourceNotifier, WebSarifLoadState>
webSarifSourceProvider =
    NotifierProvider<WebSarifSourceNotifier, WebSarifLoadState>(
      WebSarifSourceNotifier.new,
    );

/// Reads the `?sarif=<encoded-url>` query parameter from the current
/// browser URL. Returns `null` on non-web targets, when the parameter
/// is absent, or when its value is not a valid http/https URI.
Uri? readSarifQueryParam() {
  if (!isWebMode) return null;
  final raw = Uri.base.queryParameters['sarif'];
  if (raw == null || raw.isEmpty) return null;
  final parsed = Uri.tryParse(raw);
  if (parsed == null) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  return parsed;
}
