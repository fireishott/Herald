# Mimo Marching Orders - Herald v1.7.7 Point Release

**Date:** 2026-07-21
**Current version:** 1.7.5 / build 41 (HEAD `3804d82`, commit message says v1.7.6 but project.yml not bumped)
**Target version:** 1.7.7 / build 43
**Branch:** `master`
**Remote:** `origin` = `https://github.com/fireishott/Herald.git`

---

## Cross-Cutting Rules (apply to EVERY change)

1. Bump `MARKETING_VERSION` to `1.7.7` and `CURRENT_PROJECT_VERSION` to `43` in `project.yml` (lines 81-82 AND 141-142)
2. One change = one commit = one dated CHANGELOG entry
3. Relay has **no migration framework** - ship manual `ALTER`s if schema changes
4. Swift 6 strict concurrency must stay clean (`SWIFT_STRICT_CONCURRENCY: complete`)
5. Unlock login keychain before EVERY `xcodebuild`
6. Run `xcodegen generate` after editing `project.yml`
7. Deploy relay by copying from `~/Hermes-iOS/relay/` to `~/deploy/hermes-relay/relay/` then `docker compose up -d --build`
8. Connector is a **user-level** systemd service: `systemctl --user restart hermes-mobile-connector.service`

---

## Environment Block

| Thing | Value |
|------|-------|
| **App repo** | `/Users/curtisfreeman/Herald` (git; branch `master`) |
| **iOS app** | `Herald/` target, Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, iOS 18.0+ |
| **Widgets** | `HeraldWidgets/` extension, App Group `group.net.fihonline.herald` |
| **Relay** | `relay/` FastAPI + Postgres; host `192.168.10.118:8010`; health at `/v1/health` |
| **Connector** | `connector/src/herald_connector/`; Python WS client; user-level systemd `hermes-mobile-connector.service` |
| **Hermes host** | `fih-ai-host` @ `192.168.10.118`; api_server on port 8642 |
| **Build machine** | MacBook Pro @ `curtisfreeman@192.168.10.121` |
| **Project gen** | XcodeGen - edit `project.yml`, run `xcodegen generate` |
| **Bundle / team** | `net.fihonline.herald` / `58U7UPFS53` |
| **Deploy dir** | `/home/fihadmin/deploy/hermes-relay` (NOT a git repo - files copied from checkout) |
| **GitHub remote** | `https://github.com/fireishott/Herald.git` |

---

## v1.7.6 Deployment Status (MUST DO FIRST)

v1.7.6 commit `3804d82` fixed critical relay bugs (terminal event persistence, SSE Phase 2 loop) but **project.yml was never bumped** and the relay changes may not be deployed. Before starting v1.7.7 work:

1. **Verify relay deployment**: SSH to host, check if `relay/app/main.py` has the `append_job_event` fix for `done` events (grep for `"Persist terminal event"` in the container's `/app/app/main.py`)
2. If not deployed: copy relay from `~/Hermes-iOS/relay/` to deploy dir, rebuild container
3. Restart connector: `systemctl --user restart hermes-mobile-connector.service`
4. Verify SSE flow: send a simple chat message, check relay logs for `job.started` -> `job.progress` -> `job.result` sequence and iOS receiving the `done` event

---

## Bug Fixes

### B1: Multi-Turn/Multi-Tool Streaming Failures (P0-CRITICAL)

**Symptom:** Sending messages that trigger tool calls or multi-turn reasoning (common with DeepSeek, Mimo models) results in "HERALD DIDN'T RESPOND - TAP TO RETRY" after ~150 seconds. Hermes API server logs show the full response completing successfully with tool calls and multi-turn iterations. The response is generated but never reaches the iOS app.

**Architecture context (from Hermes Agent deep-dive):**

The Hermes Desktop Electron app uses a rich JSON-RPC WebSocket protocol with discrete event types (`message.start`, `message.delta`, `tool.start`, `tool.complete`, `message.complete`). Herald's connector instead uses the simpler OpenAI-compatible `/v1/chat/completions` SSE endpoint. During multi-tool agent loops, the Hermes API server keeps the SSE stream open and sends `:` keepalive comments every 30 seconds while tools execute. The connector emits `job.heartbeat` every 10 seconds independently.

**Root cause analysis - three issues in the chain:**

**Issue 1: Relay terminal event persistence (FIXED in v1.7.6, VERIFY DEPLOYED)**

`relay/app/main.py` - `append_job_event()` was not persisting `done` events when the job was already in terminal status, and the SSE Phase 2 loop was not breaking on `done` events. Fix committed in `3804d82` but relay may not be redeployed.

**Verification:** `grep -n "Persist terminal event\|break.*done" /home/fihadmin/deploy/hermes-relay/relay/app/main.py` on the host. If not present, redeploy.

**Issue 2: Terminal event message extraction drops the response text**

**File:** `Herald/Services/Live/JobStreamCoordinator.swift:254-256`

The relay's terminal `done` event sends the message as a serialized dict:
```python
terminal_payload["message"] = serialize_message(result_msg, job=job_row)  # dict, NOT string
```

But the coordinator tries to extract it as a plain string:
```swift
case "done":
    let text = json["message"] as? String ?? json["text"] as? String ?? ""
```

`json["message"] as? String` fails (it's a dict), `json["text"]` is nil, so `text` = `""`. The terminal result arrives with empty content.

**Fix:**

**File: `Herald/Services/Live/JobStreamCoordinator.swift`, line 255**

Replace:
```swift
let text = json["message"] as? String ?? json["text"] as? String ?? ""
```
With:
```swift
let text: String
if let messageDict = json["message"] as? [String: Any] {
    text = messageDict["content"] as? String ?? messageDict["text"] as? String ?? ""
} else {
    text = json["message"] as? String ?? json["text"] as? String ?? ""
}
```

**Issue 3: Connector keepalive gaps during tool execution**

**File:** `connector/src/herald_connector/herald_api_executor.py:325-403`

During multi-turn tool execution, the Hermes API server sends SSE `:` keepalive comments (line 329-331 skips these). The connector only yields `StreamEvent(type="keepalive")` when a DATA chunk arrives with no user-visible content (line 402-403). During long tool runs, the only thing on the wire may be `:` comments for extended periods.

**Fix - emit keepalive StreamEvents for SSE comments:**

**File: `connector/src/herald_connector/herald_api_executor.py`, after line 331**

Currently:
```python
if line.startswith(":"):
    # SSE comment (keepalive), skip
    continue
```

Change to:
```python
if line.startswith(":"):
    yield StreamEvent(type="keepalive")
    continue
```

**Acceptance Criteria:**
1. Send a message that triggers tool calls - response should stream through with tool activity labels, then final text
2. Multi-turn sequences (model thinks -> calls tools -> thinks again -> responds) should complete without watchdog timeout
3. The response text should not be empty when the terminal event arrives

---

### B2: iPad Model Picker Does Not Show Active Model (P1)

**Symptom:** iPhone toolbar shows "mimo-v2.5" with green dot. iPad toolbar shows only green dot and context ring, no model name text.

**Root cause:** `displayedModelName` (`ChatScreen.swift:291`) returns nil when `ModelStore.loadModels()` hasn't completed on iPad.

```swift
modelStore.activeModel?.name ?? chatStore.activeModelName ?? hostStore.currentHost?.heraldModel
```

**Fix (two parts):**

**Part A - Ensure ModelStore loads eagerly** in `ChatScreen.swift`. Verify `.task` calls `modelStore.loadModels()` without platform guard. Add one if missing.

**Part B - Show placeholder when model name is nil** in `modelStatusChip` (line 386) and `compactStatusControl` (line 260):
```swift
} else {
    Text("...")
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(Design.Colors.secondaryForeground)
        .lineLimit(1)
}
```

**Acceptance Criteria:**
1. iPad shows the active model name in the toolbar (same as iPhone)
2. If model hasn't loaded yet, "..." placeholder is visible

---

### B3: "HERALD didn't respond" Should Show Active Profile Name (P1)

**File:** `Herald/Stores/ChatStore.swift:453`

```swift
let errorText = "Herald didn't respond -- tap to retry"
```

**Fix:**
```swift
let profileName = profileStore?.activeProfile?.name ?? "Herald"
let errorText = "\(profileName) didn't respond -- tap to retry"
```

`profileStore` is already available on `ChatStore` (line 60).

---

### B4: Chat Session Naming Still Inconsistent (P1)

**Symptom:** Some sessions stay "New Chat" instead of getting LLM-generated titles.

**Root cause:** `autoTitleIfNeeded()` at `ChatStore.swift:581-611` uses `try?` to silently swallow title generation RPC failures. The generate-title RPC competes for the LLM with the in-flight job.

**Fix:**

**File: `Herald/Stores/ChatStore.swift`, replace `autoTitleIfNeeded()`**

Key changes:
- 2-second delay before hitting the LLM (lets the runtime recover)
- Validate generated title isn't blank
- Fallback always applies locally first (instant UI update), persists to server in background

**File: `connector/src/herald_connector/client.py`, in `_rpc_session_generate_title` (~line 1880)**

Add logging and a 30-second timeout around the runtime call.

---

### B5: Remove "Managed Relay" Connection Mode (P1)

**Symptom:** Onboarding ENDPOINT screen shows "Managed Relay" as the first option. There is no managed relay service.

**Scope:** Remove `.managedRelay` from `RelayConnectionMode` enum. Add backward-compatible decoder that maps old `"managedRelay"` raw value to `.selfHostedRelay`.

**Files to change:**

| File | What |
|------|------|
| `Herald/Models/UserSettings.swift` | Remove `case managedRelay`, all switch cases, `canUseHosted`, `hostedRelayBaseURL` logic. Add `init(from decoder:)` mapping `"managedRelay"` -> `.selfHostedRelay` |
| `Herald/Features/Chat/ChatScreen.swift:698-699` | Remove `.managedRelay` from `connectionBannerTitle` |
| `Herald/Features/Onboarding/OnboardingFlowView.swift` | Remove managed relay URL match, display, and cases |
| `Herald/Features/Settings/SettingsScreen.swift` | Remove hosted relay URL display and `.managedRelay` cases |

**Acceptance Criteria:**
1. Onboarding shows only Tailscale + Self-Hosted Relay
2. Self-Hosted Relay selected by default
3. Existing `managedRelay` settings migrate gracefully

---

### B6: Health Permissions Bug Regression (P2)

**Symptom:** Health permissions "bug is back." HealthKit authorization not working.

**Root cause (TestFlight builds):** Build script strips ALL entitlements including `com.apple.developer.healthkit*`. Without the entitlement, `requestAuthorization` fails silently. This is by design for TestFlight/App Store builds (paid team profiles lack these capabilities) but means HealthKit never works on TestFlight.

**Root cause (sideloaded builds):** `UserDefaults` flag `herald.healthkit.authorizationRequested` (`LiveHealthService.swift:38`) can be lost on reinstall. Apple returns `.notDetermined` for read-access status regardless of actual grant state.

**Fix:** Add a live probe in `refreshAuthorizationStatus()` (`LiveHealthService.swift:~100`) that tries a single step-count query to detect prior authorization even when the UserDefaults flag is missing:

```swift
if !previouslyRequested {
    let probeType = HKQuantityType(.stepCount)
    let descriptor = HKSampleQueryDescriptor(
        predicates: [.quantitySample(type: probeType)],
        sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
        limit: 1
    )
    if let _ = try? await descriptor.result(for: store) {
        authorizationStatus = .authorized
        UserDefaults.standard.set(true, forKey: Self.healthAuthRequestedKey)
        return
    }
}
```

**Note:** TestFlight builds will ALWAYS lack HealthKit due to entitlement stripping. This is a known limitation documented in the build pipeline. Consider adding a UI indicator when the entitlement is missing.

---

### B7: Push Notifications Not Delivering (P0-CRITICAL)

**Symptom:** No push notifications arrive on iPhone or iPad. Tested "send push to my ipad" - no response, no notification. Both devices' push registrations are deactivated in the DB after APNs returned `TOKEN_INVALID` (410 Gone).

**Root cause analysis - three issues:**

**Issue 1: APNs environment mismatch**

**File:** `/home/fihadmin/deploy/hermes-relay/.env`

The relay has `APNS_ENVIRONMENT=production` but sideloaded Xcode builds always receive **development** APNs sandbox tokens from iOS. The relay's `register_push` endpoint (`main.py:1816`) overrides the app-reported environment:

```python
push_environment=settings.apns_environment,  # Override: use relay env, not app-reported
```

When this was `production`, development tokens were sent to the production APNs gateway, which rejected them.

The DB currently shows `push_environment = 'development'` (registrations were created when the env was previously set to `development`). But the tokens themselves are stale (app was reinstalled since July 20).

**Fix:** Change `/home/fihadmin/deploy/hermes-relay/.env`:
```
APNS_ENVIRONMENT=development
```
Then `docker compose up -d --build` to restart relay.

**When shipping to TestFlight:** Change back to `APNS_ENVIRONMENT=production` since TestFlight builds get production APNs tokens.

**Issue 2: Both push registrations permanently deactivated**

After APNs returned 410, relay correctly set `is_active = false` (`main.py:1966-1969`). But the app's re-registration logic (`AppContainer.swift:685-688`) short-circuits when the token hasn't changed:

```swift
if notificationService.isPushTokenRegistered,
   notificationService.currentPushToken == normalizedToken {
    sessionStore.state.pushTokenRegistered = true
    return
}
```

If iOS returns the same token and local state says "registered", the app never re-registers with the relay, even though the relay has it as inactive.

**Fix (two parts):**

**Part A - Immediate:** Reactivate registrations in DB:
```sql
UPDATE push_registrations SET is_active = true, updated_at = NOW();
```
Then open Herald on both devices to trigger fresh token registration.

**Part B - Code fix in `AppContainer.swift:685-688`:** Add a periodic re-registration check. After the short-circuit, verify with the relay that the registration is still active. Or simpler: remove the short-circuit and always POST the token - the relay's `upsert_push_registration` is idempotent.

```swift
// Remove the short-circuit. Always re-register to ensure relay-side
// registration is active (relay may have deactivated on 410).
```

**Issue 3: No logging for APNs failures**

The relay's `/v1/push/send` endpoint returns `{"sent": 0}` with no detail about why. The `_send` method in `apns.py` logs to `herald.relay.apns` but these may not surface in `docker logs`.

**Fix:** Add explicit logging in `maybe_send_message_push` (`main.py:486-502`) for the PushResult:
```python
logger.info("APNs push to %s result=%s env=%s", device.id, result.value, registration.push_environment)
```

**Acceptance Criteria:**
1. Open Herald on iPad - push token re-registers as active
2. Send a message that takes >60s - push notification arrives on both devices
3. Lock screen shows the notification with "Herald" title and message preview
4. Notification tap opens the correct conversation

---

### B8: No Lock Screen Notifications / No Notifications Upon Response (P1)

**Symptom:** No notifications when Herald responds, neither on lock screen nor as banners.

**Root cause:** This is downstream of B7. Push registrations are inactive so `maybe_send_message_push` (`main.py:455`) iterates zero devices:

```python
for device, registration in active_push_registrations_for_user(db, user_id=user_id):
```

With no active registrations, this loop body never executes. No APNs push is sent, no inbox item is created.

**Additional check:** The `force` parameter on `maybe_send_message_push` (line 2942) is `True` only when `job_duration > 60`. For fast responses (<60s), the foreground check (`device_is_foreground`, line 456) may skip push if the device recently reported foreground. `APP_PRESENCE_STALE_SECONDS=30` in `.env` means the device is considered foreground for 30s after the last state report.

**Fix:** Fixing B7 (re-activating push registrations + fixing APNS_ENVIRONMENT) should resolve this entirely. The notification categories (`HERALD_MESSAGE_READY`, `HERALD_JOB_ACTIVE`) and actions (Read, Reply, Nudge, Stop) are already properly registered in `LiveNotificationService.swift`.

**Verification after B7 fix:**
1. Background the app, send a message via another device - notification should arrive
2. Lock the device, wait for response - lock screen notification should appear
3. Notification actions (Reply, Nudge, Stop) should work

---

### B9: Streaming Toggle in Settings (P2)

**Symptom:** User wants a toggle in Settings to disable streaming and use synchronous request/response instead.

**Implementation:**

**File: `Herald/Models/UserSettings.swift`**

Add a new setting:
```swift
var streamingEnabled: Bool = true
```

Add to the `CodingKeys` enum and both `init(from decoder:)` and `encode(to:)`.

**File: `Herald/Features/Settings/SettingsScreen.swift`**

Add a toggle in the appropriate section:
```swift
Toggle("Stream responses", isOn: $settingsStore.settings.streamingEnabled)
```

**File: `Herald/Services/Live/LiveHeraldClient.swift`**

When `streamingEnabled == false`, use the non-streaming path: POST message, poll for completion via `GET /v1/jobs/{jobId}`, then fetch the result message. The relay already supports this - `replyState: "delivered"` with inline result means no SSE needed.

**Acceptance Criteria:**
1. Settings shows a "Stream responses" toggle (default: on)
2. When off, messages still send and receive but without live typing animation
3. When off, tool activity labels are not shown during processing
4. Toggle state persists across app launches

---

### B10: App Crashes When Enabling Speech Recognition (P1)

**Symptom:** App crashes when enabling speech recognition in permissions.

**Root cause:** `LiveSpeechService.swift:12` is marked `@available(iOS 26.0, *)` because it uses the modern `DictationController` API. If any call site doesn't check `@available(iOS 26.0, *)` before accessing this service, the app crashes on iOS 18/25.

**Investigation:**

1. Check `PermissionsStore.swift:140` - `requestSpeechAuthorization()` uses `SFSpeechRecognizer.requestAuthorization` callback. If this creates or touches a `LiveSpeechService` instance without the availability check, crash.
2. Search for all references to `LiveSpeechService` or `speechService` in the codebase - every access must be behind `if #available(iOS 26.0, *)`.
3. Check `AppContainer.swift` for where `LiveSpeechService` is constructed - the construction itself must be availability-guarded.

**Fix:** Wrap every access to `LiveSpeechService` in `if #available(iOS 26.0, *)` checks. If the current deployment target is iOS 18.0, provide a fallback using `SFSpeechRecognizer` (the older API that works on iOS 18+).

**Acceptance Criteria:**
1. Tapping "Enable" on Speech permission card does not crash
2. If iOS 26+: modern speech recognition works
3. If iOS 18-25: graceful fallback or "not available" message

---

### B11: Motion/Activity Permission Resets Every Time Permissions Opens (P2)

**Symptom:** Motion and activity permission needs to be toggled every time the permissions screen opens.

**Root cause:** `LiveMotionService.swift:59` recomputes `authorizationStatus` from `CMMotionActivityManager.authorizationStatus()` each time. This static method returns the system-level auth status correctly, BUT `requestAuthorization()` (line 69-77) triggers the permission dialog via `queryActivityStarting` every time it's called - it has a suspicious double `to:` parameter that may be silently failing.

The real issue: `PermissionsStore.swift` calls `requestPermission()` -> `motionService.requestAuthorization()` each time the permissions screen renders the motion card, not just when the user taps "Enable". The permissions screen likely re-evaluates capabilities on appear, calling request instead of just checking status.

**Fix:**

**File: `Herald/Stores/PermissionsStore.swift`**

Separate "check status" from "request permission". The permissions screen should only call `checkStatus()` on appear, and only call `requestPermission()` when the user explicitly taps.

**File: `Herald/Services/Live/LiveMotionService.swift`**

In `requestAuthorization()`, check if already authorized before triggering the query:
```swift
func requestAuthorization() async {
    let status = CMMotionActivityManager.authorizationStatus()
    if status == .authorized {
        authorizationStatus = .authorized
        return
    }
    // Only trigger the permission dialog if not yet determined
    guard status == .notDetermined else {
        authorizationStatus = status == .denied ? .denied : .restricted
        return
    }
    // ... existing queryActivityStarting code
}
```

---

### B12: App Crashes on "Start Talking" in Talk Mode (P1)

**Symptom:** App crashes when hitting "Start Talking" button in Talk mode.

**Root cause:** `TalkStore.startSession()` (`TalkStore.swift:156`) requires `hermesCoordinator` to be non-nil. If the coordinator wasn't attached (e.g., API key missing, MiMo service initialization failed, or `AppContainer` didn't call `attachHermesCoordinator()`), accessing it causes a crash.

**Investigation:**

1. Check `TalkStore.refreshReadiness()` (line 131) - does it set `blockedReason` when coordinator is nil, and does the UI respect it?
2. Check `TalkModeScreen.swift:116-129` - is the "Start Talking" button disabled when `!talkStore.canStartSession`?
3. Check `AppContainer.swift` for `attachHermesCoordinator()` call - is it conditional on MiMo API key being set?

**Fix:** Ensure `startSession()` has a guard for nil coordinator:
```swift
func startSession() async {
    guard let coordinator = hermesCoordinator else {
        blockedReason = "Talk coordinator not available. Check MiMo API key in Settings."
        return
    }
    // ... rest of session start
}
```

Also ensure the UI disables the button with a clear message when the coordinator is unavailable.

---

### B13: Action Center Not Working (P2)

**Symptom:** "Action center stuff not working" - specifics unclear.

**Investigation needed:**
1. Identify what "action center" refers to - likely the inbox/notification center tab, or the iPad right panel's activity feed
2. Check `InboxStore` and related views for data loading issues
3. Check if the relay's inbox item creation (`create_inbox_item` in `main.py:504-516`) is working
4. Verify the `GET /v1/inbox` endpoint returns data

**Note:** This may be partially resolved by B7/B8 fixes since inbox items are created alongside push notifications in `maybe_send_message_push`.

---

## Backlog (v1.8)

### Notes Features

Notes features are backburnered for v1.8. No notes work in this release.

---

## Commit Order

| Order | Fix | Component | Deploy |
|-------|-----|-----------|--------|
| 0 | Verify v1.7.6 relay is deployed | Relay | Redeploy if needed |
| 1 | B7: Fix APNS_ENVIRONMENT + reactivate push registrations | Relay `.env` + DB | Relay restart |
| 2 | B7: Remove push re-registration short-circuit | iOS (`AppContainer.swift`) | App rebuild |
| 3 | B1: Terminal event message extraction | iOS (`JobStreamCoordinator.swift`) | App rebuild |
| 4 | B1: Connector keepalive for SSE comments | Connector (`herald_api_executor.py`) | Connector restart |
| 5 | B2: iPad model picker | iOS (`ChatScreen.swift`) | App rebuild |
| 6 | B3: Profile name in error message | iOS (`ChatStore.swift`) | App rebuild |
| 7 | B4: Chat naming reliability | iOS (`ChatStore.swift`) + Connector (`client.py`) | App rebuild + connector restart |
| 8 | B5: Remove Managed Relay | iOS (`UserSettings.swift`, `ChatScreen.swift`, `OnboardingFlowView.swift`, `SettingsScreen.swift`) | App rebuild |
| 9 | B6: Health permissions probe | iOS (`LiveHealthService.swift`) | App rebuild |
| 10 | B9: Streaming toggle | iOS (`UserSettings.swift`, `SettingsScreen.swift`, `LiveHeraldClient.swift`) | App rebuild |
| 11 | B10: Speech recognition availability guard | iOS (`LiveSpeechService.swift`, `PermissionsStore.swift`, `AppContainer.swift`) | App rebuild |
| 12 | B11: Motion permission check vs request separation | iOS (`LiveMotionService.swift`, `PermissionsStore.swift`) | App rebuild |
| 13 | B12: Talk mode nil coordinator guard | iOS (`TalkStore.swift`) | App rebuild |
| 14 | B13: Action center investigation | TBD | TBD |
| 15 | Version bump to 1.7.7 / build 43 | `project.yml` | xcodegen + build |

---

## CHANGELOG Entry (append to CHANGELOG.md)

After all fixes land, add this block at the top of `CHANGELOG.md` (after the `# Changelog` header, before `## [1.7.5]`):

```markdown
## [1.7.7] - 2026-07-XX

### Fix: Streaming failures on multi-tool prompts (B1)

- **Terminal event text extraction** (`JobStreamCoordinator.swift`): Relay sends `message` as a serialized dict, not a String. Fixed `parseEnvelope` to extract `content` from the message dict instead of casting to String (which silently returned empty text).
- **Connector keepalive for SSE comments** (`herald_api_executor.py`): SSE `:` keepalive comments from the Hermes API server now emit `StreamEvent(type="keepalive")` instead of being silently skipped. Prevents watchdog timeout during long tool execution windows.

### Fix: Push notifications not delivering (B7/B8)

- **APNs environment fix** (deploy `.env`): Changed `APNS_ENVIRONMENT` from `production` to `development` to match sideloaded Xcode builds. Development APNs tokens sent to the production gateway were rejected with 410 Gone.
- **Push re-registration** (`AppContainer.swift`): Removed the short-circuit that skipped re-registration when the local token matched. The relay may have deactivated the registration (e.g., after a 410), so always POST the token.
- **Push result logging** (`main.py`): Added explicit logging for APNs push results including environment and device ID.

### Fix: iPad model picker empty (B2)

- **Eager ModelStore load** (`ChatScreen.swift`): Ensured `ModelStore.loadModels()` fires on iPad without platform guard.
- **Placeholder chip** (`ChatScreen.swift`): Model status chip shows "..." when model name hasn't loaded yet, instead of rendering empty.

### Fix: Error message shows profile name (B3)

- **Profile-aware error** (`ChatStore.swift`): "Herald didn't respond" now reads "ignyte didn't respond" (or active profile name). Falls back to "Herald" when no profile is active.

### Fix: Chat session naming reliability (B4)

- **Delayed title generation** (`ChatStore.swift`): 2-second delay before LLM title request lets the runtime finish cleanup. Validates generated title isn't blank before applying.
- **Title generation timeout** (`client.py`): 30-second independent timeout for the generate-title RPC, with logging.

### Fix: Remove Managed Relay connection mode (B5)

- **Removed `.managedRelay`** (`UserSettings.swift`): Enum case removed. Backward-compatible decoder maps old `"managedRelay"` to `.selfHostedRelay`. All switch statements, `canUseHosted` property, and hosted relay URL logic removed.
- **Onboarding** (`OnboardingFlowView.swift`): ENDPOINT screen shows only Tailscale and Self-Hosted Relay.
- **Settings** (`SettingsScreen.swift`): Removed hosted relay URL display.

### Fix: Health permissions detection (B6)

- **Live authorization probe** (`LiveHealthService.swift`): When the UserDefaults flag is missing (e.g., after reinstall), probes HealthKit with a single step-count query to detect prior authorization.

### Fix: Streaming toggle (B9)

- **Settings toggle** (`UserSettings.swift`, `SettingsScreen.swift`): New "Stream responses" toggle (default: on). When off, messages use synchronous request/response without live typing animation.

### Fix: Speech recognition crash (B10)

- **Availability guard** (`LiveSpeechService.swift`, `PermissionsStore.swift`): All access to `LiveSpeechService` (iOS 26+) wrapped in `#available` checks. Prevents crash on iOS 18-25.

### Fix: Motion permission resets on every screen open (B11)

- **Separated check from request** (`LiveMotionService.swift`, `PermissionsStore.swift`): Permissions screen now checks status on appear without re-triggering the authorization dialog. Only requests permission on explicit user tap.

### Fix: Talk mode crash on Start Talking (B12)

- **Nil coordinator guard** (`TalkStore.swift`): `startSession()` guards for nil `hermesCoordinator` and sets a visible `blockedReason` instead of crashing.
```

Also add `## [1.7.6] - 2026-07-21` between v1.7.7 and v1.7.5 for the already-committed fixes:

```markdown
## [1.7.6] - 2026-07-21

### Fix: Streaming terminal events and push APNs bundle

- **Terminal event persistence** (`relay/app/main.py`): `append_job_event` now persists `done` events when job is in terminal status. SSE Phase 2 loop breaks on `done` events.
- **APNs bundle ID** (`relay/app/main.py`): Push registration now uses correct bundle ID from device registration.
- **SSE diagnostics** (`relay/app/main.py`): Added diagnostic logging for SSE event flow.

### Fix: Chat title sender check

- **Sender mismatch** (`ChatStore.swift`): `autoTitleIfNeeded` now checks `.herald` sender instead of `.assistant` when extracting assistant content for title generation.
```

---

## GitHub Release & Tag Procedure

After all commits land and TestFlight build is uploaded:

### 1. Tag the release

```bash
cd /Users/curtisfreeman/Herald
git tag -a v1.7.7 -m "Herald v1.7.7 - streaming fixes, push notifications, UI polish"
git push origin v1.7.7
```

Also tag v1.7.6 retroactively on its commit:

```bash
git tag -a v1.7.6 3804d82 -m "Herald v1.7.6 - terminal event persistence, APNs bundle fix"
git push origin v1.7.6
```

### 2. Push all commits

```bash
git push origin master
```

### 3. Authenticate GitHub CLI (if not already)

```bash
gh auth login
```

### 4. Create GitHub releases

**v1.7.6 (retroactive):**

```bash
gh release create v1.7.6 \
  --title "Herald v1.7.6" \
  --notes "$(cat <<'EOF'
## Fix: Streaming Terminal Events & Push APNs Bundle

- Terminal event persistence: `append_job_event` now persists `done` events when job is terminal
- SSE Phase 2 loop breaks on `done` events instead of hanging
- Push registration uses correct bundle ID from device registration
- Chat title generation now checks `.herald` sender (not `.assistant`)

**Full Changelog:** See CHANGELOG.md
EOF
)" \
  --target 3804d82
```

**v1.7.7:**

```bash
gh release create v1.7.7 \
  --title "Herald v1.7.7" \
  --notes "$(cat <<'EOF'
## Herald v1.7.7 - Streaming, Push Notifications, UI Polish

### Critical Fixes
- **Multi-tool streaming** (B1): Fixed terminal event text extraction (relay sends dict, not String) and connector keepalive gaps during tool execution
- **Push notifications** (B7/B8): Fixed APNs environment mismatch, push re-registration short-circuit, and added push result logging

### UI & UX
- **iPad model picker** (B2): Model name now shows in iPad toolbar
- **Profile-aware errors** (B3): "ignyte didn't respond" instead of "Herald didn't respond"
- **Chat titles** (B4): More reliable LLM title generation with timeout and delay
- **Removed Managed Relay** (B5): Onboarding shows only Tailscale + Self-Hosted Relay
- **Streaming toggle** (B9): New Settings toggle to disable streaming

### Stability
- **Health permissions** (B6): Live probe detects prior authorization after reinstall
- **Speech recognition** (B10): iOS 26 availability guard prevents crash on iOS 18-25
- **Motion permissions** (B11): No longer re-triggers dialog on every screen open
- **Talk mode** (B12): Nil coordinator guard prevents crash

**Full Changelog:** See CHANGELOG.md
EOF
)"
```

### 5. Verify releases

```bash
gh release list --limit 5
gh release view v1.7.7
```

---

## TestFlight Build Procedure

See memory file `herald-testflight-procedure.md` for full keys, IDs, and pipeline.

**Summary:**

1. Bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `project.yml` (4 instances total - 2 per target)
2. Run `xcodegen generate`
3. SSH to MBP, one call: unlock keychain -> strip entitlements -> archive -> export IPA -> restore entitlements
4. Upload via `xcrun altool --upload-app` using ASC upload key `32NT26772F`
5. Verify processing via ASC API using admin key `UQWH2GWTLU` - wait for `[VALID]`
6. **IMPORTANT:** Before TestFlight upload, change relay `APNS_ENVIRONMENT=production` since TestFlight builds get production APNs tokens

**Critical rules:**
- One SSH call for archive + export (keychain re-locks between sessions)
- Strip entitlements before build, restore after (TestFlight lacks HealthKit/App Groups)
- Don't use APNs key (`LH5GM8356P`) for upload
- Don't set `CODE_SIGN_IDENTITY` with automatic signing

---

## Post-Ship Verification Checklist

- [ ] Send a tool-using prompt on iPhone - full response arrives with tool activity labels
- [ ] Send a tool-using prompt on iPad - same result
- [ ] iPad toolbar shows active model name
- [ ] Error message shows profile name ("ignyte didn't respond")
- [ ] Three new chat sessions all get LLM-generated titles (not "New Chat")
- [ ] Onboarding shows only Tailscale + Self-Hosted Relay (no Managed)
- [ ] Health permission grant works from Permissions screen
- [ ] Health permission state persists across app relaunch
- [ ] Push notification arrives on iPhone when app is backgrounded
- [ ] Push notification arrives on iPad when app is backgrounded
- [ ] Lock screen notification shows with Reply/Nudge/Stop actions
- [ ] Notification tap opens correct conversation
- [ ] Streaming toggle in Settings disables live typing animation
- [ ] Speech recognition permission doesn't crash
- [ ] Motion permission doesn't re-trigger dialog on screen reopen
- [ ] "Start Talking" doesn't crash (shows error if coordinator unavailable)
- [ ] GitHub tags v1.7.6 and v1.7.7 exist
- [ ] GitHub releases created with release notes
- [ ] CHANGELOG.md updated with v1.7.6 and v1.7.7 entries
