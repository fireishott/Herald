#!/usr/bin/env bash
# Herald Field Freeze — capture deployment state before recovery work.
# Run on fih-ai-host as fihadmin.
# Produces artifacts in ~/herald-field-freeze-<timestamp>/

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTDIR="$HOME/herald-field-freeze-${TIMESTAMP}"
mkdir -p "$OUTDIR"

echo "=== Herald Field Freeze — $(date -Is) ==="
echo "Output: $OUTDIR"

# 1. Git state
echo "--- Git state ---"
cd ~/Hermes-iOS
git status --short --branch > "$OUTDIR/git-status.txt"
git rev-parse HEAD > "$OUTDIR/git-head.txt"
git diff --binary > "$OUTDIR/herald-field-before-recovery.patch"
tar -czf "$OUTDIR/herald-field-untracked-before-recovery.tgz" \
  connector/MCP-RCA.md \
  connector/src/herald_connector/hermes_api_executor.py \
  connector/src/herald_connector/hermes_gateway_executor.py \
  connector/src/herald_connector/hermes_runner.py \
  connector/src/herald_connector/stream_contract.py \
  relay/app/hermes_adapter.py \
  2>/dev/null || echo "Some untracked files missing (non-fatal)"

# 2. Docker state
echo "--- Docker state ---"
docker inspect hermes-relay-relay-1 > "$OUTDIR/relay-inspect.json" 2>&1 || true
docker logs hermes-relay-relay-1 > "$OUTDIR/relay-logs.txt" 2>&1 || true
docker inspect hermes-relay-postgres-1 > "$OUTDIR/postgres-inspect.json" 2>&1 || true

# 3. Connector service state
echo "--- Connector service ---"
systemctl --user status hermes-mobile-connector.service --no-pager \
  > "$OUTDIR/connector-service-status.txt" 2>&1 || true
journalctl --user -u hermes-mobile-connector.service --since '24 hours ago' --no-pager \
  > "$OUTDIR/connector-journal.txt" 2>&1 || true
pgrep -af 'herald run' > "$OUTDIR/connector-processes.txt" 2>&1 || echo "No herald run processes found" > "$OUTDIR/connector-processes.txt"

# 4. Postgres backup
echo "--- Postgres backup ---"
docker exec hermes-relay-postgres-1 sh -lc \
  'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' \
  > "$OUTDIR/herald-postgres-before-recovery.dump" 2>/dev/null || echo "Postgres dump failed (non-fatal)"
ls -lh "$OUTDIR/herald-postgres-before-recovery.dump" 2>/dev/null || true

# 5. SHA-256 checksums
echo "--- Checksums ---"
cd "$OUTDIR"
sha256sum * > checksums.txt 2>/dev/null || shasum -a 256 * > checksums.txt

echo "=== Freeze complete ==="
echo "Artifacts in: $OUTDIR"
cat "$OUTDIR/checksums.txt"
