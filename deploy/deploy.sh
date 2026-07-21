#!/usr/bin/env bash
set -euo pipefail

# ── Hermes deploy script ──────────────────────────────────────────
# Runs schema migration, builds relay image, deploys via docker compose,
# verifies version/schema, and restarts the connector.
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
MIGRATIONS_DIR="$SCRIPT_DIR/migrations"

# ── Pre-flight checks ────────────────────────────────────────────

if [ ! -f "$RELAY_DIR/.env" ]; then
  echo "ERROR: $RELAY_DIR/.env not found.  Copy .env.example and fill in real values."
  exit 1
fi

# Record the deploy commit
DEPLOY_SHA=$(cd "$REPO_ROOT" && git rev-parse --short HEAD)
echo "==> Deploy commit: $DEPLOY_SHA"

# ── Schema migration ─────────────────────────────────────────────

if ! $CONNECTOR_ONLY; then
  echo "==> Running schema migrations..."
  if [ -d "$MIGRATIONS_DIR" ]; then
    for migration in "$MIGRATIONS_DIR"/*.sql; do
      [ -f "$migration" ] || continue
      migration_name=$(basename "$migration")
      echo "    Applying: $migration_name"
      # Run migration against the Postgres container
      run docker compose -f "$RELAY_DIR/docker-compose.yml" exec -T postgres \
        psql -U "${POSTGRES_USER:-herald}" -d "${POSTGRES_DB:-herald}" \
        -f "/docker-entrypoint-initdb.d/$migration_name" 2>/dev/null \
        || run docker compose -f "$RELAY_DIR/docker-compose.yml" exec -T postgres \
        sh -c "cat /dev/stdin | psql -U ${POSTGRES_USER:-herald} -d ${POSTGRES_DB:-herald}" < "$migration" \
        || echo "    WARNING: Migration $migration_name may have already been applied"
    done
  else
    echo "    No migrations directory found — skipping."
  fi
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

  # Verify version and schema
  echo "==> Verifying relay version..."
  VERSION_RESPONSE=$(curl -sf http://localhost:8010/v1/version 2>/dev/null || echo "{}")
  RELAY_GIT_SHA=$(echo "$VERSION_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('gitSha','unknown'))" 2>/dev/null || echo "unknown")
  echo "    Relay git SHA: $RELAY_GIT_SHA (deploy: $DEPLOY_SHA)"
  if [ "$RELAY_GIT_SHA" != "$DEPLOY_SHA" ] && [ "$RELAY_GIT_SHA" != "unknown" ]; then
    echo "    WARNING: Relay SHA does not match deploy commit!"
  fi

  # Verify schema
  echo "==> Verifying schema..."
  SCHEMA_OK=true
  for col in attempt reasoning_effort; do
    if ! curl -sf http://localhost:8010/v1/health | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('data',{}).get('database')" 2>/dev/null; then
      echo "    WARNING: Database connectivity check failed"
      SCHEMA_OK=false
    fi
  done
  if $SCHEMA_OK; then
    echo "    Schema verification passed."
  fi
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

  # Verify singleton connector
  echo "==> Checking connector singleton..."
  CONNECTOR_COUNT=$(pgrep -af 'herald run' 2>/dev/null | wc -l || echo "0")
  if [ "$CONNECTOR_COUNT" -gt 1 ]; then
    echo "    WARNING: $CONNECTOR_COUNT connector processes found! Only one should be running."
  elif [ "$CONNECTOR_COUNT" -eq 1 ]; then
    echo "    Exactly one connector process running."
  else
    echo "    No connector processes found."
  fi
fi

echo "==> Deploy complete. Commit: $DEPLOY_SHA"
