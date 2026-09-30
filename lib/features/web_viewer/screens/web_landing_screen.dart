// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lintcrux/features/web_viewer/providers/sarif_file_loader_provider.dart';
import 'package:lintcrux/features/web_viewer/providers/web_sarif_source_provider.dart';
import 'package:lintcrux/l10n/generated/app_localizations.dart';
import 'package:lintcrux/services/sarif/sarif_file_loader.dart';
import 'package:lintcrux/services/violations/violation_store_provider.dart';

/// Landing screen for the web read-only mode.
///
/// Two ingestion paths:
///   * file picker — accepts a `.sarif` / `.sarif.json` upload via
///     `package:file_selector` (web implementation routes to a hidden
///     `<input type="file">`).
///   * URL bar — pastes a SARIF URL; clicking "Open" fetches and
///     parses.
///
/// When the page is first rendered, [WebLandingScreen] also inspects
/// the `?sarif=<encoded-url>` query parameter; if present, it triggers
/// an auto-fetch and navigates to the viewer on success.
class WebLandingScreen extends ConsumerStatefulWidget {
  /// Creates a [WebLandingScreen].
  const WebLandingScreen({super.key});

  @override
  ConsumerState<WebLandingScreen> createState() => _WebLandingScreenState();
}

class _WebLandingScreenState extends ConsumerState<WebLandingScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _autoLoadStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeAutoLoadFromQuery());
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _maybeAutoLoadFromQuery() async {
    if (_autoLoadStarted) return;
    _autoLoadStarted = true;
    final url = readSarifQueryParam();
    if (url == null) return;
    await _loadFromUrl(url);
  }

  Future<void> _loadFromUrl(Uri url) async {
    final loader = ref.read(sarifFileLoaderProvider);
    final store = ref.read(violationStoreProvider);
    final notifier = ref.read(webSarifSourceProvider.notifier);
    final router = GoRouter.of(context);
    notifier.markLoading();
    try {
      final report = await loader.loadFromUrl(url, store: store);
      final count = report.runs.fold<int>(
        0,
        (sum, r) => sum + r.violations.length,
      );
      notifier.markLoaded(
        WebSarifSourceUrl(url),
        violationCount: count,
      );
      if (!mounted) return;
      router.go('/web/viewer');
    } on SarifLoadException catch (e) {
      notifier.markFailed(e.message);
    }
  }

  Future<void> _pickAndLoadFile() async {
    final loader = ref.read(sarifFileLoaderProvider);
    final store = ref.read(violationStoreProvider);
    final notifier = ref.read(webSarifSourceProvider.notifier);
    final router = GoRouter.of(context);
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'SARIF',
          extensions: <String>['sarif', 'json'],
          mimeTypes: <String>['application/sarif+json', 'application/json'],
        ),
      ],
    );
    if (file == null) return;
    notifier.markLoading();
    try {
      final report = await loader.loadFromXFile(file, store: store);
      final count = report.runs.fold<int>(
        0,
        (sum, r) => sum + r.violations.length,
      );
      notifier.markLoaded(
        WebSarifSourceFile(file.name),
        violationCount: count,
      );
      if (!mounted) return;
      router.go('/web/viewer');
    } on SarifLoadException catch (e) {
      notifier.markFailed(e.message);
    }
  }

  void _loadFromUrlField() {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;
    final parsed = Uri.tryParse(raw);
    if (parsed == null ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      ref
          .read(webSarifSourceProvider.notifier)
          .markFailed(L10N.of(context).webModeInvalidUrl);
      return;
    }
    unawaited(_loadFromUrl(parsed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(webSarifSourceProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.webModeAppBarTitle),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.webModeHeadline,
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.webModeBody,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: state.isLoading ? null : _pickAndLoadFile,
                    icon: const Icon(Icons.upload_file),
                    label: Text(l10n.webModeOpenFileButton),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.webModeUrlPrompt,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          enabled: !state.isLoading,
                          decoration: InputDecoration(
                            hintText: 'https://...',
                            border: const OutlineInputBorder(),
                            labelText: l10n.webModeUrlFieldLabel,
                          ),
                          onSubmitted: (_) => _loadFromUrlField(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: state.isLoading ? null : _loadFromUrlField,
                        child: Text(l10n.webModeUrlOpenButton),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(),
                    ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.errorMessage!,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    l10n.webModeFooterNote,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
