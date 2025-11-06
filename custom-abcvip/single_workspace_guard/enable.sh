#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.."; pwd)"
ADDON="$ROOT/custom-abcvip/single_workspace_guard/compose/override.addon.yml"

echo "==> Enabling Single Workspace feature..."
echo "==> Run Plane with this command:"
echo "docker compose -f docker-compose.yml -f docker-compose.override.yml -f $ADDON up -d --build api web"
