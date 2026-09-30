// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:lintcrux/domain/models/violation.dart';
import 'package:lintcrux/services/source_preview/source_preview_service.dart';

/// Provider for the [SourcePreviewService] singleton. Tests override
/// with a service whose [SourcePreviewService.reader] is a fake.
final Provider<SourcePreviewService> sourcePreviewServiceProvider =
    Provider<SourcePreviewService>(
      (ref) => const SourcePreviewService(),
    );

/// Provider exposing the [SourceWindow] for [violation]. `null` when
/// [violation] is `null`; an empty window when the file cannot be read.
///
/// Keyed by the violation rather than reading the violation-table
/// selection provider directly: selection is feature-layer UI state, so
/// the source-preview feature passes the selected violation in (e.g.
/// `sourcePreviewWindowProvider(ref.watch(selectedViolationProvider))`).
/// This keeps the services layer from importing a features/ provider.
final FutureProviderFamily<SourceWindow?, Violation?>
sourcePreviewWindowProvider = FutureProvider.family<SourceWindow?, Violation?>((
  ref,
  violation,
) async {
  if (violation == null) return null;
  final svc = ref.watch(sourcePreviewServiceProvider);
  final related = <int>{};
  for (final loc in violation.relatedLocations) {
    if (loc.file == violation.location.file) {
      related.add(loc.line);
    }
  }
  return await svc.windowAround(
    file: violation.location.file,
    line: violation.location.line,
    relatedLineSet: related,
  );
});
