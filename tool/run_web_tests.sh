#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Run the browser-only tests under headless Chrome via
# `flutter test --platform chrome`.
#
# The default VM `flutter test` compiles with `kIsWeb == false`, so the web
# viewer's branches — its router, the missing workspace, the web dispatch of
# shared actions — are unreachable there. Every test file under test/ that
# opts in with `@TestOn('browser')` is skipped by the VM runner and runs here
# instead; nothing else runs them.
#
# Usage:
#   tool/run_web_tests.sh                     # every @TestOn('browser') file
#   tool/run_web_tests.sh test/a_web_test.dart [more...]
#
# Requires a Chrome that `flutter test --platform chrome` can launch.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(grep -rl --include='*_test.dart' "@TestOn('browser')" test | sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No @TestOn('browser') tests found under test/." >&2
  exit 1
fi

flutter test --platform chrome "${files[@]}"
