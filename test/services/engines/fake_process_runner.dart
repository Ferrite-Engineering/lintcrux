// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Re-export shim. The canonical `FakeProcessRunner` now lives in the
// shared integration-test helpers directory
// (`integration_test/helpers/fake_process_runner.dart`) so that both the
// engine unit tests here AND the `integration_test/` suite (and the Pro
// overlay's integration tests via `pro_app_driver.dart`) can consume the
// same process-runner double from one canonical location — mirroring the
// simcrux `integration_test/helpers/seeded_run.dart` shared-double
// convention.
//
// The engine unit tests keep importing this path unchanged; it forwards
// to the promoted file. New integration tests should import it via the
// helpers path / `pro_app_driver.dart` instead.
export '../../../integration_test/helpers/fake_process_runner.dart';
