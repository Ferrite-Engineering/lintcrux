#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build the headless `lintcrux` CI binary.
#
# Why `dart build cli` and not `dart compile exe`:
#   `dart compile` refuses to run when any package in the resolution
#   declares a native build hook. `objective_c` does, pulled in
#   transitively by `path_provider_foundation` — a Flutter plugin the
#   *desktop app* needs and the CLI never touches, but resolution is
#   per-package, not per-entrypoint. `dart build cli` is the supported
#   replacement. It emits `<out>/bundle/bin/lintcrux` plus a `lib/`
#   directory of native assets; the executable does not load any of them
#   for this entrypoint, so `bundle/bin/lintcrux` ships standalone.
#
# Usage:
#   tool/build_cli.sh [output-dir]        # default: build/cli
#
# The resulting single-file binary is at:
#   <output-dir>/bundle/bin/lintcrux
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-build/cli}"

echo "==> dart build cli -t bin/lintcrux.dart -o ${OUT_DIR}"
dart build cli -t bin/lintcrux.dart -o "${OUT_DIR}"

BIN="${OUT_DIR}/bundle/bin/lintcrux"
if [[ ! -x "${BIN}" ]]; then
  echo "error: expected executable at ${BIN}" >&2
  exit 1
fi

echo "==> smoke test"
"${BIN}" --version
"${BIN}" --help > /dev/null

echo "==> built ${BIN}"
