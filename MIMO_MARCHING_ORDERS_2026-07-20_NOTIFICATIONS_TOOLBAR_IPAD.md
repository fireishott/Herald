# Herald — Mimo Marching Orders: Live Responses, Notifications, iPhone Toolbar, iPad Layout

**Prepared:** 2026-07-20  
**Audience:** Mimo `mimo-v2.5`  
**Starting point:** git commit `906f3ea` (build 13 notification-concurrency fix)  
**Assessment mode:** source reviewed read-only; this document is the only file created  
**Device evidence:** `/Users/curtisfreeman/Downloads/Screenshot 2026-07-20 at 2.28.30 AM.png`

## Ground rules — read before editing

1. Keep each item below as an independent logical change and commit. Do not combine all
   five under another generic "build N fixes" commit.
2. Every shippable change must:
   - bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for both `Herald` and
     `HeraldWidgets` in `project.yml`;
   - update the README version badge;
   - add a dated `CHANGELOG.md` entry naming the behavior and files changed;
   - update the relevant README/docs text;
   - run `xcodegen generate` because `project.yml`, not the generated `.xcodeproj`, is the
     source of truth.
3. The version state is already drifted: `project.yml` is `1.2.1 / build 11`, README is
   `1.2.1`, while git history says build 13. Reconcile this in the first change, then advance
   versions monotonically for later commits.
4. Swift is 6.2 with `SWIFT_STRICT_CONCURRENCY: complete`. Keep notification delegate data
   crossings primitive and `Sendable`; UI/store mutations stay on `@MainActor`. Do not use
   `@unchecked Sendable` to silence notification APIs.
5. The relay has no migration framework. If a database schema change becomes necessary,
   include exact manual `ALTER TABLE` statements and operator instructions. The fixes below
   should not require a schema change.
6. Do not hardcode secrets, APNs credentials, host tokens, or relay credentials.
7. Unlock the Mac login keychain before **every** `xcodebuild`. Do not repeatedly resubmit a
   build or host job merely because it is slow; `fih-ai-host` has an OOM/freezing history.

## Environment

| Thing | Value |
|---|---|
| **App repo** | `/Users/curtisfreeman/Herald` (git; branch history uses "build N" commits) |
| **iOS app** | `Herald/` target; Swift 6.2; strict concurrency complete; use iOS 26 APIs for new UI |
| **Widgets** | `HeraldWidgets/`; App Group `group.net.fihonline.herald` |
| **Relay** | `relay/` FastAPI + SQLite; no migrations; field host `192.168.10.118:8010` |
| **Connector** | `connector/src/herald_connector/`; WebSocket RPC dispatcher in `client.py` |
| **Hermes host** | `fih-ai-host` at `192.168.10.118`; accepted-but-slow work must not be retried |
| **Coding model** | Mimo `mimo-v2.5` |
| **Build machine** | MacBook Pro; unlock login keychain before each `xcodebuild` |
| **Project generation** | XcodeGen; edit `project.yml`, then run `xcodegen generate` |
| **Bundle / team** | `net.fihonline.herald` / `58U7UPFS53` |
| **Secrets** | iOS Keychain; relay/connector environment; never commit secrets |

---

## P0 — Notification open: preserve the destination, serialize cold launch, never crash

### Reported behavior

Opening a Herald notification crashes the app or fails to open the chat that produced the
notification. Additional device confirmation: notification taps appear to open "any old
session" rather than the session that generated the alert.

### Confirmed defects

1. **The managed push-broker transport drops the destination metadata.**
   - Direct APNs sends `conversationId` and `messageId` in `user_info` at
     `relay/app/main.py:412-422`.
   - Managed relay transport calls `default_push_broker_sender` with only `title` and
     `body` at `relay/app/main.py:401-405`.
   - The signed broker payload contains no conversation, message, job, or category fields at
     `relay/app/main.py:354-376`.
   - `PushBrokerSendRequest` has no fields for that metadata at
     `relay/app/schemas.py:138-159`.
   - `/v1/push-broker/send` consequently invokes APNs without `category` or `user_info` at
     `relay/app/main.py:739-794`.
   - The existing broker test explicitly expects `category: None` at
     `relay/tests/test_push_broker.py:299-326`; update this test because that expectation
     preserves the bug.

2. **The tap handler can only open sessions already present in two in-memory arrays.**
   - `Herald/AppEntry.swift:79-95` parses `conversationId`, then searches only
     `recentSessions` and `pinnedSessions`.
   - It ignores archived/search/paginated sessions and any session list not loaded yet.
   - When no match is found, it calls `chatStore.loadConversation()`, which loads the
     relay's *current* conversation, not the notification's conversation.
   - This is the direct explanation for the apparently random destination: the fallback is
     whichever conversation the relay currently considers active, which need not be the
     conversation named by the notification and may change between taps.
   - A specific-conversation API already exists:
     `HeraldClientProtocol.loadConversation(id:)` at
     `Herald/Services/Protocols/HeraldClientProtocol.swift:46-47`, implemented by
     `LiveHeraldClient` at `Herald/Services/Live/LiveHeraldClient.swift:679`.

3. **Cold launch has competing asynchronous state writers.**
   - The notification delegate starts an untracked `Task` inside `MainActor.run` at
     `Herald/AppEntry.swift:82-94`.
   - At the same time, the root view starts `container.initialize()` at
     `Herald/AppEntry.swift:127`.
   - Initialization loads the current conversation before it loads sessions at
     `Herald/Stores/AppContainer.swift:355-377`.
   - A notification tap can therefore request one conversation while initialization writes
     another. This is a confirmed routing/lifecycle defect. The exact exception causing the
     reported crash is **repro needed** because no device `.ips` crash report is available.
     Instrument this call chain rather than inventing a crash signature:

       `UNUserNotificationCenterDelegate.didReceive`
       → `AppContainer.initialize`
       → `SessionListStore/ChatStore conversation assignment`
       → `AppRootView/MainTabView render`

### Concrete fix path

1. Extend message push metadata end to end:
   - Change `default_push_broker_sender` to accept `conversation_id`, `message_id`, optional
     `job_id`, and `category`.
   - Add optional `conversationId`, `messageId`, `jobId`, and `category` fields to
     `PushBrokerSendRequest`.
   - Include those exact fields in the signed payload on both sender and verifier paths.
     Optional values must be canonicalized consistently before signing.
   - Forward `category` to `send_alert_push(category:)` and the IDs through
     `send_alert_push(user_info:)` in the broker endpoint.
   - Make direct APNs, managed broker APNs, and `/v1/push/send` produce the same custom
     payload contract.
   - Use the stable category identifier `HERALD_MESSAGE_READY` for completed chat replies.

2. Add a single `@MainActor` notification-routing entry point on `AppContainer`, for
   example `handleNotificationRoute(conversationID:messageID:jobID:action:userText:)`.
   The delegate must copy only primitive strings out of `UNNotificationResponse`, then call
   this entry point. Do not pass `UNNotificationResponse` into a `Task` or actor boundary.

3. Store a pending route while initialization/bootstrap is incomplete. Process it exactly
   once after `initialize()` has established a usable session. If already initialized,
   process it immediately. Add single-flight protection around initialization so two callers
   cannot run the bootstrap sequence concurrently.

4. Add `SessionListStore.switchToSession(id:)` (or an equivalent `ChatStore` method) that
   calls `heraldClient.loadConversation(id:)` directly. Notification routing must never
   depend on the requested session appearing in the first 50 list results.

   **Hard rule:** delete the notification path's no-argument `chatStore.loadConversation()`
   fallback. If a notification contains a valid `conversationId`, either load exactly that
   ID or show an explicit "Conversation unavailable" error. Never substitute the relay's
   current conversation, the most recent local conversation, or the first sidebar entry.

5. Navigation order after the target conversation loads successfully:
   - dismiss sheets and voice overlays as appropriate;
   - pop the navigation path;
   - select Chat in the shared router;
   - publish the loaded target conversation;
   - clear the pending route.
   If loading fails, remain alive, select Chat, show a recoverable error, and retain enough
   structured logging to diagnose the relay response.

6. Add `Logger` breadcrumbs containing action identifier and redacted ID suffixes at receipt,
   deferral, load start, load success, and load failure. Never log message bodies, reply text,
   access tokens, or full notification payloads.

### Required tests

- Relay direct-push test asserts category plus `conversationId`, `messageId`, and `jobId`.
- Relay broker-sender test asserts those fields survive the signed request.
- Push-broker endpoint test asserts APNs receives the same category and `user_info`.
- Signature tests prove metadata tampering invalidates the broker request.
- iOS test: terminated/cold-start route is deferred until initialization, then opens the
  exact ID.
- iOS test: the destination is not in the loaded session page but still opens by ID.
- iOS test: malformed/missing ID falls back safely without a crash.
- iOS test: load failure produces visible recoverable state, not termination.

### Acceptance criteria

- Tap a notification with Herald terminated: the app launches into the exact originating
  conversation with no crash.
- Tap while another conversation is open: the notified conversation replaces it.
- Tap notifications from three different sessions in arbitrary order: each tap opens the
  matching session every time; the previous/current session has no influence.
- Managed relay and direct APNs behave identically.
- Old/malformed/deleted-session notifications never crash, never open a random conversation,
  and show a clear unavailable state when an ID was present but cannot be loaded.

---

## P0 — Lock-screen actions: Read, Reply, Stop, and Nudge

### Confirmed gaps

- The app registers no `UNNotificationCategory` or `UNNotificationAction`. Launch currently
  sets only the delegate at `Herald/AppEntry.swift:16-23`.
- `LiveNotificationService` only requests permission and tracks the token at
  `Herald/Services/Live/LiveNotificationService.swift:11-38`.
- APNs supports a category parameter at `relay/app/apns.py:122-149`, but all current message
  push call sites omit it.
- The visible Chat Stop button only cancels the local SSE consumer at
  `Herald/Stores/ChatStore.swift:422-440`; it does not cancel the relay job or Hermes work.
- The connector already keeps running jobs in an `active_jobs` task dictionary at
  `connector/src/herald_connector/client.py:717-752`, but exposes no cancellation RPC in
  the dispatcher at `connector/src/herald_connector/client.py:1088-1126`.

### Action contract — implement these exact meanings

| Action | Behavior |
|---|---|
| **Read** | Open the exact conversation through the P0 routing entry point and foreground the app. |
| **Reply** | `UNTextInputNotificationAction`; post the typed text to the notification's `conversationId`, using a fresh `clientMessageId`. It must not depend on the currently displayed conversation. |
| **Stop** | Cancel `jobId` end to end. If already completed, return a harmless "Already finished" result. Never represent local SSE cancellation as backend cancellation. |
| **Nudge** | Submit the fixed follow-up `Continue, and give me a concise status update.` to the same conversation with a fresh `clientMessageId`. This is a queued chat follow-up, not an out-of-band runtime interrupt. |

Register `HERALD_MESSAGE_READY` with Read, Reply, and Nudge. Register
`HERALD_JOB_ACTIVE` with Read, Stop, and Nudge. Only attach Stop when the payload refers to
a live/queued job; do not show a knowingly useless Stop action on a completed reply.

### Concrete implementation path

1. **iOS category registration**
   - Give `NotificationServiceProtocol` and `LiveNotificationService` a category-registration
     method.
   - Register both categories during launch before remote notifications can be acted on.
   - Define stable action IDs in one shared Swift namespace; do not scatter raw strings.
   - Route all action responses through the P0 `AppContainer` handler.

2. **Make the active-job category real**
   - The relay currently sends only a completion alert, after `complete_message_job`, at
     `relay/app/main.py:2622-2631`. A completed notification cannot offer a meaningful Stop.
   - Add a background-only active-job alert after the connector successfully claims a job
     (`relay/app/main.py:2495-2528`). Use title `Herald is working`, include
     `conversationId`, `messageId`, and `jobId`, and attach `HERALD_JOB_ACTIVE`.
   - Keep the existing completion alert, but attach `HERALD_MESSAGE_READY`. Use a stable
     APNs thread/collapse identifier derived from `jobId` across direct and broker transports
     so completion replaces or groups with the working notification instead of leaving noisy
     duplicates.

3. **Reply/Nudge iOS caller**
   - Add an explicit `sendMessage(_:conversationID:clientMessageID:)` service operation.
     `LiveHeraldClient.makeCreateBody` currently always takes
     `currentConversation?.id` at `Herald/Services/Live/LiveHeraldClient.swift:285-304`,
     which is unsafe for notification actions.
   - Reuse existing `POST /v1/messages`; its schema already accepts `conversationId` and
     `clientMessageId` at `relay/app/schemas.py:174-185`.
   - Update Live/Mock/Resilient implementations and tests together.
   - Reject empty Reply text locally. Nudge uses the exact fixed text above.

4. **Stop capability: connector RPC + relay endpoint + iOS caller**
   - Connector RPC: add `jobs.cancel` to the dispatcher. Move the per-connection
     `active_jobs` registry to concurrency-safe connector state accessible by the RPC.
     Validate the job ID, cancel the matching `asyncio.Task`, await its cancellation, clean
     staged attachments, and return `{jobId, status: "cancelled"}`. Ensure a cancelled task
     emits one terminal cancellation result rather than a generic retryable failure.
   - Relay endpoint: add authenticated `POST /v1/jobs/{job_id}/cancel`. Verify the job belongs
     to the requesting user; return idempotent success for `cancelled`; return
     `already_completed` for terminal jobs. Dispatch connector RPC `jobs.cancel` for running
     work and persist/publish a terminal `cancelled` SSE event. A queued job can be cancelled
     directly without connector dispatch.
   - iOS caller: add typed cancellation to the appropriate service/store and call it from the
     Stop action using `jobId` from the push payload.
   - No DB migration should be needed because `MessageJob.status` is text. If constraints or
     indexes are added, provide manual SQL.

5. **Background execution discipline**
   - Complete notification responses promptly and use the async delegate API correctly.
   - Keep UI feedback best-effort; the network operation is authoritative.
   - On authentication failure, perform the existing token-refresh flow once. Do not create
     a duplicate reply/nudge because a request was accepted slowly; preserve its
     `clientMessageId` for safe replay.

### Required tests

- Category registration contains the exact action identifiers and options.
- Read uses the same cold-launch route as a normal tap.
- Reply to conversation B while conversation A is open posts only to B.
- Duplicate delivery of the same Reply request is deduplicated by `clientMessageId`.
- Nudge sends the exact fixed text to the correct conversation.
- Cancel queued job, cancel running job, cancel already-completed job, unauthorized job ID,
  connector-disconnected cancellation, and double cancellation.
- A cancelled job cannot later publish a successful assistant message.

### Acceptance criteria

- Long-press a lock-screen notification and see the actions appropriate to its state.
- Reply without opening Herald; the reply appears in the originating conversation exactly
  once.
- Read foregrounds the exact chat.
- Stop terminates real host work, not just local UI streaming.
- Nudge adds one deterministic follow-up to the correct chat.

---

## P0 — Replace timeout-and-hope behavior with one resumable live job connection

### Reported behavior

Sending a prompt does not feel like a continuously live connection. The app appears to wait
for a timeout, hope the work finished, poll, and eventually offer a retry.

### What is actually live today

There is a real token path when the connector is using `HeraldAPIRuntimeAdapter`:

`Hermes API SSE` → `connector job.progress` → `relay per-job SSE` → `LiveHeraldClient`
→ `ChatStore` delta coalescing → SwiftUI

- Hermes API streaming is enabled at
  `connector/src/herald_connector/runtime_adapter.py:77-126`.
- The executor consumes Hermes SSE and emits reasoning/text/tool events at
  `connector/src/herald_connector/herald_api_executor.py:204-317`.
- The connector converts those to `job.progress` WebSocket messages at
  `connector/src/herald_connector/client.py:869-953`.
- The relay publishes them into the job SSE stream at `relay/app/main.py:2590-2599` and
  flushes text batches every ~40 ms at `relay/app/main.py:2245-2332`.
- iOS consumes that SSE at `Herald/Services/Live/LiveHeraldClient.swift:378-440` and paints
  text on a ~33 ms cadence at `Herald/Stores/ChatStore.swift:619-678`.

The problem is not the absence of streaming code. The problem is that transport loss,
first-token waiting, leases, and retry are not represented by one authoritative job state
machine.

### Confirmed defects

1. **SSE EOF without `done` is incorrectly treated as success.**
   - `streamJobEvents` returns `nil` whenever the byte stream ends at
     `Herald/Services/Live/LiveHeraldClient.swift:425-427`.
   - `sendStreaming` then reloads the conversation and always yields `.finished` at
     `Herald/Services/Live/LiveHeraldClient.swift:216-225`.
   - If the job is still queued/running and no final message exists,
     `resolveFinalMessage` manufactures an empty delivered Herald message at
     `Herald/Services/Live/LiveHeraldClient.swift:458-490`.
   - A Wi-Fi/cellular handoff can therefore look like "hope it finished" instead of a
     recoverable stream interruption.

2. **The SSE client reconnects only for HTTP 401.**
   - `streamJobEvents` loops only around token refresh at
     `Herald/Services/Live/LiveHeraldClient.swift:385-438`.
   - Timeout, connection loss, server restart, HTTP/2 reset, and clean premature EOF do not
     reattach to the same job. The outer layer emits `Stream interrupted` and abandons live
     streaming at `Herald/Services/Live/LiveHeraldClient.swift:226-229`.

3. **Polling declares failure before the relay's own job deadline.**
   - iOS polling delays total about **134.5 seconds** and then mark pending messages failed at
     `Herald/Stores/ChatStore.swift:680-730`.
   - Relay jobs have a **180-second** lease at `relay/app/config.py:45-52` and
     `relay/app/services.py:1199-1214`.
   - Thus the app can display failure and enable Retry while the original host job is still
     valid for another ~45 seconds.

4. **Relay uses a fixed wall-clock deadline, not a liveness lease.**
   - Every claimed job gets an absolute `now + 180s` deadline at
     `relay/app/main.py:2533-2553`.
   - Connector heartbeats prove the WebSocket/host is alive, but they do not extend this job
     deadline. A healthy long tool run is killed at the same point as a frozen job.
   - The timeout path calls `fail_message_job(... retryable=True)` and then publishes a
     terminal-looking `done/status=failed` at `relay/app/main.py:2514-2531`. The database job
     is queued for another execution while iOS is told it failed. This is exactly a
     timeout-then-hope/retry split-brain.

5. **Connector CLI fallback cannot stream content.**
   - If the API runtime does not report `supports_streaming`, the connector runs a blocking
     CLI turn and sends only generic heartbeats until the final result at
     `connector/src/herald_connector/client.py:962-1016`.
   - The app gets no job phase or tool progress during that interval. This fallback must be
     exposed honestly as live liveness/status, even though token deltas are unavailable.

6. **SSE replay is not reconnect-safe.**
   - Events are stored only in process memory. `subscribe_job_events` pops the replay buffer
     into the first subscriber at `relay/app/main.py:280-289`.
   - Events are not assigned SSE IDs, and iOS `SSEEvent` stores only `event` and `data` at
     `Herald/Models/SSEEvent.swift:3-6`.
   - A reconnect cannot send `Last-Event-ID`; deltas produced during a disconnect can be
     lost or consumed by the stale subscriber queue.

7. **The comments and behavior disagree around auto-retry.**
   - `ChatStore` comments claim `.messageSent` does not count as progress at
     `Herald/Stores/ChatStore.swift:192-198`, but the implementation signals progress for it
     at `Herald/Stores/ChatStore.swift:221-224`.
   - The pre-accept watchdog is currently 120 seconds with one automatic resubmission at
     `Herald/Stores/ChatStore.swift:20-21,166-188`. Reusing `clientMessageId` makes this HTTP
     submission idempotent in the relay at `relay/app/main.py:2099-2129`, which is good.
   - Manual Retry is different: `retryMessage` calls `sendMessage` and generates a new
     `clientMessageId` at `Herald/Stores/ChatStore.swift:536-553,100-106`. If polling falsely
     marked the original failed, manual Retry can create a second agent turn.

8. **Phone activity, iOS SSE activity, and host-connector activity are conflated.**
   - iOS reports foreground only on activation/system launch at
     `Herald/Stores/AppContainer.swift:380-423`, and reports background on the scene change at
     `Herald/AppEntry.swift:128-133`.
   - The foreground record becomes stale after 120 seconds at
     `relay/app/services.py:847-850` / `relay/app/config.py:61`. There is no periodic presence
     heartbeat while the user actively keeps Herald open, so a long foreground session can
     be misclassified as background.
   - That device state is currently used only to suppress duplicate pushes at
     `relay/app/main.py:398-400`. It has no relationship to whether a host job survives.
   - By contrast, **any** host WebSocket disconnect with `in_flight_job_id` immediately calls
     `fail_message_job(... retryable=False)` and publishes terminal failure at
     `relay/app/main.py:2733-2764`. There is no reconnect grace period.
   - The connector itself retries its relay connection after only three seconds at
     `connector/src/herald_connector/client.py:668-678`, so the relay may permanently fail a
     job just before the same connector returns.
   - Worse, connector `active_jobs` is scoped inside one `_run_once` WebSocket session at
     `connector/src/herald_connector/client.py:717-752`. On socket exit the send worker is
     stopped at `connector/src/herald_connector/client.py:766-768`, but active job tasks are
     neither durably transferred nor cleanly cancelled. A Hermes task may keep running and
     enqueue a result into an outbound queue that no longer has a sender.

### Target state machine

Use one server-authoritative state model for every job:

`submitting → queued → claimed/running → reasoning/tool/text progress → completed`

Terminal alternatives are `failed` and `cancelled`. Transport state (`connected`,
`reconnecting`, `offline`) is separate from job state. Losing the SSE connection must never
change a running job to failed, completed, or retried.

### Concrete fix path

#### 1. Connector: send job-specific liveness, not just socket heartbeats

- While an entry in `active_jobs` is running, emit `job.heartbeat` every 10 seconds with
  `jobId`, a monotonic sequence/time, and the last known phase (`starting`, `thinking`,
  `tool`, `writing`, or `cli_waiting`).
- Emit an immediate `job.started` after the task is accepted locally, before waiting for the
  first model token.
- Continue emitting normal `job.progress` events for reasoning/text/tools.
- The CLI fallback must emit `job.started` plus `job.heartbeat(phase=cli_waiting)` so the UI
  can distinguish "alive but non-token-streaming" from frozen.
- Stop the heartbeat task on exactly one terminal `job.result`, `job.failed`, or cancellation.

This is an extension of the existing connector job WebSocket protocol, not an unrelated RPC.
The connector side, relay endpoint/SSE side, and iOS caller/consumer side must land together.

#### 2. Relay: make the lease renewable and job events resumable

- Add `renew_message_job_lease(job_id, connection_nonce)` and call it only for matching
  `job.started`, `job.heartbeat`, and real `job.progress` frames. Generic connector/socket
  traffic must not renew a stuck job.
- Replace the absolute 180-second wall-clock kill with an **inactivity lease**: fail/requeue
  only when no job-specific liveness or progress has arrived for the configured interval.
  Keep a separate generous hard cap for runaway work if required operationally, but it must
  be much longer and surface as an explicit terminal policy failure—not a silent retry.
- Publish `queued`, `started`, `heartbeat/phase`, progress, and terminal events to SSE.
- Never publish terminal `done/failed` when the database status was set back to `queued` for
  an internal retry. Publish a nonterminal `requeued` event and keep the same job stream open.
- Add authenticated `GET /v1/jobs/{job_id}` returning the authoritative status, phase,
  timestamps, retry count, result/error, and conversation ID. This is the recovery snapshot
  for relay restarts and SSE gaps.
- Assign monotonically increasing SSE event IDs per job. Retain a bounded per-job ring buffer
  until a terminal TTL; do not `pop` it on first subscription. Accept `Last-Event-ID` and
  replay later events. No DB migration is required for an in-memory replay ring; after a
  relay process restart the job snapshot/database remains the recovery authority.
- Set `Cache-Control: no-cache, no-transform`, keep `X-Accel-Buffering: no`, and preserve the
  30-second comment keepalive. Add deployment/proxy tests proving frames are not buffered.

#### 3. iOS: replace stream-or-poll with a resumable job stream controller

- Expand `SSEEvent` to parse `id:`. Track the last event ID per active job.
- Model job state explicitly in `StreamingUpdate` instead of overloading `.messageSent` and
  message delivery status. At minimum support queued, running/phase, reconnecting,
  progress, completed, failed, and cancelled.
- Treat only a decoded terminal `done` or a terminal `GET /jobs/{id}` snapshot as
  `.finished`/`.failed`. Premature EOF is a transport interruption, never success.
- On transient SSE loss, query `GET /v1/jobs/{id}`:
  - completed → load the canonical final message once;
  - failed/cancelled → show the terminal result;
  - queued/running → reconnect SSE to the **same job** with `Last-Event-ID` and bounded
    exponential backoff/jitter.
- Continue reconnecting while the app is active and the job is nonterminal. When backgrounded,
  persist the job ID/last event ID and resume on activation; APNs/Live Activity handles
  background visibility.
- Delete the finite ~134.5-second client-side failure verdict. Polling may remain only as a
  low-frequency status safety net; it must never override a nonterminal server job.
- Show honest phases in the placeholder/Live Activity: `Queued`, `Starting on host`,
  `Thinking`, tool label, `Writing`, and `Reconnecting…`. A heartbeat updates liveness
  without pretending text was received.

#### 4. Retry semantics

- Automatic submit retry before a 202 response must reuse the same `clientMessageId` and
  therefore reattach to the existing job if the relay accepted the first request.
- Once a job ID is known, never POST the prompt again automatically. Reconnect/reattach by
  job ID.
- Manual Retry first queries the original job:
  - queued/running → reattach;
  - completed → load result;
  - failed/cancelled → offer an explicit **Run again** action that creates a new
    `clientMessageId` and explains that it is a new execution.
- Preserve the original user bubble and job identity across reconnects; do not remove and
  recreate messages merely because transport changed.

#### 5. Separate app presence from connector/job lifetime

Use these explicit rules:

| Event | Required behavior |
|---|---|
| iPhone active + job running | Maintain/reconnect the per-job SSE aggressively; show live phase; suppress completion APNs banner on that device. |
| iPhone backgrounded/suspended + job running | iOS SSE may disappear normally. Keep the relay/connector job running; deliver Live Activity/APNs completion; reattach when the app returns. |
| Host connector transiently disconnects + job running | Mark transport `reconnecting`, retain the job and lease during a bounded grace period, and allow the returning connector to resume the same job. Do not emit terminal failure immediately. |
| Host connector intentionally drains with no job | Clean offline transition; no error message in a chat. |
| Host connector intentionally stops during a job | Drain until terminal if possible, otherwise send an explicit `job.cancelled`/`job.aborted` terminal frame. Do not use the ambiguous “disconnected before completing” path. |
| Connector/process absent past grace with no resumable task | Terminal infrastructure failure or fenced requeue according to policy; never run two unfenced copies. |

Implementation details:

- Add a periodic iOS presence heartbeat (for example every 30 seconds) while `scenePhase ==
  .active`; send one explicit background transition and stop the heartbeat outside active.
  Presence reporting is best-effort and must not keep the app alive in background.
- Presence affects **delivery UX only**: foreground stream vs background push. It must never
  be used as authority to cancel or fail host execution.
- Move connector active-job ownership out of the local `_run_once` scope. Maintain a
  connection-independent active-job registry and an ordered bounded outbound event/result
  buffer. When the relay socket reconnects, the connector sends a `resume` hello containing
  active job IDs, lease/fencing tokens, last event sequence, and any buffered terminal result.
- The relay assigns a claim generation/fencing token when dispatching a job. Every connector
  progress/result/heartbeat carries it. Reject stale generations so a requeued old worker
  cannot publish after a newer execution owns the job.
- On host WebSocket loss, change the relay job transport state to `reconnecting` and start a
  grace timer instead of calling terminal `fail_message_job` in the WebSocket `finally` block.
  A same-host resume with the valid generation cancels the timer and continues the existing
  SSE/job identity.
- If the connector process itself died and cannot resume, requeue only after grace and only
  with a new fencing generation. Preserve the same relay job/client-message identity and
  surface `Recovering on host…` to iOS. Because Hermes tools may have external side effects,
  prefer recovery/status inspection over blind replay; automatic replay must be limited to
  jobs the connector can prove did not begin execution.
- On connector shutdown/service restart, implement a drain handshake: stop accepting new
  jobs, finish or explicitly cancel active jobs, flush terminal results, then close the
  WebSocket. Authentication revocation and operator-forced termination remain immediate.
- Replace the user-facing string “Hermes connector disconnected before completing the
  response” with state-aware messages. Transient loss is `Reconnecting to Hermes…`; only a
  terminal post-grace failure says the host connection was lost, with a safe Reattach/Run
  again choice based on authoritative job state.

### Required tests

- SSE ends cleanly without `done` while job remains running: iOS reconnects and never emits
  an empty `.finished` message.
- Wi-Fi → cellular handoff during reasoning/text streaming: reconnect with `Last-Event-ID`,
  no duplicated/missing final text, one completed message.
- Relay process restarts mid-job: iOS recovers from `GET /jobs/{id}` and resumes/finishes.
- More than 180 seconds of healthy job-specific heartbeats: job remains running and is not
  requeued.
- No job heartbeat/progress for the inactivity lease: one controlled retry/failure state,
  with no false terminal event while database state is queued.
- CLI fallback: continuous liveness/phase is visible although token deltas are unavailable.
- App backgrounds and foregrounds during a job: it reattaches to the same job.
- Keep Herald visibly active for more than two minutes: presence remains foreground and no
  duplicate completion push is shown.
- Background Herald mid-response: the iOS SSE can close without failing the host job; one
  completion push arrives and foregrounding reattaches/loads the same result.
- Drop the connector WebSocket for less than the reconnect grace while Hermes is still
  running: the same job resumes and its buffered result is delivered exactly once.
- Kill the connector process during a job: after grace the relay performs the fenced terminal
  recovery policy, never accepting a late result from the old generation.
- Graceful connector service restart while idle and while busy: idle closes cleanly; busy
  drains/resumes without the generic disconnect failure.
- Manual Retry on queued/running/completed/failed jobs follows the rules above.
- Duplicate POST with the same `clientMessageId` returns the same job and executes once.

### Acceptance criteria

- From Send until terminal result, the app always shows an authoritative live phase or an
  explicit reconnecting/offline transport state—never an unexplained wait.
- A healthy five-minute tool run is not failed or retried by a 120/134/180-second client or
  relay timer.
- Network interruption reattaches to the same job and resumes updates.
- Backgrounding the iPhone never terminates host work, and a transient host WebSocket drop
  does not become a terminal chat error.
- Exactly one Hermes execution and one assistant result occur unless the user explicitly
  chooses **Run again** after a terminal failure.

---

## P1 — Remove the iPhone system-generated three-dot overflow

### Confirmed root cause

The screenshot's top-right circle with `…` is SwiftUI toolbar overflow, not Herald's
`TypingDotsView`.

- `ChatScreen` always installs `toolbarContent` at
  `Herald/Features/Chat/ChatScreen.swift:64-66`.
- The leading item packs hamburger + profile + model/status + timer at
  `Herald/Features/Chat/ChatScreen.swift:156-176`.
- The trailing item adds Canvas + Settings at
  `Herald/Features/Chat/ChatScreen.swift:178-195`.
- The model chip explicitly uses `.fixedSize(horizontal: true, ...)` at
  `Herald/Features/Chat/ChatScreen.swift:292-320`, so it resists compression.
- The profile chip's label is not width-bounded at
  `Herald/Features/Chat/ChatScreen.swift:228-253`.
- iPhone already has a dedicated Settings tab at `Herald/ContentView.swift:37-45`, making
  the toolbar gear redundant.

### Concrete fix path

Create separate toolbar compositions for phone and pad; do not try to fix this only by
lowering font sizes.

- **iPhone leading:** session drawer/hamburger only.
- **iPhone principal:** one bounded status control that shows compact connection/model state
  and opens the existing context popover. Cap its width and remove horizontal `fixedSize`.
- **iPhone trailing:** Canvas only. Remove the duplicate Settings gear on phone.
- Put profile switching inside the existing context/status presentation or session drawer so
  it remains reachable without consuming another toolbar slot.
- Keep the richer profile/model/timer presentation for wide iPad content.
- Add accessibility labels to every icon-only control.

Do not replace the system overflow with a hand-authored ellipsis menu; the user explicitly
wants the three dots gone.

### Required tests

- Add a compact-width SwiftUI/UI-test configuration with the longest realistic profile and
  model names.
- Verify iPhone portrait at the smallest supported width, Display Zoom, and an accessibility
  Dynamic Type size.
- Verify toolbar controls remain accessible by VoiceOver labels.

### Acceptance criteria

- No top-right `…` appears on any supported iPhone width or text-size setting.
- Drawer, model/profile controls, timer/context status, and Canvas remain reachable.
- Settings remains reachable through the bottom tab.

---

## P1 — Mount the iPad UI and make landscape a true three-panel layout

### Confirmed root causes

1. **The adaptive root is dead code.** `AppRootView` renders `MainTabView()` directly at
   `Herald/Features/Onboarding/AppRootView.swift:12-20`. Repository search finds no live
   `AdaptiveRootView()` call. Therefore every iPad gets the iPhone TabView regardless of
   orientation.

2. **Even if mounted, the current adaptive layout is not three columns.** It creates a
   two-column `NavigationSplitView` and overlays the right inspector over the content at
   `Herald/Features/Sidebar/AdaptiveRootView.swift:27-46`.

3. **The inspector defaults closed.** `isRightPanelOpen` starts `false` at
   `Herald/Features/Sidebar/AdaptiveRootView.swift:8-10`, so wide landscape would still not
   show it.

4. **Router/sidebar state is disconnected.** `TabRouter` offers an
   `oniPadSectionSwitch` callback at `Herald/Core/Router.swift:66-69`, but
   `AdaptiveRootView` never installs it. Notification navigation currently changes
   `router.selectedTab`, while the iPad view uses a private `selectedSection` state, so the
   two can disagree.

### Concrete fix path

1. In `AppRootView`, render `AdaptiveRootView()` after onboarding instead of
   `MainTabView()`. `AdaptiveRootView` remains responsible for choosing `MainTabView` on
   iPhone.

2. Replace the inspector overlay with the three-column initializer:
   - sidebar: `iPadSidebarView` and session browser;
   - content: selected Chat/Inbox/Talk/Settings screen;
   - detail: `iPadRightPanelView` with Logs/Terminal/Tools/Canvas.

3. Drive split visibility from available geometry/window width, not physical orientation
   APIs. A full-width landscape iPad must default to all three columns. Portrait and narrow
   Stage Manager/Split View widths may collapse the inspector while retaining sidebar +
   content. Preserve the user's explicit inspector toggle during a scene session.

4. Unify navigation state:
   - synchronize `selectedSection` with `router.selectedTab`, or make the router the single
     source of truth;
   - install and remove `oniPadSectionSwitch` with the adaptive view lifecycle;
   - ensure a notification selecting Chat changes the visible iPad content, not only the
     hidden iPhone tab value;
   - ensure Settings presentation selects the iPad Settings section rather than opening an
     iPhone-style sheet.

5. Avoid nesting duplicate `NavigationStack`s around Chat when the split column already owns
   navigation. Keep route destinations available for permissions/capture/connect-host.

### Required tests

- iPad full-width landscape: sidebar + main content + inspector visible simultaneously.
- iPad portrait: usable adaptive collapse with no clipped 300-point overlay.
- iPad Split View/Stage Manager narrow width: no forced three-column squeeze.
- Switch every sidebar section and verify router state follows.
- Open a chat notification on iPad while Inbox or Settings is selected; Chat becomes visible
  and the correct conversation loads.
- iPhone portrait remains `MainTabView` with the session drawer and bottom tabs.

### Acceptance criteria

- Full-width iPad landscape opens with three genuine, independently laid-out panels.
- The inspector no longer covers chat content.
- Rotation and window resizing preserve a coherent selection and do not duplicate screens.
- iPhone behavior is unchanged except for the intentional toolbar cleanup.

---

## Implementation order and commit boundaries

1. **Resumable live job connection** — job heartbeat/renewable lease, resumable SSE + status
   snapshot, iOS state machine, reattach-only retry. This is the first release/version
   reconciliation because it fixes core execution correctness.
2. **Notification metadata + crash-safe routing** — relay broker/direct parity, pending route,
   direct load-by-ID, diagnostic tests.
3. **Notification actions** — Read/Reply/Nudge plus real connector-backed Stop. Separate
   version/changelog/commit because it introduces a new cross-tier capability.
4. **iPhone toolbar** — compact phone-specific composition, screenshots/UI tests.
5. **iPad adaptive root + three columns** — mount adaptive root, unify router state, replace
   overlay, iPad UI tests.

Before claiming completion, run the relevant relay and connector tests, generate the Xcode
project, unlock the keychain, build both app and widget targets, and exercise the four device
acceptance flows. If `pytest` is unavailable on the Mac shell, use the repository's documented
Python environment instead of skipping the backend tests.
