# Mimo Marching Orders — Herald v1.7.4 Bugfix Release

**Date:** 2026-07-21
**Current version:** 1.7.3 / build 39
**Target version:** 1.7.4 / build 40
**Branch:** `master` (HEAD `d2cb690`)

---

## Environment Reference

Before making any changes, understand the deployment topology:

| Component | Where | How |
|-----------|-------|-----|
| **Herald iOS app** | Built on MBP via Xcode 26.3, Swift 6.2, iOS 18.0+ | `project.yml` → xcodegen → build → sideload via Xcode |
| **Relay** (FastAPI/uvicorn) | Docker container `hermes-relay-relay-1` on `fih-ai-host` (192.168.10.118), port **8010** | Compose project `hermes-relay` in `/home/fihadmin/deploy/hermes-relay` (non-git copy) |
| **Postgres** | Docker sidecar `hermes-relay-postgres-1`, Postgres 16-alpine, database `herald` | Named volume `postgres_data`, not exposed externally. DB user: `relay` in prod, `postgres` in some docs — verify with `.env` |
| **Connector** | systemd `hermes-mobile-connector.service` on host | Source at `/home/fihadmin/Hermes-iOS/connector/`, runs from `.venv/bin/herald run` |
| **Hermes agent** | `api_server` on host port **8642** | Model: deepseek-v4-flash via Ollama/llama-server |
| **Dashboard** | Separate desktop process on host port **9119** | basic auth, has HTTP watchdog timer for auto-restart |

**Deploy directory caveat:** `/home/fihadmin/deploy/hermes-relay` is NOT a git repo. Updated relay code must be copied from the checkout at `~/Hermes-iOS/relay/`. The repo's `deploy/RUNBOOK_OPS_2026-07-20.md` documents the full process.

**Build pipeline reminder:** On MBP, unlock keychain before EVERY `xcodebuild`. Bump version in 3 files: `project.yml` (2 targets: Herald + HeraldWidgets) has `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. Strip entitlements for paid team if needed.

---

## Fixes in This Release

| ID | Bug | Severity | Component |
|----|-----|----------|-----------|
| F1 | Notes show "0 notes", new notes fail silently | **Critical** | iOS (`NotesRepository.swift`) |
| F2 | Relay notes API: `_parse_body` is sync, always returns `{}` | **High** | Relay (`notes.py`) |
| F3 | Relay notes API: `create_note` returns tuple instead of Response | **High** | Relay (`notes.py`) |
| F4 | Double thinking bubbles during streaming | **High** | iOS (`ChatStore.swift`, `MarkdownParser.swift`) |
| F5 | Reasoning effort toggle has no effect on LLM output | **High** | Connector (`client.py`, `runtime_adapter.py`) |
| F6 | Gateway live logging not wired into iPad UI | **Medium** | iOS (`AppContainer.swift`, `iPadRightPanelView.swift`) |

---

## F1: Notes Date Encoding/Decoding Mismatch (CRITICAL)

### Root Cause

`NotesRepository.swift` line 47 encodes dates with `.iso8601` but line 41 decodes with the default `.deferredToDate` (expects epoch Doubles). After any note is saved, every subsequent `loadNotes()` throws a decoding error. The error is caught in `NotesStore.loadNotes()` and `notes` stays `[]` → "0 notes". Since `createNote()` internally calls `loadNotes()` first (line 55), new note creation also fails.

### Fix

**File:** `Herald/Features/Notes/NotesRepository.swift`

**Line 41** — change:
```swift
return try JSONDecoder().decode([HeraldNote].self, from: data)
```
to:
```swift
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
return try decoder.decode([HeraldNote].self, from: data)
```

**Also fix `loadAttachments` at line 184** — same pattern, uses bare `JSONDecoder()` while `saveAttachments` (line 192) uses default encoding. Apply matching strategy to both encode and decode for attachments too. Check if `saveAttachments` sets any date encoding strategy — if not, pick one strategy (`.iso8601`) and apply to both save and load for both notes and attachments.

### Data recovery

Any `notes-index.json` written by v1.7.3 contains ISO8601 strings. The fix above will read them correctly. No migration needed — the fix is the migration.

### Verification

1. Build and run on device
2. Open Notes tab — should load any previously-saved notes (dates will parse now)
3. Create a new note — should appear in the list immediately
4. Kill and relaunch the app — notes should persist

---

## F2: Relay `_parse_body` Always Returns Empty Dict

### Root Cause

**File:** `relay/app/notes.py` lines 363-368

```python
def _parse_body(request: Request) -> dict:
    try:
        return request.json() if hasattr(request, '_json') else {}
    except Exception:
        return {}
```

`request.json()` is **async** in Starlette/FastAPI. The function is sync, so it can never `await` the coroutine. The `_json` cache attribute is only set after `await request.json()` has been called, which never happens here. So `hasattr(request, '_json')` is always `False`, and the function always returns `{}`. Every endpoint using `_parse_body` (`create_note`, `update_note`, `create_run`) receives an empty dict — titles are empty, updates never apply.

### Fix

**File:** `relay/app/notes.py`

**Step 1:** Make `_parse_body` async:
```python
async def _parse_body(request: Request) -> dict:
    try:
        return await request.json()
    except Exception:
        return {}
```

**Step 2:** Update all callers to `await` it. Search for `_parse_body(` in the file and add `await` to each call:
- `create_note` (~line 50): `body = await _parse_body(request)`
- `update_note` (~line 91): `body = await _parse_body(request)`
- `create_run` (~line 271): `body = await _parse_body(request)`

**Step 3:** Ensure the caller functions are `async def` (they should already be, since they're FastAPI route handlers).

### Verification

```bash
# After relay redeploy, test from host:
curl -s -X POST http://localhost:8010/v1/notes \
  -H "Authorization: Bearer $INTERNAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"title": "Test Note"}' | jq .
# Should return {"data": {"id": "...", "title": "Test Note", ...}}
```

---

## F3: Relay `create_note` Returns Tuple Instead of Response

### Root Cause

**File:** `relay/app/notes.py` line 76

```python
return {"data": _note_to_dict(note)}, status.HTTP_201_CREATED
```

FastAPI serializes this tuple as a JSON array `[{"data": {...}}, 201]` instead of just `{"data": {...}}` with a 201 status code. The iOS `NoteResponse` decoder fails to parse this.

Same issue at `create_run` (~line 293).

### Fix

**File:** `relay/app/notes.py`

**Line 76** — change:
```python
return {"data": _note_to_dict(note)}, status.HTTP_201_CREATED
```
to:
```python
from fastapi.responses import JSONResponse
# ...
return JSONResponse(content={"data": _note_to_dict(note)}, status_code=status.HTTP_201_CREATED)
```

**Line ~293** (create_run) — same fix:
```python
return JSONResponse(content={"data": _run_to_dict(run)}, status_code=status.HTTP_201_CREATED)
```

Import `JSONResponse` at the top of the file if not already imported:
```python
from fastapi.responses import JSONResponse
```

### Verification

Same curl as F2 — response should be a JSON object `{"data": {...}}`, not `[{...}, 201]`.

---

## F4: Double Thinking Bubbles

### Root Cause

Two independent views render thinking/reasoning content, and both fire for the same message:

1. **`ReasoningView`** — renders `message.reasoning` (streamed via `.reasoningDelta` SSE events). Shown in `MessageBubble.swift:198-203` when `!message.reasoning.isEmpty && settingsStore.settings.showReasoning`.

2. **`ThinkingBlockView`** — renders `<think>...</think>` blocks parsed from `message.content` by `MarkdownParser.swift:201-227`. Shown via `MarkdownContentView.swift:49-51` when `showReasoning` is true.

During streaming, reasoning tokens arrive as `.reasoningDelta` events and accumulate in `message.reasoning`. When `.finished` arrives (`ChatStore.swift:264-293`), the relay's final message may contain `<think>...</think>` blocks in `message.content`. The stripping logic at lines 283-292 can fail if:
- The relay's content doesn't start with the exact streamed reasoning text (whitespace differences)
- The regex strip at line 290 fails on nested tags or multiline edge cases

When stripping fails, both `message.reasoning` (non-empty from streaming) AND `<think>` blocks in `message.content` survive → two thinking bubbles.

### Fix (two-pronged)

**Prong A — Robust stripping in ChatStore.swift (primary fix)**

**File:** `Herald/Stores/ChatStore.swift`, in the `.finished` handler (~line 264-293)

Replace the stripping logic (lines 277-292) with:
```swift
if !streamedReasoning.isEmpty {
    resolved.reasoning = streamedReasoning
    if let startedAt = reasoningStartedAt {
        resolved.reasoningDuration = Date().timeIntervalSince(startedAt)
    }
}
// Always strip <think>…</think> from content — whether or not we streamed reasoning.
// Use dotMatchesLineSeparators so [\s\S] isn't needed.
if let regex = try? NSRegularExpression(pattern: "<think>.*?</think>", options: [.dotMatchesLineSeparators]) {
    let range = NSRange(resolved.content.startIndex..., in: resolved.content)
    resolved.content = regex.stringByReplacingMatches(in: resolved.content, range: range, replacement: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
```

Key changes:
- Always strip `<think>` blocks (moved outside the `if !streamedReasoning.isEmpty` guard)
- Use `NSRegularExpression` with `.dotMatchesLineSeparators` instead of `String.replacingOccurrences` (the `\s\S` pattern in a Swift regex literal can be fragile)
- Remove the `hasPrefix` check entirely — it's unreliable and the regex handles all cases

**Prong B — Guard in MarkdownContentView (defense in depth)**

**File:** `Herald/Features/Chat/MarkdownContentView.swift`, line 49-52

Add a check that suppresses `ThinkingBlockView` when `message.reasoning` is already populated:

```swift
case .thinking(_, let thinkContent):
    if showReasoning && message.reasoning.isEmpty {
        ThinkingBlockView(content: thinkContent, isStreaming: isStreaming)
    }
```

This requires passing `message` (or just `message.reasoning.isEmpty`) into `MarkdownContentView`. Check what the view's init signature already accepts and add a `hasStreamedReasoning: Bool` parameter if `message` isn't available:

```swift
// In MarkdownContentView init, add:
let hasStreamedReasoning: Bool

// In the .thinking case:
case .thinking(_, let thinkContent):
    if showReasoning && !hasStreamedReasoning {
        ThinkingBlockView(content: thinkContent, isStreaming: isStreaming)
    }
```

Then pass `hasStreamedReasoning: !message.reasoning.isEmpty` from `MessageBubble.swift` where `MarkdownContentView` is instantiated.

### Verification

1. Send a message that triggers thinking (any message to deepseek-v4-flash with thinking enabled)
2. During streaming: should see ONE thinking bubble (the `ReasoningView` from `.reasoningDelta`)
3. After completion: should still see ONE thinking bubble (same `ReasoningView`, with duration)
4. No duplicate `ThinkingBlockView` should appear

---

## F5: Reasoning Effort Toggle Dead End-to-End

### Root Cause

The reasoning effort value flows correctly from the iOS UI through the relay to the connector, but the connector drops it:

1. `SettingsScreen.swift:529` — user sets `reasoningEffort`
2. `AppContainer.swift:290` — wired to `LiveHeraldClient`
3. `LiveHeraldClient` sends it in `MessageCreateBody` JSON to relay
4. `relay/app/main.py:710-711` — relay stores it on the job and includes it in the WS payload
5. **`connector/src/herald_connector/client.py:975-980`** — calls `runtime.send_text_message_streaming()` but **never passes** `reasoningEffort` from `job.get("reasoningEffort")`
6. **`connector/src/herald_connector/runtime_adapter.py:107-125`** — `send_text_message_streaming()` has no `reasoning_effort` parameter at all
7. The executor classes (`herald_api_executor.py`, `hermes_gateway_executor.py`) also lack it

### Fix (3 files in connector)

**File 1:** `connector/src/herald_connector/runtime_adapter.py`

Add `reasoning_effort` parameter to `send_text_message_streaming`:
```python
async def send_text_message_streaming(
    self,
    *,
    latest_user_message: str,
    history: list[RuntimeConversationMessage],
    session_id: str | None = None,
    attachments: list[dict] | None = None,
    reasoning_effort: str | None = None,
) -> AsyncIterator:
    """Async streaming send — yields StreamEvent objects."""
    async for event in self.executor.stream_message(
        latest_user_message=latest_user_message,
        history=[
            HeraldConversationMessage(role=message.role, text=message.text)
            for message in history
        ],
        session_id=session_id,
        attachments=attachments,
        reasoning_effort=reasoning_effort,
    ):
        yield event
```

**File 2:** `connector/src/herald_connector/client.py` (~line 975)

Pass `reasoning_effort` from the job:
```python
async for event in runtime.send_text_message_streaming(
    latest_user_message=user_message,
    history=history,
    session_id=job.get("sessionId"),
    attachments=job.get("attachments"),
    reasoning_effort=job.get("reasoningEffort"),
):
```

**File 3:** The executor used in production. Find which executor is active:
```bash
grep -r "class.*Executor" connector/src/herald_connector/ --include="*.py"
```

The executor's `stream_message` method needs to accept and use `reasoning_effort`. For the Hermes API executor (`herald_api_executor.py` or `hermes_gateway_executor.py`):

```python
async def stream_message(
    self,
    *,
    latest_user_message: str,
    history: list[HeraldConversationMessage],
    session_id: str | None = None,
    attachments: list[dict] | None = None,
    reasoning_effort: str | None = None,
) -> AsyncIterator[StreamEvent]:
```

How the executor passes `reasoning_effort` to the LLM depends on the backend API. For the Hermes `api_server` at port 8642:
- If it's an OpenAI-compatible `/v1/chat/completions` endpoint, pass `reasoning_effort` in the request body (DeepSeek supports `reasoning_content` field, or use model-specific params)
- If the `api_server` doesn't support reasoning effort natively, the executor should set `think: true/false` or equivalent based on the value:
  - `"off"` → omit thinking / set `think: false`
  - `"low"` / `"medium"` / `"high"` → set `think: true` (possibly with budget hints if the model supports them)

**Important:** Check how the Hermes `api_server` handles thinking. The current model is `deepseek-v4-flash` which supports `<think>` blocks natively. The executor may need to add a system prompt hint or use the model's specific API params.

### Verification

1. Set reasoning effort to "off" in Herald Settings
2. Send a message — response should NOT contain `<think>` blocks or show a thinking bubble
3. Set reasoning effort to "high"
4. Send a message — response SHOULD show thinking
5. Check relay logs: `docker logs hermes-relay-relay-1 --tail 20 | grep reasoning`

---

## F6: Gateway Live Logging Not Wired Into iPad UI

### Root Cause

Two fully-built components exist but are never instantiated or placed in the view hierarchy:
- `DashboardLogService` (`Herald/Services/Support/DashboardLogService.swift`) — connects via SSE to `{baseURL}/logs/stream` on the dashboard (:9119)
- `LiveLogView` (`Herald/Features/Sidebar/LiveLogView.swift`) — displays the SSE log stream

Neither is instantiated in `AppContainer.swift` or placed in `iPadRightPanelView.swift`. The current "Activity" tab in `iPadRightPanelView` shows local `chatStore.logEntries` only.

Additionally, the server endpoint (`/logs/stream`) does not exist on the relay. The dashboard on :9119 is a separate process that may or may not expose an SSE endpoint.

### Fix (3 steps)

**Step 1: Wire `DashboardLogService` into `AppContainer.swift`**

In `AppContainer.swift`, after the existing service instantiations, add:
```swift
let dashboardLogService = DashboardLogService(
    baseURLProvider: { settingsStore.settings.dashboardURL ?? "http://192.168.10.118:9119" },
    credentialsProvider: { 
        guard let user = settingsStore.settings.dashboardUsername,
              let pass = settingsStore.settings.dashboardPassword else { return nil }
        return (user, pass)
    }
)
```

Check if `SettingsStore` / `UserSettings` already has `dashboardURL`, `dashboardUsername`, `dashboardPassword` fields. If not, add them:

**File:** `Herald/Models/UserSettings.swift`
```swift
var dashboardURL: String?
var dashboardUsername: String?
var dashboardPassword: String?
```

Inject `dashboardLogService` into the SwiftUI environment wherever the iPad sidebar is rendered.

**Step 2: Add a "Live Logs" tab or toggle to `iPadRightPanelView.swift`**

Option A (recommended): Replace the current local-only Activity tab with a hybrid that shows BOTH local `chatStore.logEntries` AND remote `DashboardLogService` entries. Add a segmented control at the top: "Local | Gateway".

Option B: Add `LiveLogView` as a fifth tab in `RightPanelTab`:
```swift
enum RightPanelTab: String, CaseIterable, Identifiable {
    case logs, gateway, terminal, tools, canvas
    // ...
    var title: String {
        switch self {
        case .logs: "Activity"
        case .gateway: "Gateway"
        // ...
        }
    }
}
```

Then in the tab content switch:
```swift
case .gateway: LiveLogView()
```

**Step 3: Verify dashboard SSE endpoint exists**

SSH to the host and check if the dashboard on :9119 exposes `/logs/stream`:
```bash
curl -s -H "Accept: text/event-stream" http://localhost:9119/logs/stream
```

If it doesn't exist, this feature needs a server-side component added to the dashboard. That's a separate task — for this release, add the wiring on the iOS side and show a "Dashboard not available" state if the SSE connection fails (the `DashboardLogService` already handles reconnection and failure states).

### Verification

1. Open Herald on iPad
2. Open the right panel
3. Look for the Gateway tab (or toggle)
4. If dashboard is running on :9119 with `/logs/stream`, should see live log entries
5. If not running, should show "Connection Failed" state gracefully

---

## Deployment Sequence

Execute in this exact order. Each numbered step blocks the next.

### Phase 1: iOS Code Changes (MBP)

All changes are in the local Herald repo at `/Users/curtisfreeman/Herald/`.

1. **Fix F1** — `NotesRepository.swift` date decoding (1 line change)
2. **Fix F4 Prong A** — `ChatStore.swift` robust `<think>` stripping
3. **Fix F4 Prong B** — `MarkdownContentView.swift` guard against duplicate thinking views
4. **Fix F6 Step 1-2** — Wire `DashboardLogService` into `AppContainer` and add Gateway tab to iPad sidebar

### Phase 2: Version Bump (MBP)

**File:** `project.yml` — update in **both** the Herald and HeraldWidgets targets:
```yaml
MARKETING_VERSION: "1.7.4"
CURRENT_PROJECT_VERSION: "40"
```

There are exactly 2 places each — lines 81-82 and lines 133-134.

### Phase 3: Build and Test (MBP)

```bash
# Unlock keychain (required before every build)
security unlock-keychain -p "$(security find-generic-password -s 'login' -w)" ~/Library/Keychains/login.keychain-db

# Generate Xcode project from updated project.yml
xcodegen generate

# Build
xcodebuild -scheme Herald -configuration Debug -destination 'platform=iOS,name=Curtis iPad' build

# Install on device via Xcode, then test:
# - Notes: create, persist across relaunch
# - Thinking: single bubble only
# - Gateway tab: shows in iPad right panel
```

### Phase 4: Relay Fixes (SSH to host)

```bash
ssh fihadmin@192.168.10.118

# Fix F2 and F3 in the relay
cd ~/Hermes-iOS
git pull origin master  # or apply changes manually if not committed

# Edit relay/app/notes.py:
# 1. Make _parse_body async (F2)
# 2. Fix create_note and create_run return types (F3)

# Copy updated relay code to deploy dir
cp -r relay/app/* ~/deploy/hermes-relay/relay/app/
cp relay/pyproject.toml ~/deploy/hermes-relay/relay/

# Rebuild and redeploy relay
cd ~/deploy/hermes-relay
cp .env .env.backup.$(date +%s)
docker compose build relay
docker compose up -d relay

# Wait and verify
sleep 5
curl -s http://localhost:8010/health | jq .
docker logs hermes-relay-relay-1 --tail 20
```

### Phase 5: Connector Fix (SSH to host)

```bash
# Fix F5 — reasoning effort passthrough
cd ~/Hermes-iOS/connector/src/herald_connector

# Edit client.py: pass reasoning_effort to runtime.send_text_message_streaming
# Edit runtime_adapter.py: add reasoning_effort parameter
# Edit the active executor: accept and use reasoning_effort

# Restart connector
sudo systemctl restart hermes-mobile-connector.service
sudo systemctl status hermes-mobile-connector.service
journalctl -u hermes-mobile-connector.service -n 20 --no-pager
```

### Phase 6: End-to-End Verification

Test from the iPad app after all deployments:

| Test | Expected |
|------|----------|
| Open Notes tab | Shows any existing notes (not "0 notes") |
| Create new note | Appears in list, persists across app relaunch |
| Send message with thinking | Single thinking bubble during stream, single after completion |
| Toggle "Show Reasoning" off | Thinking bubble hides |
| Set Reasoning Effort to "off" | Next message has no thinking tokens |
| Set Reasoning Effort to "high" | Next message has thinking tokens |
| iPad right panel → Gateway tab | Shows connection state; if dashboard running on :9119, shows live logs |
| Send message via chat (ignyte) | Says "Yo" → gets response → check relay note creation with title |

### Phase 7: Commit and Tag

```bash
cd ~/Herald  # on MBP
git add Herald/Features/Notes/NotesRepository.swift \
        Herald/Stores/ChatStore.swift \
        Herald/Features/Chat/MarkdownContentView.swift \
        Herald/Stores/AppContainer.swift \
        Herald/Features/Sidebar/iPadRightPanelView.swift \
        Herald/Models/UserSettings.swift \
        project.yml
git commit -m "fix: notes persistence, single thinking bubble, reasoning effort passthrough, gateway log wiring (v1.7.4)"
git tag v1.7.4
git push origin master --tags
```

---

## Files Changed Summary

| File | Fix | Change Type |
|------|-----|-------------|
| `Herald/Features/Notes/NotesRepository.swift` | F1 | Add `.iso8601` date decoding strategy |
| `relay/app/notes.py` | F2, F3 | Make `_parse_body` async; fix return types |
| `Herald/Stores/ChatStore.swift` | F4 | Robust `<think>` stripping in `.finished` handler |
| `Herald/Features/Chat/MarkdownContentView.swift` | F4 | Guard `ThinkingBlockView` when streamed reasoning exists |
| `connector/src/herald_connector/client.py` | F5 | Pass `reasoningEffort` to runtime |
| `connector/src/herald_connector/runtime_adapter.py` | F5 | Accept `reasoning_effort` param |
| `connector/src/herald_connector/*_executor.py` | F5 | Accept and use `reasoning_effort` |
| `Herald/Stores/AppContainer.swift` | F6 | Instantiate `DashboardLogService` |
| `Herald/Features/Sidebar/iPadRightPanelView.swift` | F6 | Add Gateway tab |
| `Herald/Models/UserSettings.swift` | F6 | Add dashboard URL/credentials fields |
| `project.yml` | Version | Bump to 1.7.4 / build 40 |

---

## Risk Notes

- **F1 is the only zero-risk fix** — single line, no behavioral change, just matches decoder to encoder
- **F2/F3 require relay redeploy** — follow the deploy runbook exactly, preserve `.env`
- **F4 Prong A changes streaming completion logic** — test thoroughly with multiple message types (short, long, tool-use, thinking-heavy)
- **F5 requires connector restart** — brief interruption to active sessions. The executor change depends on how the Hermes `api_server` handles reasoning parameters — investigate before implementing
- **F6 is additive** — no risk to existing functionality, graceful failure if dashboard isn't running
