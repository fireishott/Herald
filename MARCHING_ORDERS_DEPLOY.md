# Herald RCA Repair - Deployment Marching Orders

**Generated**: 2026-07-23
**Profile**: ignyte (fih-ai-host .118)
**Scope**: 5 RCA issues + 1 architectural enhancement (push notifications)

---

## Environment

```
host:           fih-ai-host @ 192.168.10.118 (connector, gateway, local relay zombie)
relay host:     192.168.10.101 (Docker relay)
gateway API:    :8642 (hermes on .118)
Docker relay:   :8010 (production relay on .101)
connector WS:   :8765 (native relay - gateway path)
connector MCP:  :8767 (MCP HTTP - hermes_mobile tools)
connector MCP2: :8766 (perseus MCP server)
local relay:    :8020 (ZOMBIE - not in Caddy path, kill it)
Caddy:          routes hermes-relay -> .101:8010
repo:           /Users/curtisfreeman/Herald
connector src:  connector/src/herald_connector/
iOS bundle:     net.fihonline.herald
profile:        ignyte (HERMES_HOME=/home/fihadmin/.hermes/profiles/ignyte)
```

## Cross-Cutting Rules

- Relay has NO migrations - manual SQL only (`docker exec hermes-relay python3 -c "..."`)
- Connector runs on fih-ai-host .118 as fihadmin, systemd user unit
- Docker relay runs on .101:8010
- fih-ai-host has OOM freezes - do not retry slow SSH commands; use timeouts
- MBP builds: unlock keychain before every `xcodebuild`
- Bump iOS version in 4 places: `project.yml` lines 81, 82, 152, 153
- Bump connector version in 2 places: `connector/pyproject.toml:7`, `connector/src/herald_connector/__init__.py:3`
- One logical change = one commit

---

## Priority Summary

| Priority | Task | Type | Effort | Blocked By |
|---|---|---|---|---|
| P0 | Task 1: Re-pair phone credential | Ops | 2 min | - |
| P0 | Task 2: Stabilize FastAPI host WS | Ops | 15 min | - |
| P0 | Task 3: Purge incomplete jobs from relay DB | Ops | 5 min | - |
| P0 | Task 4: Fix MCP transport_security for 0.0.0.0 | Code | 15 min | - |
| P1 | Task 5: Kill zombie local relay + clean duplicate sessions | Ops | 5 min | - |
| P1 | Task 6: Wire server-side APNs push trigger | Code | 30 min | Task 2 |
| P1 | Task 7: Add RELAY_INTERNAL_API_KEY to connector env | Ops | 5 min | - |
| P2 | Task 8: Shorten watchdog 120s -> 30s | Code | 2 min | Task 2 |
| P2 | Task 9: Fix /v1/host/events 404 | Code | 15 min | - |

---

## Phase 1: Operational Fixes (no code changes)

### Task 1 (P0): Re-pair Phone Credential

**RCA Issue**: #1 - REST credential expired, /v1/models returns 401

The connector's REST credential (`tYdrp3N_...`) has expired. WS auth uses a different token (hence "Online" status works) but REST calls to `/v1/hosts/current` and `/v1/models` return 401, breaking the model picker.

The pairing code generator is at `client.py:683` (`create_phone_pairing_code`).

**Steps**:

```bash
# 1. Generate new pairing code
ssh fihadmin@192.168.10.118 "hermes-mobile pair-phone"
```

```bash
# 2. Scan/enter the code in Herald app on phone
```

```bash
# 3. Verify models are back
ssh fihadmin@192.168.10.118 "curl -s http://localhost:8642/v1/models | python3 -m json.tool | head -20"
```

**Acceptance**:
- [ ] `/v1/models` returns model list (not 401)
- [ ] `/v1/hosts/current` returns `isOnline: true` (not 401)
- [ ] Model picker in Herald populated
- [ ] Can switch models from Herald

---

### Task 2 (P0): Stabilize FastAPI Host WebSocket

**RCA Issue**: #2 - WS flap storm (handshake timeouts, 502, 4400, 1011)

The connector's WS to the Docker relay (`wss://hermes-relay.fihonline.net/v1/hosts/ws`) is in a constant flap cycle. The connector retries every 1s (`client.py:786`). Error modes:

1. Handshake timeouts - Caddy/relay not responding fast enough
2. HTTP 502 storm - Caddy returning bad gateway (relay briefly crashed)
3. 4400 disconnect - Relay accepts WS then immediately rejects (duplicate connector session)
4. 1011 keepalive ping timeout - WS established but keepalive fails

The 4400 immediately after connect is the smoking gun - duplicate connector sessions in the relay DB.

**Steps**:

```bash
# 1. Check for duplicate connector sessions in relay DB
ssh fihadmin@192.168.10.101 "docker exec hermes-relay python3 -c \"
import os, psycopg
u = os.environ['DATABASE_URL'].replace('postgresql+psycopg', 'postgresql')
c = psycopg.connect(u)
cur = c.cursor()
cur.execute('SELECT id, is_online, last_seen, connector_version FROM connectors ORDER BY last_seen DESC')
for r in cur.fetchall():
    print(r)
c.close()
\""
```

```bash
# 2. If duplicate entries exist for the same host, delete stale ones
# (keep only the most recent is_online=true entry)
# Replace <stale_id> with the actual id from step 1
ssh fihadmin@192.168.10.101 "docker exec hermes-relay python3 -c \"
import os, psycopg
u = os.environ['DATABASE_URL'].replace('postgresql+psycopg', 'postgresql')
c = psycopg.connect(u)
cur = c.cursor()
cur.execute('DELETE FROM connectors WHERE id = %s', ('<stale_id>',))
c.commit()
print(f'Deleted {cur.rowcount} stale connector(s)')
c.close()
\""
```

```bash
# 3. Restart Docker relay to clear WS state
ssh fihadmin@192.168.10.101 "docker restart hermes-relay"
```

```bash
# 4. Wait 10s then watch connector journal for stability (run for 60s+)
ssh fihadmin@192.168.10.118 "journalctl --user -u hermes-mobile-connector --since '1 min ago' --no-pager | tail -30"
```

**Acceptance**:
- [ ] No 502 errors for 5+ minutes
- [ ] No 4400 disconnects for 5+ minutes
- [ ] No 1011 keepalive ping timeouts for 5+ minutes
- [ ] Journal shows stable "FastAPI host WebSocket connected" with no immediate disconnect
- [ ] Send a test message from Herald - token-by-token streaming works

---

### Task 3 (P0): Purge Incomplete Jobs from Relay DB

**RCA Issue**: #3 - 112K+ incomplete job events, crash-loop risk on restart

The relay's `job_events` table has 112,934 events across 97 incomplete jobs (only 3 `done` events). On relay restart, ALL incomplete jobs are replayed. If any replay contains a non-JSON-serializable type, the relay crashes -> restarts -> crashes again.

**Steps**:

```bash
ssh fihadmin@192.168.10.101 "docker exec hermes-relay python3 -c \"
import os, psycopg
from datetime import datetime, timedelta, timezone
u = os.environ['DATABASE_URL'].replace('postgresql+psycopg', 'postgresql')
c = psycopg.connect(u)
cur = c.cursor()

# Count before
cur.execute('SELECT COUNT(*) FROM job_events')
total_before = cur.fetchone()[0]
print(f'Total events before: {total_before}')

# Delete events for jobs older than 48h that have no done event
cutoff = datetime.now(timezone.utc) - timedelta(hours=48)
cur.execute('''
  DELETE FROM job_events
  WHERE job_id IN (
    SELECT je.job_id
    FROM job_events je
    WHERE je.type = 'started'
      AND je.created_at < %s
      AND je.job_id NOT IN (
        SELECT job_id FROM job_events WHERE type = 'done'
      )
  )
''', (cutoff,))
deleted = cur.rowcount
c.commit()

# Count after
cur.execute('SELECT COUNT(*) FROM job_events')
total_after = cur.fetchone()[0]
print(f'Deleted {deleted} events, {total_after} remaining')

# Verify remaining incomplete job count
cur.execute(\\\"SELECT COUNT(DISTINCT job_id) FROM job_events WHERE type != 'done'\\\")
incomplete = cur.fetchone()[0]
print(f'Remaining incomplete jobs: {incomplete}')

c.close()
\""
```

**Acceptance**:
- [ ] < 50 incomplete jobs remaining
- [ ] < 1000 total job_events (down from 112K+)
- [ ] Relay restart does not trigger crash loop

---

### Task 5 (P1): Kill Zombie Local Relay + Clean Duplicate Sessions

**RCA Issues**: #3 (zombie relay) + #2 (duplicate connector sessions)

A uvicorn process on :8020 (PID 453718) is a local relay zombie. Not in Caddy's routing path (Caddy routes to .101:8010), but consuming resources and creating split-brain risk.

**Steps**:

```bash
# 1. Kill zombie local relay (PID may have changed - find by port)
ssh fihadmin@192.168.10.118 "lsof -ti:8020 | xargs -r kill -9"
```

```bash
# 2. Verify port freed
ssh fihadmin@192.168.10.118 "lsof -ti:8020 || echo 'Port 8020 free'"
```

**Acceptance**:
- [ ] Port 8020 free (no process listening)
- [ ] Single connector entry per host_id in relay DB (verified in Task 2)

---

### Task 7 (P1): Add RELAY_INTERNAL_API_KEY to Connector Environment

The push notification call in Task 6 needs an internal API key to authenticate with the relay's `/v1/push/send` endpoint. The relay's auth uses `X-Relay-Internal-Key` header (`relay/app/security.py:70`) validated against its `INTERNAL_API_KEY` env var.

**Steps**:

```bash
# 1. Get the relay's INTERNAL_API_KEY value
ssh fihadmin@192.168.10.101 "docker exec hermes-relay printenv INTERNAL_API_KEY"
```

```bash
# 2. Add to connector systemd unit (replace <key> with value from step 1)
ssh fihadmin@192.168.10.118 "mkdir -p ~/.config/systemd/user/hermes-mobile-connector.service.d"
```

```bash
ssh fihadmin@192.168.10.118 "cat > ~/.config/systemd/user/hermes-mobile-connector.service.d/push.conf << 'UNIT_EOF'
[Service]
Environment=\"RELAY_INTERNAL_API_KEY=<key>\"
UNIT_EOF"
```

```bash
# 3. Reload and restart
ssh fihadmin@192.168.10.118 "systemctl --user daemon-reload && systemctl --user restart hermes-mobile-connector"
```

```bash
# 4. Verify env var present
ssh fihadmin@192.168.10.118 "systemctl --user show hermes-mobile-connector --property=Environment | grep RELAY"
```

**Acceptance**:
- [ ] `RELAY_INTERNAL_API_KEY` present in connector environment
- [ ] Connector starts without errors
- [ ] No "Push skipped: RELAY_INTERNAL_API_KEY not set" in connector logs after Task 6 deploys

---

## Phase 2: Code Fixes

### Task 4 (P0): Fix MCP transport_security for 0.0.0.0 Bind

**RCA Issue**: #4 - MCP hermes_mobile 421 Misdirected Request

**Root Cause**:

1. `mcp_server.py:26` creates `FastMCP("herald")` at module load. `host` defaults to `"127.0.0.1"`.
2. Because `host == "127.0.0.1"`, the FastMCP constructor auto-enables DNS rebinding protection with `allowed_hosts=["127.0.0.1:*", "localhost:*", "[::1]:*"]`.
3. `client.py:799` later sets `mcp_instance.settings.host = "0.0.0.0"` but does NOT update `settings.transport_security`.
4. Gateway connects via `127.0.1.1:8767` (Linux hostname-mapped loopback). This IP doesn't match any `allowed_hosts` entry, so the MCP server returns 421.

**Fix A** - Update transport_security when host changes (defense-in-depth):

**File**: `connector/src/herald_connector/client.py:795-804`

Replace the entire `_run_mcp_http_server` method:

```python
# CURRENT CODE (lines 795-804):
    async def _run_mcp_http_server(self, host: str, port: int) -> None:
        """Run the MCP Streamable HTTP server as a background task."""
        from .mcp_server import mcp as mcp_instance

        mcp_instance.settings.host = host
        mcp_instance.settings.port = port
        try:
            await mcp_instance.run_streamable_http_async()
        except Exception:
            logger.exception("MCP HTTP server failed")

# REPLACEMENT:
    async def _run_mcp_http_server(self, host: str, port: int) -> None:
        """Run the MCP Streamable HTTP server as a background task."""
        from .mcp_server import mcp as mcp_instance
        from mcp.server.transport_security import TransportSecuritySettings

        mcp_instance.settings.host = host
        mcp_instance.settings.port = port

        if host == "0.0.0.0":
            mcp_instance.settings.transport_security = TransportSecuritySettings(
                enable_dns_rebinding_protection=False,
            )

        try:
            await mcp_instance.run_streamable_http_async()
        except Exception:
            logger.exception("MCP HTTP server failed")
```

**Fix B** - Set correct host at FastMCP construction (permanent fix):

**File**: `connector/src/herald_connector/mcp_server.py:26`

```python
# CURRENT CODE (line 26):
mcp = FastMCP("herald", instructions="Provides real-time location and health data from the user's phone.")

# REPLACEMENT (add import at top of file, after line 16):
from mcp.server.transport_security import TransportSecuritySettings

# Then replace line 26:
mcp = FastMCP(
    "herald",
    instructions="Provides real-time location and health data from the user's phone.",
    host="0.0.0.0",
    transport_security=TransportSecuritySettings(
        enable_dns_rebinding_protection=False,
    ),
)
```

Apply BOTH fixes. Fix B is the permanent fix (production always binds 0.0.0.0). Fix A is defense-in-depth.

**Acceptance**:
- [ ] `curl -X POST http://192.168.10.118:8767/mcp -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}'` returns valid MCP initialize response
- [ ] Gateway can call `http://127.0.1.1:8767/mcp` without 421
- [ ] Gateway can call `http://127.0.0.1:8767/mcp` without 421
- [ ] `hermes mcp test hermes_mobile` passes
- [ ] Sensor tools (get_user_location, get_health_summary, etc.) available in agent

---

### Task 6 (P1): Wire Server-Side APNs Push Trigger

**Blocked by**: Task 2 (WS must be stable), Task 7 (env var must be set)

The Herald iOS app's SSE stream consumer is suspended when the app goes to background (iOS limitation). The local notification in `ChatStore.swift:380-394` only fires when `.finished` actually arrives via SSE - which it won't when suspended. Fix: fire a REMOTE push from the connector when a job completes, via the relay's `/v1/push/send` endpoint.

The relay endpoint exists at `relay/app/main.py:1908`. It expects:
- Header: `X-Relay-Internal-Key` (validated by `require_internal_key` at `security.py:70`)
- Body: `{"user_id": str, "type": "alert"|"silent", "title": str, "body": str}`

**Change 1**: Add `_send_push_for_job` method to `HeraldConnector`

**File**: `connector/src/herald_connector/client.py`

Insert this new method after `_handle_relay_outbound` (after line 1275):

```python
    async def _send_push_for_job(self, job_id: str, body_text: str) -> None:
        """Send a remote push notification via the relay's APNs gateway."""
        state = self.state_store.load()
        if not state.relay_url or not state.user_id:
            return

        internal_key = os.getenv("RELAY_INTERNAL_API_KEY", "").strip()
        if not internal_key:
            logger.debug("Push skipped: RELAY_INTERNAL_API_KEY not set")
            return

        body = body_text.strip()
        if not body:
            return

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.post(
                    f"{state.relay_url.rstrip('/')}/v1/push/send",
                    headers={
                        "X-Relay-Internal-Key": internal_key,
                        "Content-Type": "application/json",
                    },
                    json={
                        "user_id": state.user_id,
                        "type": "alert",
                        "title": "Herald",
                        "body": body[:100],
                    },
                )
                if resp.status_code >= 400:
                    logger.warning(
                        "Push send failed: HTTP %s - %s",
                        resp.status_code,
                        (resp.text or "")[:200],
                    )
                else:
                    logger.info("Push sent for job %s", job_id[:8])
        except Exception:
            logger.debug("Push send error (non-fatal)", exc_info=True)
```

**Dependencies already satisfied**:
- `httpx` imported at `client.py:20`
- `os` imported at `client.py:9`
- `self.state_store` initialized at `client.py:383`
- `state.relay_url` at `state.py:60`, `state.user_id` at `state.py:64`

**Change 2**: Fire push after job.result send (success path)

**File**: `connector/src/herald_connector/client.py`

After line 1119 (`await websocket.send(json.dumps(result_payload))`), add one line:

```python
            self._stop_job_heartbeat(job_id)
            await websocket.send(json.dumps(result_payload))
            await self._send_push_for_job(job_id, cleaned_text)    # <-- ADD THIS LINE
        except Exception as error:  # noqa: BLE001
```

**Change 3**: Fire push after job.failed send (error path)

**File**: `connector/src/herald_connector/client.py`

After line 1127 (the closing `}))` of the `job.failed` websocket send), add one line:

```python
            await websocket.send(json.dumps({
                "type": "job.failed",
                "jobId": job_id,
                "retryable": self._is_retryable_job_error(error),
                "error": str(error),
            }))
            await self._send_push_for_job(job_id, f"Herald ran into an issue: {str(error)[:100]}")    # <-- ADD THIS LINE
```

**Change 4**: Wire `_handle_relay_outbound` for proactive agent messages

**File**: `connector/src/herald_connector/client.py:1270-1275`

Replace the existing stub:

```python
# CURRENT CODE (lines 1270-1275):
    async def _handle_relay_outbound(self, request_id: str, action: dict) -> dict:
        """Handle an outbound action from the gateway (agent response -> deliver to iOS via APNs)."""
        # TODO: Integrate with APNs push handler
        # For now, return success - APNs integration will be wired in T2 completion
        logger.info("Outbound action received: requestId=%s, type=%s", request_id, action.get("type"))
        return {"success": True}

# REPLACEMENT:
    async def _handle_relay_outbound(self, request_id: str, action: dict) -> dict:
        """Handle an outbound action from the gateway (agent response -> deliver to iOS via APNs)."""
        logger.info("Outbound action received: requestId=%s, type=%s", request_id, action.get("type"))
        action_type = action.get("type", "send")
        if action_type == "send":
            text = action.get("text", "")
            await self._send_push_for_job(request_id, text)
        return {"success": True}
```

**Acceptance**:
- [ ] Send a message in Herald, lock phone immediately
- [ ] Within 30s: APNs notification arrives with response preview
- [ ] Tap notification -> app opens with full response, SSE resumes
- [ ] Send a message with app foregrounded: SSE streams normally, push also fires (phone ignores duplicate)
- [ ] No errors in connector log for push sends
- [ ] Connector log shows "Push sent for job xxxxxxxx" on completion

---

### Task 8 (P2): Shorten SSE Watchdog 120s -> 30s

**BLOCKED BY**: Task 2 (WS must be stable for 5+ minutes first)

With server-side push (Task 6) providing an independent delivery channel, the SSE watchdog is now a safety net. 30s catches genuinely dead streams without making the user wait 2 minutes.

**DO NOT deploy this until Task 2 is confirmed stable.** Shortening the watchdog during a WS flap storm causes false "didn't respond" errors.

**File**: `Herald/Stores/ChatStore.swift:36`

```swift
// CURRENT (line 36):
    static var watchdogTimeout: Duration = .seconds(120)

// REPLACEMENT:
    static var watchdogTimeout: Duration = .seconds(30)
```

**Acceptance**:
- [ ] FastAPI host WS stable for 5+ minutes (prerequisite, verified from Task 2)
- [ ] Message sends from Herald with app foregrounded: streaming works normally
- [ ] Lock phone during response: push arrives within 30s
- [ ] No false "didn't respond" errors during normal operation

---

### Task 9 (P2): Fix /v1/host/events 404

**RCA Issue**: #5 - Herald polls `/v1/host/events` every ~10s, gets 404

**Root Cause**: The endpoint does not exist in the relay. Grep of `relay/app/main.py` shows zero matches for `host/events`. The closest endpoints are:
- `/v1/hosts/current` (GET)
- `/v1/hosts/ws` (WebSocket)

The iOS app's `HostStatusStreamService.swift:41` hits `apiClient.streamEvents(path: "host/events", ...)` which maps to `GET /v1/host/events` - a stale client endpoint that the relay never implemented.

**Fix**: Remove the dead SSE polling from the iOS app. Host status is already available via the WS connection.

**File**: `Herald/Services/Live/HostStatusStreamService.swift`

Delete or disable `HostStatusStreamService` and remove its callsite. The entire file (`HostStatusStreamService.swift`, 65 lines) polls a non-existent endpoint. Alternatively, if host-status events are needed, implement the endpoint in the relay - but that's a separate feature, not this RCA scope.

**Minimum fix**: Comment out the `start()` call at the callsite so the 404 polling stops:

```bash
# Find where HostStatusStreamService.start() is called
grep -rn "hostStatusStream\|HostStatusStreamService" Herald/Herald/ --include="*.swift"
```

Then disable the callsite (do not delete the class yet - just stop calling `.start()`).

**Acceptance**:
- [ ] No more 404s for `/v1/host/events` in relay logs
- [ ] Host online/offline status still works (via WS path, not SSE)

---

## Phase 3: Deploy Connector to Host

After all code changes are committed:

```bash
# 1. Bump connector version in 2 places
#    connector/pyproject.toml:7    -> version = "0.3.0"
#    connector/src/herald_connector/__init__.py:3 -> __version__ = "0.3.0"
```

```bash
# 2. Install updated connector on host
ssh fihadmin@192.168.10.118 "cd ~/Herald/connector && git pull && pip install -e ."
```

```bash
# 3. Restart connector (picks up code + env var from Task 7)
ssh fihadmin@192.168.10.118 "systemctl --user restart hermes-mobile-connector"
```

```bash
# 4. Restart gateway to pick up MCP fix
ssh fihadmin@192.168.10.118 "systemctl --user restart hermes"
```

```bash
# 5. Verify MCP tools
ssh fihadmin@192.168.10.118 "curl -s -X POST http://localhost:8767/mcp -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"id\":1,\"params\":{\"protocolVersion\":\"2025-03-26\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"0.1\"}}}' | python3 -m json.tool | head -20"
```

```bash
# 6. Verify connector is connected and stable
ssh fihadmin@192.168.10.118 "journalctl --user -u hermes-mobile-connector --since '30 sec ago' --no-pager"
```

---

## Phase 4: iOS Build (only after WS confirmed stable)

```bash
# 1. Bump version in project.yml (4 places):
#    line 81:  MARKETING_VERSION: "2.1.2"
#    line 82:  CURRENT_PROJECT_VERSION: "53"
#    line 152: MARKETING_VERSION: "2.1.2"
#    line 153: CURRENT_PROJECT_VERSION: "53"

# 2. Apply Task 8 (watchdog) and Task 9 (host/events) changes

# 3. Generate Xcode project
cd /Users/curtisfreeman/Herald
xcodegen generate

# 4. Unlock keychain (REQUIRED before every xcodebuild)
security unlock-keychain -p <pw> ~/Library/Keychains/login.keychain-db

# 5. Build
xcodebuild -project Herald.xcodeproj -scheme Herald -configuration Release archive \
  -archivePath build/Herald.xcarchive

# 6. Upload to TestFlight (see [[herald-testflight-procedure]] for full pipeline)
```

---

## Verification Checklist (Post-Deploy)

### RCA Fixes
- [ ] `/v1/models` returns model list (not 401) - Task 1
- [ ] `/v1/hosts/current` returns isOnline:true (not 401) - Task 1
- [ ] FastAPI host WS stable for 5+ minutes (no 502/4400/1011) - Task 2
- [ ] Incomplete jobs purged from relay DB (< 50 remaining) - Task 3
- [ ] MCP initialize returns valid response (no 421) - Task 4
- [ ] Sensor tools available in agent - Task 4
- [ ] Local relay on :8020 killed - Task 5
- [ ] Single connector session in relay DB - Task 5

### Push Notifications
- [ ] `RELAY_INTERNAL_API_KEY` present in connector env - Task 7
- [ ] Push arrives when app is backgrounded during response - Task 6
- [ ] Tap push -> app opens with full response, SSE resumes - Task 6
- [ ] App foregrounded: SSE streams normally, push fires silently - Task 6

### Streaming
- [ ] Token-by-token streaming works in foreground - Task 2
- [ ] Notification banner appears when agent responds while app backgrounded - Task 6
- [ ] No false "didn't respond" errors - Task 8

### Cleanup
- [ ] No 404s for `/v1/host/events` in relay logs - Task 9
- [ ] Port 8020 free on .118 - Task 5

---

## Env Var Reference

| Variable | Where | Purpose | Task |
|---|---|---|---|
| `RELAY_INTERNAL_API_KEY` | connector (.118) | Connector-side key sent as `X-Relay-Internal-Key` header | 7 |
| `INTERNAL_API_KEY` | relay (.101) | Relay-side key validated against the header | 7 |
| `HERALD_MCP_HOST` | connector (.118) | MCP HTTP server bind address (default: `0.0.0.0`) | 4 |
| `HERALD_MCP_PORT` | connector (.118) | MCP HTTP server port (default: `8767`) | 4 |
| `HERALD_MCP_HTTP_ENABLED` | connector (.118) | Enable MCP HTTP server (default: `1`) | - |
| `HERALD_NATIVE_RELAY_ENABLED` | connector (.118) | Enable native relay WS on :8765 (default: `1`) | - |
| `HERALD_FASTAPI_HOST_WS_ENABLED` | connector (.118) | Enable FastAPI host WS client (default: `1`) | - |
