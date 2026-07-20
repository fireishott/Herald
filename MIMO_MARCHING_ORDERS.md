# Herald — Marching Orders for Mimo

**Author:** assessment pass (no code changed). **Target build:** next after build 13.
**Scope:** 8 defects/features reported from device. Each item below is grounded in the
actual source so you can go straight to the fix. Do NOT start coding until you've read
the "Ground rules" section — especially the versioning/changelog mandate.

---

## Ground rules (apply to EVERY change in this doc)

1. **Version + changelog + README, every time.** For each shippable change you must:
   - Bump the version in **all three** places the pipeline reads (see
     `hermes-ios-build-pipeline` memory: version lives in 3 files). Grep before you
     commit: `grep -rn "1\.2\.1\|version-1" README.md project.yml Herald/ HeraldWidgets/`.
   - Add a dated `## [x.y.z]` section to `CHANGELOG.md` with `### Added / Changed / Fixed`
     subsections naming the files touched (match the existing style in that file).
   - Update the version badge line in `README.md` and any feature docs under `docs/`.
   - Update `MAINTAINER_NOTES.md` if the build/dev workflow changes.
   - One logical change = one commit = one changelog entry. Don't batch unrelated fixes
     under a single vague "build N" line — the current CHANGELOG top entries ("build 13:
     fix streaming visibility, reasoning duplication, scroll, timer, images, video, tool
     persistence, notifications, error surfacing") are exactly what NOT to do again.
2. **Assess before editing.** Every item lists the exact files/lines. Read them first.
3. **Match surrounding idiom** — this is Swift 6.2, `@Observable @MainActor` stores,
   strict concurrency. Notification-delegate methods already tripped Swift 6 concurrency
   in build 13; keep new delegate/callback code `@MainActor`-clean.
4. Backend changes (relay/connector) that touch the DB **need manual ALTERs** — the relay
   has no migrations (see `hermes-ios-app` memory). Ship the ALTER statements in the PR.

---

## P0 — Profile selector does not switch (the screenshot bug)

**Symptom:** `/profile flynt` (typed, or tapped in `ProfileSelectorSheet`) makes the agent
reply *"I can't switch profiles from within a session — that's a CLI-level operation…
run `hermes profile use flynt`."* The chip never changes. This is the "use hermes gw
natively, not the TUI" ask — same root cause.

**Root cause (confirmed in code):**
- `ProfileSelectorSheet` selection → `ChatScreen.swift:248-249` calls
  `chatStore.sendMessage("/profile \(name)")`.
- `/profile` is a **read-only INFO command** (`SlashCommand.swift` gatewayCommands:
  `"Show active profile and home directory", acceptsArgument: false`). The connector's
  registry agrees (`connector/.../client.py:42` `gatewayOnly: False`, no arg). Sending
  `/profile flynt` as chat text just asks the agent to describe itself; the agent
  correctly refuses to switch.
- The app then relies on `ChatStore.detectProfileSwitch(...)` (`ChatStore.swift:866-881`)
  scraping the reply for "switched to profile X" — which never appears. So the chip
  optimistically flips via `markActive` (`ChatScreen.swift:248`) then reverts on the next
  `GET /v1/profiles` refresh. Fragile by design.
- **There is no profile-switch RPC anywhere.** The connector only has
  `profiles.list` (`client.py:1109-1110, 1458-1525`, read-only). The RPC dispatch table
  (`client.py:1095-1125`) has no `profiles.use`. The relay only exposes
  `GET /v1/profiles` (`relay/app/main.py:1210-1222`).

**Fix — build a real native switch path (3 layers):**

1. **Connector** (`connector/src/herald_connector/client.py`):
   - Add `elif method == "profiles.use": result = await self._rpc_profiles_use(params)`
     to the dispatch table (~line 1109, next to `profiles.list`).
   - Implement `_rpc_profiles_use(self, params)`: validate `params["name"]` against the
     same profile enumeration `_rpc_profiles_list` already builds (reject unknown names).
     Switching profiles = pointing `HERMES_HOME` at the sibling profile dir and
     **restarting the gateway/connector service**. The service manager already supports
     this: `service_management.py:113 def restart()`. Reuse it. Persist the new default
     (the `config["profile"]["default"]` override that `_rpc_profiles_list` reads at
     `client.py:1479`) so the choice survives the restart.
   - **Caveat (user has ACCEPTED this):** switching profiles restarts the runtime and
     **drops the live session** — intrinsic, it's what `hermes profile use` does. This is
     approved; just handle it cleanly. Return `{ "activeProfile": {...}, "restarting": true }`
     so the client shows a "switching… reconnecting" state instead of an error, and
     auto-recovers when the host comes back.

2. **Relay** (`relay/app/main.py`): add `POST /v1/profiles/active` (mirror the
   `profile_catalog` handler at `:1210`). Body `{ "name": "flynt" }` → dispatch the
   `profiles.use` method to the host with a longer timeout (restart can take 10-20s;
   the list call uses 10s at `:1216` — use ~30s here). Return the connector's result.

3. **iOS:**
   - `ProfileStore.swift`: add `func setActiveProfile(_ name:) async throws` that POSTs to
     `profiles/active` via the injected `RelayAPIClient` (it already holds `apiClient` +
     `accessTokenProvider`). On success call `markActive(name)` and kick `loadProfiles(force: true)`.
   - `ChatScreen.swift:244-249`: replace the `sendMessage("/profile \(name)")` call with
     `Task { try? await profileStore.setActiveProfile(name) }`. Show a transient
     "Switching to <name>… reconnecting" state (the host will bounce — reuse the existing
     `connectionBanner` / `hostStore.connectionState` machinery, ChatScreen:48-49).
   - Delete or neuter `detectProfileSwitch` text-scraping (`ChatStore.swift:302, 866-881`)
     once the RPC path lands — it's a fragile hack that will now fight the real signal.
   - Keep `/profile` (no arg) as the info command it is; only the **sheet** and
     `/profile <name>` should route to the RPC.

**Acceptance:** tapping a profile in the sheet switches the runtime, the chip updates and
*stays* updated after the 60s catalog refresh, and no chat message is emitted. The app
never tells the user to open a TUI.

---

## P0 — Retry loop / "that was already done" duplicate execution

**Symptom:** a response shows a failure with a Retry affordance; tapping Retry makes the
agent say the work was already done — i.e. the job actually ran on the backend, but the
client gave up and re-dispatched it.

**Root cause (confirmed):**
- `ChatStore.runStreamingAttempt` (`ChatStore.swift:199-`) races the SSE stream against a
  **~30s watchdog**. If no *progress* event arrives in 30s it declares a stall and
  `runAttemptLoop` (`:166-190`) **auto-re-sends the same content** (up to `maxAutoRetries`),
  then leaves a manual "tap to retry" (`failStalledMessage` `:390` → `retryMessage` `:536`).
- Critically, `.messageSent` (relay accepted the job) is **deliberately excluded** from
  "progress" (`:196-198`, `:221-224`). So a job that is accepted and genuinely running but
  slow to first token (long tool call, cold model prefill on the self-hosted box — see the
  fih-ai-host OOM/freeze history) trips the 30s watchdog and gets **executed a second
  time**. The connector/gateway does not dedupe on `clientMessageID`, so the retry is a
  brand-new turn → "I already did that."

**Fix — idempotency, not just longer timeouts:**
1. **Make retries idempotent end-to-end.** The client already generates and sends a
   `clientMessageID` (`ChatStore.swift:105`, passed to `heraldClient.sendStreaming(...
   clientMessageID:)` at `:205`). The **backend must honor it:** in the connector's job
   dispatch path, if an inbound job carries a `clientMessageID` that is already
   running/completed, **re-attach to the existing job's stream instead of starting a new
   turn** (return the in-flight/finished result). This single change kills the double-exec
   for both the auto-retry and the manual Retry button. Verify where the relay→connector
   job is created (`connector/.../herald_runner.py` / `herald_api_executor.py`) and key it
   on `clientMessageID`.
2. **Stop treating "accepted but slow" as a stall.** Once `.messageSent` arrives, the job
   IS dispatched. Either (a) extend the post-accept watchdog substantially (the 30s window
   is tuned for the "claimed but never dispatched" bug described in the `:156-165` comment,
   which is a *different* failure), or (b) after `.messageSent`, switch from the fixed 30s
   to the polling-fallback path (`needsPollingFallback`, `:207`) so a slow-but-alive job is
   awaited via poll rather than re-sent. Distinguish "never accepted" (retry is safe) from
   "accepted, no tokens yet" (retry is NOT safe — poll instead).
3. **Manual Retry button** (`MessageBubble` → `retryMessage` `:536`): reuse the original
   `clientMessageID` so step 1's dedupe applies. Currently retry re-derives content
   (`normalizedRetryContent` `:846`) and removes messages — make sure it carries the same
   id so the backend recognizes it.

**Acceptance:** on a slow-but-successful turn, no duplicate execution occurs; Retry after a
genuine drop re-attaches or safely re-runs exactly once.

---

## P1 — Dynamic Island / Live Activity: thinking brain, timers, completion notification

**Current state (confirmed):**
- Live Activity infra exists: `HeraldActivityAttributes` (status/`toolName`/`startDate`/
  `sessionType`), `LiveActivityService` (`startVoiceSession`, `startToolCall`,
  `updateToolProgress`, `endActivity`), rendered by `HeraldWidgets/HeraldLiveActivity.swift`
  (already uses `Text(timerInterval:)` at `:154` — timers work when an activity exists).
- **Gap 1 (brain while thinking/backgrounded):** the chat Live Activity is started **only
  on the first tool call** — `ChatStore.swift:253 chatLiveActivity.startToolCall(...)`.
  It is never started at message send or when reasoning begins. So a pure "thinking" turn
  (reasoning, no tool) shows **nothing** on the Lock Screen / Dynamic Island. `ContentState`
  already anticipates a `"Thinking"` status (see the doc comment in
  `HeraldActivityAttributes.swift`) — it's just never triggered.
- **Gap 2 (completion notification):** there is **no local notification on response
  complete** anywhere. `LiveNotificationService` only does push *authorization/token*
  (`requestAuthorization`, `updatePushToken` — grep confirms no `UNNotificationRequest`
  is ever scheduled). The APNs/push-broker path exists (`PushBrokerClient`,
  `relay/app/apns.py`) but nothing fires a "your response is ready" alert.

**Fix:**
1. **Start the activity at send, in a "Thinking" state.** In `ChatStore.sendMessage`
   (`:100`) or at first `.reasoningDelta`/first byte, call a new
   `chatLiveActivity.startThinking(sessionType: "chat")` that sets `status: "Thinking"`,
   `startDate: .now` (drives the live timer), no `toolName`. Transition to
   `updateToolProgress` when tools start (existing `:253`), and `endActivity()` on
   `.finished` (existing `:305`). Ensure it's ended on every terminal path (`:326, 361,
   403, 411, 425` already call `endActivity`).
2. **Widget: render the brain.** In `HeraldLiveActivity.swift`, when `toolName == nil &&
   status == "Thinking"`, show a `brain`/`brain.head.profile` SF Symbol with the existing
   pulse animation and the `Text(timerInterval:)` clock (`:154`). Compact/minimal Dynamic
   Island presentations should show the brain glyph + elapsed timer.
3. **Completion notification when backgrounded.** On `.finished` (`ChatStore.swift:256`),
   if `UIApplication.shared.applicationState != .active`, schedule a local
   `UNNotificationRequest` via a new `LiveNotificationService.notifyResponseComplete(
   preview:)` (title "Herald replied", body = first ~120 chars of the response). Gate on a
   new `UserSettings` toggle (default on) and on notification authorization already tracked
   by that service. **Preferred for reliability:** also have the **relay** send an APNs push
   on turn completion (via the existing `PushBrokerClient`/`apns.py`) so the alert arrives
   even if iOS has suspended the app — the local-notification path only works while the app
   is backgrounded-but-alive.

**Acceptance:** send a thinking-only prompt, background the app → Dynamic Island shows a
pulsing brain + running timer; when the reply lands you get a notification with a preview.

---

## P1 — Pinch-to-zoom chat text + remember sizing

**Current state:** pinch/`MagnificationGesture` exists **only for image attachments**
(`MessageAttachmentsView.swift:257-260`). There is **no** text-scaling anywhere — no
font-scale store, no persisted size.

**Fix:**
1. Add a persisted `chatFontScale: Double` (clamped ~0.8–2.0, default 1.0) to
   `UserSettings.swift` with backward-compatible `Codable` migration (follow the exact
   pattern used for the TTS props added in 1.1.0 — see CHANGELOG). Persist via
   `SettingsStore`.
2. Attach a `MagnificationGesture` to the chat `ScrollView`/message list
   (`ChatScreen.swift:515 messageList`). During the gesture, multiply a live scale; on
   `.onEnded`, commit the clamped value to `settingsStore`. Apply it to message text via
   the `Design.Typography` fonts used in `MessageBubble` / `MarkdownContentView` /
   `CodeBlockView` — prefer scaling the font sizes (or a `.dynamicTypeSize` / `scaleEffect`
   on text only, NOT on whole bubbles, to avoid layout breakage of code blocks and tables).
3. Restore the saved scale on launch so sizing persists across sessions and relaunches.
4. Don't conflict with the image pinch gesture — the image viewer has its own gesture scope;
   ensure the list-level gesture doesn't hijack pinch while an image is zoomed.

**Acceptance:** pinch in chat resizes message text smoothly, the size sticks after force-quit.

---

## P1 — "3 dots keep coming back" = top-right ⋯ toolbar overflow (CONFIRMED)

**User confirmed this is the top-right ⋯ menu, not the thinking dots.** SwiftUI is
synthesizing an overflow `⋯` menu because the toolbar has more items than fit.

**Where:** `ChatScreen.swift:156-196 toolbarContent`. The **leading** group packs
`hamburger (iPhone) + profileChip + modelStatusChip + sessionTimerChip` (`:159-176`) and the
**trailing** group has canvas + gear (`:178-195`). On narrow devices the combined intrinsic
width exceeds the nav bar, so SwiftUI collapses the overflow into an auto `⋯`. It "keeps
coming back" because it's regenerated on every layout pass whenever the chips are wide (e.g.
long profile/model names like "mimo-v2.5").

**Fix:**
1. Condense the leading chips so they fit without overflow: icon-only (or heavily truncated)
   under a width/`DeviceClass.isPhone` threshold — `profileChip` already truncates model
   names (`:478`); apply the same discipline to all three chips and cap their combined width.
2. Consider moving `sessionTimerChip` (and/or the model chip) into a **single explicit**
   compact control, or into the session drawer, so the toolbar never overflows and iOS never
   synthesizes the `⋯`.
3. Verify with the longest realistic profile + model strings on the smallest supported
   iPhone in the layout preview — the overflow must not reappear.

**Acceptance:** no `⋯` menu ever appears in the chat toolbar on any supported device, with
long profile/model names.

---

## P2 — `/new` takes multiple tries / "cycled through previous sessions"

**Symptom:** first two `/new` attempts cycled sessions; third worked.

**What the code does today:** typed `/new` → `sendMessage` (`ChatScreen.swift:671`) →
`dispatchTypedSlashCommand` (`:784`) → local lookup requires `name == "new" &&
suggestedArgument == nil && isLocal` against `chatStore.commandCatalog +
SlashCommand.localCommands` (`:797-798`) → `handleSlashCommand` (`:742`) → `case "new":
showClearConfirmation = true` (`:743-744`). So `/new` is gated behind a **destructive
confirmation dialog** and only starts a new session after the user taps "Clear"
(`performClear` `:807`).

**Likely bugs to check (repro on device first):**
1. **Catalog collision.** The remote `commandCatalog` (from `GET /v1/commands`) may contain
   a non-local `new`/`resume` entry or `/resume <session>` argument-suggestions
   (`SlashCommand.fromRemote` produces `isLocal: false`). If the autocomplete highlights a
   `resume`/session suggestion and the composer's Return dispatches the **highlighted menu
   item** rather than the typed `/new`, you'd "cycle through previous sessions." Verify what
   `filteredCommands` (`ChatInputBar.swift:75-100`) returns for query `new` and whether any
   `/resume`-style suggestions rank above local `/new`.
2. **Confirmation friction.** Even on the happy path, `/new` needs a dialog tap. That plus
   fuzzy-match noise reads as "took 3 tries." Consider: make local `/new` deterministic and
   first in the menu, and (optionally) skip the confirmation when the current session is
   empty/already-saved.
3. Ensure `dispatchTypedSlashCommand`'s `.first{…}` can't match a **remote** `new` before
   the local one (the `isLocal` filter should protect this — add a test).

**Acceptance:** typing `/new` (or tapping it once) reliably starts a new session in a single
action and never navigates into an existing session. Add a unit test around
`dispatchTypedSlashCommand("/new")` and the catalog-merge ordering.

---

## Suggested sequencing & commits

1. **Profile switch RPC** (P0) — connector + relay + iOS, one feature, one changelog entry,
   version bump. Ship the caveat handling (restart/reconnect).
2. **Retry idempotency** (P0) — backend dedupe on `clientMessageID` + watchdog fix.
3. **Live Activity thinking-brain + completion notification** (P1).
4. **Pinch-to-zoom + persisted font scale** (P1).
5. **Thinking-dots lifecycle leak** (P1) — likely small; audit + choke-point.
6. **`/new` determinism** (P2) — repro, then fix catalog ordering + confirmation.

Each is an independent PR with its own version bump, `CHANGELOG.md` entry, and README/docs
update per the Ground Rules. Do not land two of these under one "build N" changelog line.
