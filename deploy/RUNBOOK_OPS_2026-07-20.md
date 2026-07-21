# Ops Runbook — 2026-07-20

Execute in order. Each step blocks the next.

## Ops-1: Relay redeploy (F1)

### Step 1: Reconcile host checkout

```bash
# SSH to host
ssh fihadmin@<host>

# Check current state
cd ~/Hermes-iOS
git status --short | wc -l   # expect ~477 lines of uncommitted changes
git log --oneline -3          # expect old HEAD

# Stash or diff the uncommitted connector changes
git diff > /tmp/connector-patch.diff
git stash

# Fast-forward to upstream master (contains S1-S3 streaming fixes)
git fetch origin
git checkout master
git merge origin/master

# Verify streaming fixes are present
grep -c "sourceSeq" connector/src/herald_connector/client.py   # expect > 0
grep -c "reasoning_delta" connector/src/herald_connector/client.py   # expect > 0

# Review the stashed changes vs what's now in master
git stash show -p | head -100
# If the stash is a subset of what's now in master, drop it:
# git stash drop
```

### Step 2: Verify Postgres schema

```bash
# Check what tables exist
docker exec hermes-relay-postgres-1 psql -U relay -d relay -c '\dt'

# Verify job_events table (durable log)
docker exec hermes-relay-postgres-1 psql -U relay -d relay -c '\d job_events'

# Verify message_jobs has reasoning_effort column
docker exec hermes-relay-postgres-1 psql -U relay -d relay -c '\d message_jobs' | grep reasoning_effort

# Verify notes tables (1.7.2)
docker exec hermes-relay-postgres-1 psql -U relay -d relay -c "SELECT count(*) FROM information_schema.tables WHERE table_name IN ('notes','note_blobs','note_recognitions','note_runs','note_run_events','enriched_note_revisions');"
# expect 6

# If any are missing, run the CREATE/ALTER from relay/app/models.py manually.
# relay has no migration framework — exact statements only.
```

### Step 3: Copy updated relay code to deploy directory

```bash
# The deploy dir is NOT a git repo. Copy from the checkout:
cd ~/Hermes-iOS
cp -r relay/app/* ~/deploy/hermes-relay/relay/app/
cp relay/pyproject.toml ~/deploy/hermes-relay/relay/
cp relay/Dockerfile ~/deploy/hermes-relay/relay/  # if exists, or use the new one from deploy/

# OR better: use the new deploy/ directory from the repo
cd ~/Hermes-iOS
# The repo now has deploy/relay/docker-compose.yml, Dockerfile, etc.
# Point docker compose at the repo's relay/ source:
```

### Step 4: Rebuild and redeploy

```bash
cd ~/deploy/hermes-relay   # or wherever docker-compose.yml lives

# Preserve .env (APNS_* etc.)
cp .env .env.backup.$(date +%s)

# Rebuild
docker compose build relay

# Verify sourceSeq is in the new image
docker compose run --rm relay grep -c "sourceSeq" /app/app/main.py   # expect > 0

# Deploy
docker compose up -d relay

# Wait for health
sleep 5
curl -s http://localhost:8010/health | jq .

# Check logs for startup
docker logs hermes-relay-relay-1 --tail 20
```

### Step 5: Restart connector

```bash
sudo systemctl restart hermes-mobile-connector.service
sudo systemctl status hermes-mobile-connector.service
journalctl -u hermes-mobile-connector.service -n 20 --no-pager
```

### Step 6: Verify streaming

```bash
# Send a test message from the iOS app, then check relay logs:
docker logs hermes-relay-relay-1 --tail 50 | grep -E "source_seq|text_delta|reasoning_delta"

# Check DB for event ladder:
docker exec hermes-relay-postgres-1 psql -U relay -d relay -c "SELECT seq, type FROM job_events WHERE job_id=(SELECT id FROM message_jobs ORDER BY created_at DESC LIMIT 1) ORDER BY seq LIMIT 20;"
# expect: started, text_delta, text_delta, ..., reasoning_delta, ..., done
```

---

## Ops-2: Gateway config (F2)

### Step 1: Update ignyte config

```bash
# Edit the gateway display config
vi ~/.hermes/profiles/ignyte/config.yaml

# Under display.platforms, add:
#     api_server:
#       show_reasoning: false
#
# This overrides the global show_reasoning: true for the api_server platform only.
# Herald has its own reasoning UI; the gateway's 💭 prepend is for dumb clients (Discord).
```

### Step 2: Restart gateway (SESSIONS DROP)

```bash
# WARNING: Gateway restart drops live sessions. Schedule with Curtis.
# The exact restart command depends on how ignyte runs (systemd? docker? direct?)
# Check: systemctl status hermes-agent or similar

# After restart, verify the config took effect:
grep -A5 "api_server" ~/.hermes/profiles/ignyte/config.yaml
```

### Step 3: Capture F2 duplication repro

```bash
# While restarting anyway, capture a raw SSE stream to diagnose the doubled reasoning:
curl -N -H "Authorization: Bearer $HERMES_API_KEY" \
  -H "Content-Type: application/json" \
  http://localhost:8642/v1/chat/completions \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"Hello"}],"stream":true}' \
  2>&1 | head -100

# Check if delta.content already contains reasoning text before the 💭 block
# If yes → model is inlining reasoning into content (not just a gateway prepend)
# If no → the duplication was solely from the gateway prepend
```

---

## F5a: Enable Push Notifications capability (Apple Developer portal)

The entitlement is declared in `project.yml` and `Herald.entitlements`, but the provisioning profile must also include the Push Notifications capability:

1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Select App ID `net.fihonline.herald`
3. Enable "Push Notifications" capability
4. Regenerate the Development provisioning profile (Xcode does this automatically with Automatic Signing)
5. Clean build in Xcode: Product → Clean Build Folder, then build again
6. Verify: `codesign -d --entitlements :- Herald.app | grep aps-environment`

## F5b: Push logging verification

After Ops-1 (relay redeploy), the new push logging is live. Test:

```bash
# Background the iOS app on device
# Trigger a completion (e.g., send a message from another client or wait for async response)
# Check relay logs:
docker logs hermes-relay-relay-1 --tail 50 | grep -i push

# Expected: "Skipping push for device X (foreground)" or "APNs delivery sent to device X"
# If you see nothing: presence pings may never go stale → check app_presence_stale_seconds setting
```
