// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/domain/enums/verible_availability_status.dart';
import 'package:lintcrux/domain/interfaces/verible_fix_service.dart';
import 'package:lintcrux/domain/models/verible_availability.dart';
import 'package:lintcrux/domain/models/verible_fix_apply_result.dart';
import 'package:lintcrux/domain/models/verible_fix_batch.dart';
import 'package:lintcrux/services/verible/verible_availability_provider.dart';
import 'package:lintcrux/services/verible/verible_fix_service_provider.dart';

class _FakeService implements VeribleFixService {
  @override
  Future<VeribleAvailability> checkAvailability() async {
    return const VeribleAvailability(
      status: VeribleAvailabilityStatus.available,
      binaryPath: '/usr/local/bin/verible-verilog-lint',
      version: '0.0-3608-g4ca4e1c4',
      capabilities: {VeribleCapability.structuredJsonOutput},
    );
  }

  @override
  Future<VeribleFixBatch> dryRun({
    String? scopeFilter,
    List<String>? specificRules,
  }) async {
    return VeribleFixBatch(
      batchId: 'fake',
      generatedAt: DateTime.utc(2026),
      sourceProject: '/p',
      proposals: const [],
    );
  }

  @override
  Future<List<VeribleFixApplyResult>> apply(
    VeribleFixBatch batch,
    List<String> selectedProposalIds,
  ) async {
    return const <VeribleFixApplyResult>[];
  }
}

void main() {
  group('veribleFixServiceProvider', () {
    test('default is NoopVeribleFixService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(veribleFixServiceProvider),
        isA<NoopVeribleFixService>(),
      );
    });

    test('overridable with a custom implementation', () {
      final container = ProviderContainer(
        overrides: [
          veribleFixServiceProvider.overrideWithValue(_FakeService()),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(veribleFixServiceProvider),
        isA<_FakeService>(),
      );
    });
  });

  group('veribleAvailabilityProvider', () {
    test('Noop default reports notInstalled', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final a = await container.read(veribleAvailabilityProvider.future);
      expect(a.status, VeribleAvailabilityStatus.notInstalled);
    });

    test('honors a Pro-style override', () async {
      final container = ProviderContainer(
        overrides: [
          veribleFixServiceProvider.overrideWithValue(_FakeService()),
        ],
      );
      addTearDown(container.dispose);
      final a = await container.read(veribleAvailabilityProvider.future);
      expect(a.status, VeribleAvailabilityStatus.available);
      expect(a.binaryPath, '/usr/local/bin/verible-verilog-lint');
    });
  });
}
