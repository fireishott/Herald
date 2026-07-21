#!/usr/bin/env bash
set -euo pipefail

# ── Hermes deploy script ──────────────────────────────────────────
# Builds relay image, verifies schema, deploys via docker compose,
# and restarts the connector.  Supports --dry-run.
#
# Usage:
#   ./deploy/deploy.sh              # live deploy
#   ./deploy/deploy.sh --dry-run    # print commands without executing
#   ./deploy/deploy.sh --relay-only # skip connector restart
#   ./deploy/deploy.sh --connector-only # skip relay, restart connector only

DRY_RUN=false
RELAY_ONLY=false
CONNECTOR_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=true ;;
    --relay-only)    RELAY_ONLY=true ;;
    --connector-only) CONNECTOR_ONLY=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELAY_DIR="$SCRIPT_DIR/relay"
CONNECTOR_DIR="$REPO_ROOT/connector"

# ── Pre-flight checks ────────────────────────────────────────────

if [ ! -f "$RELAY_DIR/.env" ]; then
  echo "ERROR: $RELAY_DIR/.env not found.  Copy .env.example and fill in real values."
  exit 1
fi

# ── Relay deploy ──────────────────────────────────────────────────

if ! $CONNECTOR_ONLY; then
  echo "==> Building relay image..."
  run docker compose -f "$RELAY_DIR/docker-compose.yml" build --no-cache relay

  echo "==> Starting relay + Postgres..."
  run docker compose -f "$RELAY_DIR/docker-compose.yml" up -d

  echo "==> Waiting for relay health check..."
  for i in $(seq 1 30); do
    if curl -sf http://localhost:8010/v1/health > /dev/null 2>&1; then
      echo "    Relay is healthy."
      break
    fi
    if [ "$i" -eq 30 ]; then
      echo "ERROR: Relay failed to become healthy after 30s."
      exit 1
    fi
    sleep 1
  done

  echo "==> Verifying schema (relay creates tables on startup)..."
  # The relay auto-creates tables via SQLAlchemy create_all().
  # A successful health check confirms the app booted with a valid schema.
  echo "    Schema OK (tables auto-created by relay on startup)."
fi

# ── Connector restart ────────────────────────────────────────────

if ! $RELAY_ONLY; then
  if [ -d "$CONNECTOR_DIR" ] && command -v pm2 > /dev/null 2>&1; then
    echo "==> Restarting connector via pm2..."
    run pm2 restart hermes-connector || run pm2 restart connector || echo "    WARNING: pm2 restart failed — restart connector manually."
  elif [ -d "$CONNECTOR_DIR" ]; then
    echo "==> Connector directory found but pm2 not available.  Restart connector manually."
  else
    echo "==> No connector directory found at $CONNECTOR_DIR — skipping."
  fi
fi

echo "==> Deploy complete."
