# Mimo Marching Orders - Herald v1.7.5 Point Release (Bugfix)

**Date:** 2026-07-21
**Author:** Claude Opus 4.6 (code-grounded audit from screenshots + repo + live host)
**Current version:** 1.7.4 / build 40 (tag `v1.7.4`, HEAD `3909d6f`)
**Target version:** 1.7.5 / build 41
**Branch:** `master`

---

## Cross-Cutting Rules (apply to EVERY change)

1. Bump `MARKETING_VERSION` to `1.7.5` and `CURRENT_PROJECT_VERSION` to `41` in `project.yml` (lines 81-82 AND 141-142)
2. One change = one commit = one dated CHANGELOG entry
3. Relay has **no migration framework** - ship manual `ALTER`s if schema changes
4. Swift 6 strict concurrency must stay clean (`SWIFT_STRICT_CONCURRENCY: complete`)
5. Unlock login keychain before EVERY `xcodebuild`
6. Run `xcodegen generate` after editing `project.yml`
7. Deploy relay by copying from `~/Hermes-iOS/relay/` to `~/deploy/hermes-relay/relay/` (deploy dir is NOT a git repo)
8. Connector is a **user-level** systemd service: `systemctl --user restart hermes-mobile-connector.service` (NOT `sudo systemctl`)

---

## Environment Block

| Thing | Value |
|------|-------|
| **App repo** | `/Users/curtisfreeman/Herald` (git; branch `master`) |
| **iOS app** | `Herald/` target, Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, iOS 18.0+ |
| **Widgets** | `HeraldWidgets/` extension, App Group `group.net.fihonline.herald` |
| **Relay** | `relay/` FastAPI + Postgres (docker sidecar); host `192.168.10.118:8010`; health endpoint is `/v1/health` (NOT `/health`) |
| **Connector** | `connector/src/herald_connector/`; Python WS client; user-level systemd service `hermes-mobile-connector.service` |
| **Hermes host** | `fih-ai-host` @ `192.168.10.118`; hard-freezes from OOM; model: deepseek-v4-flash via api_server on port 8642 |
| **Build machine** | MacBook Pro; unlock keychain before every build |
| **Project gen** | XcodeGen - edit `project.yml`, run `xcodegen generate` |
| **Bundle / team** | `net.fihonline.herald` / `58U7UPFS53` |
| **Deploy dir** | `/home/fihadmin/deploy/hermes-relay` (NOT a git repo - files copied from checkout) |
| **Relay DB** | Postgres 16 in `hermes-relay-postgres-1`, database `hermes_mobile`, user `hermes` |

---

## v1.7.4 Delivery Status (What Mimo Shipped)

All six v1.7.4 fixes were committed (`f5e8da7` + `3909d6f`) and deployed:

| Fix | Status | Verified |
|-----|--------|----------|
| F1: Notes date encoding | Committed | Needs retest |
| F2: Relay `_parse_body` async | Committed + relay redeployed | Relay up, but notes POST returns 401 (auth issue in test, not code) |
| F3: Relay `create_note` JSONResponse | Committed + relay redeployed | Same |
| F4: Double thinking bubbles | Committed (NSRegularExpression fix in 3909d6f) | Needs device test |
| F5: Reasoning effort passthrough | Committed + connector restarted | Connector logs show chat completions flowing |
| F6: Gateway live logging | Committed | iPad panel needs device test |

---

## Environment Issues Found (Fix Before Code)

### E1: Relay Health Endpoint Wrong Path (P0-infrastructure)

**Problem:** The health check uses `curl http://localhost:8010/health` but the endpoint is at `/v1/health`. Returns 404.

**Evidence:** Relay logs show `"GET /health HTTP/1.1" 404 Not Found`. Route list confirms `/v1/health {'GET'}`.

**Fix:** Update all monitoring/verification scripts to use `/v1/health`:
```bash
# In deploy runbook and all verification steps:
curl -s http://localhost:8010/v1/health | jq .
```

### E2: Relay Logging Silent (P1-observability)

**Problem:** The relay Docker container has only 10 log lines despite being up for an hour. Uvicorn is not configured with a log level, so the app-level logger (Python `logging` module) output is lost. Only uvicorn's access log shows.

**Evidence:** `docker logs hermes-relay-relay-1 2>&1 | wc -l` = 10 lines. No app-level logs for jobs, messages, push notifications, or errors.

**Fix:** Add `--log-level info` to the uvicorn CMD in `relay/Dockerfile`:
```dockerfile
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--log-level", "info", \
     ...rest unchanged...]
```

Also verify the app configures Python logging to propagate to the root logger. Check `relay/app/main.py` startup for `logging.basicConfig()` or similar.

### E3: Connector Systemd Command (P2-docs)

**Problem:** Previous marching orders used `sudo systemctl restart` but the connector is a **user-level** service.

**Fix:** All references must use:
```bash
systemctl --user restart hermes-mobile-connector.service
systemctl --user status hermes-mobile-connector.service
journalctl --user -u hermes-mobile-connector.service -n 20 --no-pager
```

---

## Bug Fixes

### B1: Notes - New Note Cannot Be Selected/Opened (P0)

**Symptom:** Creating a new note makes it appear in the list, but tapping it (or any other note) doesn't switch the editor. The previously-open note stays in the foreground. The workspace feels "wonky" - the split view doesn't respond to selection changes.

**Root Cause:** `NoteEditorView` loads its data only in `.onAppear` (line 99), which fires once per view lifecycle. When `selectedNoteId` changes in `NotesWorkspaceView`, SwiftUI reuses the existing `NoteEditorView` instance (same structural position in the `detail` slot) without recreating it. `.onAppear` does not re-fire, so `loadNote()` never runs for the new note ID.

**Files:**
- `Herald/Features/Notes/NotesWorkspaceView.swift:14` - missing `.id()` modifier
- `Herald/Features/Notes/NoteEditorView.swift:99-101` - `.onAppear` is sole load trigger

**Fix:**

**File: `Herald/Features/Notes/NotesWorkspaceView.swift`, line 14**

Add `.id(selectedId)` to force SwiftUI to destroy and recreate the editor when the note changes:

```swift
if let selectedId = store.selectedNoteId {
    NoteEditorView(noteId: selectedId)
        .id(selectedId)
} else {
```

This is the minimal fix. The `.id()` modifier tells SwiftUI this is a new view identity when the UUID changes, which triggers full teardown/recreation including `.onAppear`.

**Acceptance Criteria:**
1. Create a new note - it appears in the list AND the editor switches to show it (empty canvas, cursor in title field)
2. Tap a different note in the list - the editor switches to that note's content
3. Rapid switching between notes updates the canvas each time
4. Creating note A, switching to note B, then back to A shows A's saved content

---

### B2: Chat Sessions Always Titled "New Chat" (P0)

**Symptom:** Every new chat conversation shows "New Chat" in the session list. No auto-generated title from the conversation content.

**Root Cause:** `autoTitleIfNeeded()` at `ChatStore.swift:566-581` has three problems:

1. **Naive title generation** (line 574): It just truncates the first user message to 60 chars instead of generating a meaningful summary title. "When enriching cards on Hailie's love and bliss board you must use stealth tools..." becomes a 60-char prefix, not "Hailie's board card enrichment".

2. **Silent error swallowing** (line 578-580): If `heraldClient.renameSession()` throws (e.g., the session ID format doesn't match what the relay expects, or auth issues), the error is caught and discarded. No logging, no retry.

3. **Only runs on `.finished`** (line 313): If the stream terminates with `.failed` or `.cancelled` (which happens when responses are unreliable - see B3), `autoTitleIfNeeded()` never executes.

**Files:**
- `Herald/Stores/ChatStore.swift:566-581` - `autoTitleIfNeeded()` method
- `Herald/Stores/ChatStore.swift:313` - only call site (in `.finished` handler)
- `Herald/Stores/ChatStore.swift:338-349` - `.cancelled` handler (no title generation)
- `Herald/Stores/ChatStore.swift:354-379` - `.failed` handler (no title generation)

**Fix (two-part):**

**Part A - LLM-generated title via connector RPC**

Add a new RPC method `session.generateTitle` to the connector that asks the LLM to produce a 3-6 word title from the first exchange.

**File: `connector/src/herald_connector/client.py`**

In the RPC handler dispatch (find the `_handle_rpc` method or equivalent), add:

```python
elif method == "session.generateTitle":
    user_message = params.get("userMessage", "")
    assistant_message = params.get("assistantMessage", "")
    prompt = f"Generate a concise 3-6 word title for this conversation. Return ONLY the title, nothing else.\n\nUser: {user_message}\nAssistant: {assistant_message}"
    # Use the same runtime adapter for a quick non-streaming completion
    title = await self.runtime.generate_title(prompt)
    return {"title": title}
```

**File: `connector/src/herald_connector/runtime_adapter.py`**

Add a `generate_title` method:

```python
async def generate_title(self, prompt: str) -> str:
    """Quick non-streaming completion for title generation."""
    result = await self.executor.complete(prompt, max_tokens=20)
    return result.strip().strip('"').strip("'")[:60]
```

**File: `connector/src/herald_connector/herald_api_executor.py`**

Add a `complete` method (non-streaming single-shot):

```python
async def complete(self, prompt: str, max_tokens: int = 20) -> str:
    """Non-streaming single-shot completion."""
    payload = {
        "model": self.model_name,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "stream": False,
        "temperature": 0.3,
    }
    if hasattr(self, '_think_param'):
        payload[self._think_param] = False
    response = await self._client.post(
        f"{self.api_url}/v1/chat/completions",
        json=payload,
    )
    response.raise_for_status()
    data = response.json()
    return data["choices"][0]["message"]["content"]
```

**File: `relay/app/main.py`**

Add a relay endpoint that forwards the title generation RPC:

```python
@app.post("/v1/sessions/{session_id}/generate-title")
async def generate_session_title(
    session_id: str,
    body: dict,
    auth: AuthContext = Depends(get_auth_context),
    db: Session = Depends(get_db),
) -> dict:
    session = get_session(db, session_id=session_id)
    if session is None or session.user_id != auth.user.id:
        raise HTTPException(status_code=404, detail="Session not found.")
    
    # Forward to connector via RPC
    result = await rpc_to_connector(
        db, user_id=auth.user.id,
        method="session.generateTitle",
        params={
            "userMessage": body.get("userMessage", ""),
            "assistantMessage": body.get("assistantMessage", ""),
        }
    )
    if result and "title" in result:
        rename_session(db, session_id=session_id, title=result["title"])
        return success({"title": result["title"]})
    return success({"title": None})
```

**Part B - Fix `autoTitleIfNeeded()` on the iOS side**

**File: `Herald/Stores/ChatStore.swift`**

Replace `autoTitleIfNeeded()` (lines 566-581):

```swift
private func autoTitleIfNeeded() async {
    let defaultTitles: Set<String> = ["New Chat", "Herald"]
    guard let conv = conversation,
          defaultTitles.contains(conv.title),
          let firstUserMessage = conv.messages.first(where: { $0.sender == .user })
    else { return }
    let raw = firstUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return }

    // Try LLM-generated title first
    let assistantContent = conv.messages.first(where: { $0.sender == .assistant })?.content ?? ""
    if let generated = try? await heraldClient.generateSessionTitle(
        sessionId: conv.id,
        userMessage: String(raw.prefix(500)),
        assistantMessage: String(assistantContent.prefix(500))
    ) {
        conversation?.title = generated
        onTitleChanged?(conv.id, generated)
        return
    }

    // Fallback: truncated first message
    let title = raw.count > 60 ? String(raw.prefix(57)) + "..." : raw
    do {
        _ = try await heraldClient.renameSession(id: conv.id, title: title)
        conversation?.title = title
        onTitleChanged?(conv.id, title)
    } catch {
        appendLog(level: .warn, "Auto-title failed: \(error.localizedDescription)")
    }
}
```

Add the `generateSessionTitle` method to the Herald client protocol and implementation.

Also call `autoTitleIfNeeded()` in the `.failed` handler (after line 379) and `.cancelled` handler (after line 349):

```swift
// In .cancelled handler, after the existing code:
await self.autoTitleIfNeeded()

// In .failed handler, after the existing code:
await self.autoTitleIfNeeded()
```

**Acceptance Criteria:**
1. Send a message - after response arrives, session title updates to a meaningful 3-6 word summary (not "New Chat")
2. If LLM title generation fails, title falls back to first-message truncation
3. If the response stream fails/cancels, the title still updates (from fallback path)
4. Existing titled sessions are not re-titled

---

### B3: Unreliable Responses / Needing Follow-Up Nudges (P0)

**Symptom:** Messages sometimes don't get responses. User has to send follow-up "nudge" messages. Sometimes still no response.

**Root Cause:** Multiple issues in the streaming pipeline:

1. **Watchdog fires with no recovery** (`ChatStore.swift:167-187`): The 120-second watchdog at line 389 fires when no progress events arrive. When it fires, `runAttemptLoop` sets `toolActivity = "Waiting for host..."` (line 185) but does NOT retry or call `failStalledMessage()`. The user is stuck forever in "Waiting for host..." state with no way to retry.

2. **`failStalledMessage` is dead code** (`ChatStore.swift:437-455`): This method exists and would show "Herald didn't respond - tap to retry", but it is NEVER CALLED from anywhere.

3. **No SSE reconnection on connection drop**: If the SSE connection between the iOS app and relay drops (network change, iOS backgrounding), no reconnection logic exists. The stream just stops yielding events, the watchdog fires after 120s, and the user sees "Waiting for host...".

4. **Host OOM freezes**: The host at 192.168.10.118 freezes multiple times per day from OOM. During a freeze, the connector cannot process jobs. The relay holds the job, but when the host recovers, the connector may have lost its WebSocket connection. If the relay's WebSocket to the connector drops, the job is orphaned.

**Files:**
- `Herald/Stores/ChatStore.swift:167-187` - `runAttemptLoop` (no retry after stall)
- `Herald/Stores/ChatStore.swift:389-410` - watchdog race
- `Herald/Stores/ChatStore.swift:437-455` - `failStalledMessage` (dead code)
- `Herald/Stores/ChatStore.swift:25` - `watchdogTimeout = 120` seconds

**Fix:**

**File: `Herald/Stores/ChatStore.swift`**

Replace `runAttemptLoop` (lines 167-187):

```swift
private func runAttemptLoop(
    content: String,
    attachments: [PendingAttachment],
    clientMessageID: UUID,
    placeholderID: UUID
) async {
    let stalled = await runStreamingAttempt(
        content: content,
        attachments: attachments,
        clientMessageID: clientMessageID,
        placeholderID: placeholderID
    )
    guard stalled else { return }

    // Watchdog fired. Show "Waiting for host..." for a grace period,
    // then fail the message with a tap-to-retry prompt.
    if let idx = conversation?.messages.firstIndex(where: { $0.id == placeholderID }) {
        conversation?.messages[idx].toolActivity = "Waiting for host..."
    }

    // Grace period: wait another 30s for a late response via polling
    try? await Task.sleep(for: .seconds(30))

    // Check if the message was answered during the grace period
    let refreshed = await refreshActiveConversation()
    conversation = mergeConversationMetadata(from: conversation, into: refreshed)
    if let msg = conversation?.messages.first(where: { $0.id == placeholderID }),
       msg.status == .delivered || !msg.content.isEmpty {
        // Response arrived during grace period
        return
    }

    // No response - fail with tap-to-retry
    failStalledMessage(clientMessageID: clientMessageID, placeholderID: placeholderID)
}
```

This wires up `failStalledMessage` so users see "Herald didn't respond - tap to retry" instead of being stuck on "Waiting for host..." forever.

**Acceptance Criteria:**
1. Send a message when the host is unresponsive - after ~150s (120 watchdog + 30 grace), the message shows "Herald didn't respond - tap to retry"
2. Tapping the failed message triggers `retryMessage` and resubmits
3. If the host responds during the 30s grace period, the response displays normally (no failure state)
4. Normal responses within the 120s watchdog are unaffected

---

### B4: Missing Push Notifications When Responses Arrive (P1)

**Symptom:** No notification appears when Herald finishes generating a response while the app is backgrounded. The user only knows a response arrived by opening the app.

**Root Cause:** The relay's `device_is_foreground()` check at `relay/app/services.py:856-859` uses a 120-second stale window (`APP_PRESENCE_STALE_SECONDS=120` in `.env`). This means if the app reported "foreground" within the last 2 minutes, the relay skips the push notification even though the user may have backgrounded the app moments ago.

Timeline:
1. User sends message (app reports "foreground")
2. User switches to another app (app reports "background" via `AppEntry.swift:141`)
3. Response arrives 30-90 seconds later
4. If "background" report was delayed or the response arrived before the foreground state expired, `device_is_foreground()` returns `true` and push is SKIPPED

The `reportAppStateIfNeeded("background")` at `AppEntry.swift:141` fires when `scenePhase == .background`, but this transition can be delayed if the app is performing background work. Also, the relay's `app-state` POST can fail silently (the function wraps everything in `try?`).

**Files:**
- `relay/app/services.py:856-859` - `device_is_foreground()` implementation
- `relay/app/config.py:61` - `app_presence_stale_seconds: int = 120`
- `deploy/hermes-relay/.env` - `APP_PRESENCE_STALE_SECONDS=120`
- `Herald/AppEntry.swift:137-148` - scene phase handler
- `Herald/Stores/AppContainer.swift:914-930` - `reportAppStateIfNeeded()`
- `relay/app/main.py:435-515` - `maybe_send_message_push()`

**Fix (three parts):**

**Part 1 - Reduce stale seconds**

**File: `deploy/hermes-relay/.env`**

Change:
```
APP_PRESENCE_STALE_SECONDS=120
```
to:
```
APP_PRESENCE_STALE_SECONDS=30
```

This reduces the window where a recently-foreground device is treated as still active. 30 seconds is generous enough for normal app-state reporting to propagate.

**Part 2 - Force push for slow responses**

**File: `relay/app/main.py`, in `maybe_send_message_push()` (~line 435)**

Add a `force` parameter that bypasses the foreground check when the response took a long time:

```python
async def maybe_send_message_push(
    *,
    db: Session,
    user_id: str,
    conversation_id: str,
    message_id: str,
    message_text: str,
    job_id: str | None = None,
    category: str | None = None,
    force: bool = False,
) -> None:
    # ...existing setup...
    for device, registration in active_push_registrations_for_user(db, user_id=user_id):
        if not force and device_is_foreground(device, stale_seconds=settings.app_presence_stale_seconds):
            logger.info("Skipping push for device %s (foreground)", device.id)
            continue
        # ...rest unchanged...
```

At the call site in the WebSocket job.result handler (~line 2896), calculate job duration and force push if >60 seconds:

```python
job_duration = (utcnow() - job.created_at).total_seconds() if job.created_at else 0
await maybe_send_message_push(
    db=sdb,
    user_id=user_id,
    conversation_id=job.session_id,
    message_id=str(job.message_id),
    message_text=response_text[:160],
    job_id=str(job.id),
    category="HERALD_MESSAGE_READY",
    force=(job_duration > 60),
)
```

**Part 3 - Ensure background state reports reliably**

**File: `Herald/Stores/AppContainer.swift:914-930`**

Add logging and ensure the state report fires immediately:

```swift
func reportAppStateIfNeeded(_ state: String) async {
    guard pairingStore.isPaired, let apiClient, let accessToken = await sessionStore.currentAccessToken() else {
        return
    }

    struct AppStateBody: Encodable {
        let state: String
    }
    struct AppStateResponse: Decodable {}

    do {
        _ = try await apiClient.post(
            path: "device/app-state",
            body: AppStateBody(state: state),
            accessToken: accessToken
        ) as AppStateResponse
    } catch {
        // Log but don't fail - push routing may be wrong but chat still works
    }
}
```

**Acceptance Criteria:**
1. Send a message, then immediately switch to another app
2. When the response arrives (within 30-120 seconds), a push notification appears
3. Tapping the notification opens Herald to the conversation
4. If the app is in the foreground when the response arrives quickly (<30s), no duplicate notification

---

### B5: Dynamic Island / Lock Screen Shows Logo Instead of Relevant Emoji (P1)

**Symptom:** When Herald is processing a request, the Dynamic Island and lock screen Live Activity show the Herald flame logo in the compact/minimal slots. The user expects a contextual emoji (brain for thinking, speech bubble for responding, etc.).

**Root Cause:** `HeraldLiveActivity.swift` always renders `HeraldBrandIcon` (the app icon) in every Dynamic Island position (lines 81, 105, 115). The `ContentState` struct in `HeraldActivityAttributes.swift` has no emoji field - only `status: String`, `toolName: String?`, `elapsedSeconds: Int`, `startDate: Date?`, `sessionType: String`.

**Files:**
- `HeraldWidgets/HeraldLiveActivity.swift:81,105,115` - `HeraldBrandIcon` in all positions
- `Herald/Models/HeraldActivityAttributes.swift:8-14` - `ContentState` (no emoji field)
- `Herald/Services/Live/LiveActivityService.swift` - phase updates (no emoji mapping)

**Fix:**

**Step 1: Add emoji to ContentState**

**File: `Herald/Models/HeraldActivityAttributes.swift`**

The `ContentState` struct is shared between the main app and widget extension. It MUST be updated in both copies:

```swift
struct ContentState: Codable, Hashable, Sendable {
    var status: String
    var toolName: String?
    var elapsedSeconds: Int
    var startDate: Date?
    var sessionType: String
    var emoji: String?           // Contextual emoji for Dynamic Island
}
```

Check if there's a duplicate of this file in `HeraldWidgets/`. If `HeraldActivityAttributes.swift` exists in both `Herald/Models/` and `HeraldWidgets/`, update BOTH. If the widget target imports it via the app target, only one file needs changing.

**Step 2: Map phases to emojis**

**File: `Herald/Services/Live/LiveActivityService.swift`**

Add an emoji mapping function and pass emoji in all state updates:

```swift
private func emojiForPhase(_ phase: String, sessionType: String) -> String {
    switch phase.lowercased() {
    case "thinking", "reasoning":
        return "\u{1F9E0}"    // brain
    case "responding", "streaming":
        return "\u{1F4AC}"    // speech bubble
    case "working", "executing":
        return "\u{26A1}"     // lightning
    case "listening":
        return "\u{1F3A4}"    // microphone
    case "searching", "browsing":
        return "\u{1F50D}"    // magnifying glass
    case "writing", "editing":
        return "\u{270F}\u{FE0F}"  // pencil
    default:
        switch sessionType {
        case "voice": return "\u{1F3A4}"
        case "tool":  return "\u{1F527}"
        default:      return "\u{1F4AC}"
        }
    }
}
```

Update all ContentState constructions in this file to include `emoji`:

```swift
// In startThinking():
let state = HeraldActivityAttributes.ContentState(
    status: "Thinking",
    toolName: nil,
    elapsedSeconds: 0,
    startDate: .now,
    sessionType: "chat",
    emoji: emojiForPhase("thinking", sessionType: "chat")
)

// Similarly for updatePhase(), startToolCall(), etc.
```

**Step 3: Render emoji in Dynamic Island**

**File: `HeraldWidgets/HeraldLiveActivity.swift`**

Replace the three `HeraldBrandIcon` usages:

**Line 105 (compactLeading):**
```swift
} compactLeading: {
    if let emoji = context.state.emoji {
        Text(emoji)
            .font(.system(size: 14))
    } else {
        HeraldBrandIcon(size: 14)
    }
}
```

**Line 115 (minimal):**
```swift
} minimal: {
    if let emoji = context.state.emoji {
        Text(emoji)
            .font(.system(size: 16))
    } else {
        HeraldBrandIcon(size: 16)
    }
}
```

**Line 81 (expanded leading) - keep the logo** in the expanded view since there's room for branding. Only replace compact and minimal.

**Lock screen (line 124):** Keep `HeraldBrandIcon` in the lock screen banner - it has room for both the logo and the status text. Alternatively, add the emoji next to the status:

```swift
Text("\(context.state.emoji ?? "") \(context.state.status)")
    .font(.subheadline)
    .italic()
    .foregroundStyle(.primary)
```

**Acceptance Criteria:**
1. Send a message - Dynamic Island compact view shows brain emoji during thinking, speech bubble during streaming response
2. Lock screen Live Activity banner shows contextual emoji alongside the status text
3. When no emoji is available (legacy state), falls back to Herald logo
4. Voice sessions show microphone emoji
5. Tool execution shows lightning/wrench emoji

---

### B6: Handwriting Cleanup Does Not Work Like Apple Notes (P2 - Deferred Feature)

**Symptom:** The handwriting experience on the PencilKit canvas doesn't clean up strokes in real-time like Apple Notes does (smoothing, straightening, Scribble text conversion).

**Root Cause:** This is a feature gap, not a bug. Herald uses basic `PKCanvasView` with:
- Raw ink strokes only (`PencilCanvasRepresentable.swift`)
- Batch OCR via `VNRecognizeTextRequest` on rasterized PNG (`VisionHandwritingRecognizer.swift`)
- No live stroke-to-text conversion
- No Scribble integration
- No shape recognition or stroke smoothing

Apple Notes achieves this through deep system integration (private APIs) and extensive stroke processing that is beyond the scope of a point release.

**Recommendation:** **Defer to v1.8.0 or later.** For v1.7.5, focus on the note selection bug (B1) which is the critical blocker. The handwriting experience with raw PencilKit is functional for drawing/sketching; it just doesn't convert handwriting to text live.

**If minimal improvement is desired for v1.7.5:**

**File: `Herald/Features/Notes/PencilCanvasRepresentable.swift`, line 22**

Enable the pencil-only drawing policy for a smoother feel:
```swift
canvas.drawingPolicy = .pencilOnly
```

This prevents finger drawing (which causes accidental marks) and lets the system's built-in palm rejection work better. Users can still use fingers for scrolling/zooming.

---

## Deployment Sequence

### Phase 1: iOS Code Changes (MBP, local)

Execute in order:

1. **B1** - `NotesWorkspaceView.swift:14` - add `.id(selectedId)` (1 line)
2. **B3** - `ChatStore.swift:566-581` - replace `autoTitleIfNeeded()` with LLM-backed version; add calls in `.cancelled` and `.failed` handlers
3. **B3** - Add `generateSessionTitle` to `HeraldClient` protocol + `LiveHeraldClient` implementation
4. **B3-fallback** - `ChatStore.swift` - improve fallback title + add error logging
5. **B5** - `HeraldActivityAttributes.swift` - add `emoji: String?` to `ContentState` (update ALL copies)
6. **B5** - `LiveActivityService.swift` - add `emojiForPhase()`, pass emoji in all state updates
7. **B5** - `HeraldLiveActivity.swift` - render emoji in compact/minimal Dynamic Island
8. **B3-response** - `ChatStore.swift:167-187` - replace `runAttemptLoop` with grace period + `failStalledMessage` wiring

### Phase 2: Version Bump (MBP)

**File: `project.yml`** - update in both Herald and HeraldWidgets targets:

```yaml
# Line 81-82 (Herald target):
MARKETING_VERSION: "1.7.5"
CURRENT_PROJECT_VERSION: "41"

# Line 141-142 (HeraldWidgets target):
MARKETING_VERSION: "1.7.5"
CURRENT_PROJECT_VERSION: "41"
```

Then run:
```bash
xcodegen generate
```

### Phase 3: Build and Test (MBP)

```bash
# Unlock keychain
security unlock-keychain -p "$(security find-generic-password -s 'login' -w)" ~/Library/Keychains/login.keychain-db

cd ~/Herald
xcodegen generate
xcodebuild -scheme Herald -configuration Debug -destination 'platform=iOS,name=Curtis iPad' build
```

Install on devices. Test B1 (note switching) and B5 (emoji in Dynamic Island) before proceeding to server deployment.

### Phase 4: Relay Changes (SSH to host)

```bash
ssh fihadmin@192.168.10.118

# Pull latest code
cd ~/Hermes-iOS
git fetch origin && git pull origin master

# Fix E1: Verify health endpoint works
curl -s http://localhost:8010/v1/health | jq .

# Fix E2: Verify Dockerfile has --log-level info
grep "log-level" relay/Dockerfile

# Copy updated relay to deploy dir
cp -r relay/app/* ~/deploy/hermes-relay/relay/app/
cp relay/pyproject.toml ~/deploy/hermes-relay/relay/
cp relay/Dockerfile ~/deploy/hermes-relay/relay/

# Fix B4: Update stale seconds
cd ~/deploy/hermes-relay
cp .env .env.backup.$(date +%s)
sed -i 's/APP_PRESENCE_STALE_SECONDS=120/APP_PRESENCE_STALE_SECONDS=30/' .env

# Rebuild and redeploy
docker compose build relay
docker compose up -d relay

# Verify
sleep 5
curl -s http://localhost:8010/v1/health | jq .
docker logs hermes-relay-relay-1 --tail 20
```

### Phase 5: Connector Changes (SSH to host)

```bash
# Still on fihadmin@192.168.10.118
cd ~/Hermes-iOS

# Verify B2 (title generation) connector changes
grep -c "generateTitle\|generate_title" connector/src/herald_connector/client.py
grep -c "generate_title\|complete" connector/src/herald_connector/herald_api_executor.py

# Restart connector (USER-LEVEL service, not sudo!)
systemctl --user restart hermes-mobile-connector.service
systemctl --user status hermes-mobile-connector.service
journalctl --user -u hermes-mobile-connector.service -n 20 --no-pager
```

### Phase 6: End-to-End Verification

| Test | Expected | Bug |
|------|----------|-----|
| Create new note, tap another note, tap back | Editor switches each time, shows correct content | B1 |
| Send chat message, wait for response | Session title updates to meaningful 3-6 word summary | B2 |
| Send message when host is slow/frozen | After ~150s shows "Herald didn't respond - tap to retry" | B3 |
| Tap failed message to retry | Message resubmits, response arrives | B3 |
| Send message, background the app, wait for response | Push notification appears | B4 |
| Watch Dynamic Island during thinking | Shows brain emoji, not Herald logo | B5 |
| Watch Dynamic Island during streaming | Shows speech bubble emoji | B5 |
| Relay health check | `curl http://localhost:8010/v1/health` returns 200 | E1 |
| Relay logs visible | `docker logs hermes-relay-relay-1` shows app-level logs | E2 |

### Phase 7: Commit and Tag

```bash
cd ~/Herald  # on MBP

# Stage changed files
git add Herald/Features/Notes/NotesWorkspaceView.swift \
        Herald/Stores/ChatStore.swift \
        Herald/Models/HeraldActivityAttributes.swift \
        Herald/Services/Live/LiveActivityService.swift \
        HeraldWidgets/HeraldLiveActivity.swift \
        Herald/Stores/AppContainer.swift \
        relay/Dockerfile \
        relay/app/main.py \
        connector/src/herald_connector/client.py \
        connector/src/herald_connector/runtime_adapter.py \
        connector/src/herald_connector/herald_api_executor.py \
        project.yml

git commit -m "fix: note selection, chat titles, response reliability, push notifications, status emoji (v1.7.5)"

git tag v1.7.5
git push origin master --tags
```

---

## Files Changed Summary

| File | Bug | Change |
|------|-----|--------|
| `Herald/Features/Notes/NotesWorkspaceView.swift` | B1 | Add `.id(selectedId)` to force editor recreation |
| `Herald/Stores/ChatStore.swift` | B2, B3 | LLM-backed autoTitle, call in failed/cancelled, wire failStalledMessage |
| `Herald/Models/HeraldActivityAttributes.swift` | B5 | Add `emoji: String?` to ContentState |
| `Herald/Services/Live/LiveActivityService.swift` | B5 | Phase-to-emoji mapping, pass emoji in all updates |
| `HeraldWidgets/HeraldLiveActivity.swift` | B5 | Render emoji in compact/minimal Dynamic Island |
| `Herald/Stores/AppContainer.swift` | B4 | Improve reportAppStateIfNeeded error handling |
| `relay/Dockerfile` | E2 | Add `--log-level info` to uvicorn CMD |
| `relay/app/main.py` | B2, B4 | generateTitle RPC proxy, force-push for slow responses |
| `connector/src/herald_connector/client.py` | B2 | session.generateTitle RPC handler |
| `connector/src/herald_connector/runtime_adapter.py` | B2 | generate_title() method |
| `connector/src/herald_connector/herald_api_executor.py` | B2 | complete() non-streaming method |
| `deploy/hermes-relay/.env` | B4 | APP_PRESENCE_STALE_SECONDS 120 -> 30 |
| `project.yml` | Version | 1.7.5 / build 41 |

---

## Risk Assessment

| Fix | Risk | Notes |
|-----|------|-------|
| B1 (note selection) | **Low** | Single `.id()` modifier, well-understood SwiftUI pattern |
| B2 (chat titles) | **Medium** | New RPC endpoint across all three tiers; test title generation latency |
| B3 (response reliability) | **Medium** | Changes streaming completion logic; grace period adds 30s before fail state |
| B4 (push notifications) | **Low** | Config change + additive force parameter; existing push infra unchanged |
| B5 (emoji) | **Low** | Additive field with nil fallback; widget must be rebuilt with matching ContentState |
| B6 (handwriting) | **Deferred** | Feature gap, not fixable in point release |
| E1 (health endpoint) | **Zero** | Documentation/script fix only |
| E2 (relay logging) | **Low** | One Dockerfile flag |

---

## Known Constraints

- **Host OOM freezes:** The host at 192.168.10.118 freezes multiple times daily. This means the connector becomes unresponsive during freezes, and jobs that were in-flight are orphaned. The B3 fix (failStalledMessage) addresses the client-side experience but doesn't prevent the underlying job loss. A cgroup `MemoryMax` fix is in progress separately.

- **HeraldActivityAttributes duplication:** The `ContentState` struct must match byte-for-byte between the main app target and the widget extension target. If these files are separate copies, both MUST be updated. A mismatch will cause Live Activity updates to silently fail.

- **Relay no-migration constraint:** The relay uses Postgres without a migration framework. Any schema changes require manual `ALTER TABLE` statements run directly against the database. The v1.7.5 changes do NOT require schema changes.
