#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build + deploy the OPEN-CORE LintCrux read-only web viewer to Cloudflare
# (app.lintcrux.app).
#
# Cloudflare Workers Static Assets, same model as the WaveCrux app and the
# marketing sites. The viewer ships open-core with no beta expiry — redeploy to
# ship updates to everyone.
#
# One-time setup:
#   - `wrangler login` (OAuth) to authenticate this machine to the Cloudflare
#     account that holds the lintcrux.app zone (it already hosts the marketing
#     site).
#   - app.lintcrux.app is provisioned automatically from wrangler.jsonc on
#     first deploy.
#
# Run from the repo root:
#   ./scripts/deploy_web.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Refuse a release whose version disagrees with the beta flag compiled from
# the pinned crux-shared (a 1.x build with the beta still on ships every paid
# feature free). See scripts/check_beta_period.sh.
"$REPO_ROOT/scripts/check_beta_period.sh"

echo "=== pub get ==="
flutter pub get

echo "=== l10n ==="
flutter gen-l10n

echo "=== flutter build web (release) ==="
# NOTE: deliberately no --dart-define=BETA_EXPIRY. The per-release hard build
# expiry (crux_license `kBetaExpiry`, guide §17) is a desktop-distribution
# mechanism: a web build self-updates on deploy, so a visitor is at most one
# reload away from the current version and there is no stale build to retire.
# Injecting an expiry here would block the viewer for anyone who happens to
# load a cached bundle after the date.
flutter build web --release

echo "=== Deploy to Cloudflare (lintcrux-viewer -> app.lintcrux.app) ==="
if command -v wrangler >/dev/null 2>&1; then
  wrangler deploy
else
  npx --yes wrangler deploy
fi

echo ""
echo "Deployed. Live at https://app.lintcrux.app/"
echo "(First deploy provisions the custom domain — DNS/SSL may take a minute.)"
