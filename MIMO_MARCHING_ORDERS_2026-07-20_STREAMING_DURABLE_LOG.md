# Herald — Mimo Marching Orders: Durable Streaming + Hermes-Native Talk

**Prepared:** 2026-07-20
**Audience:** Mimo `mimo-v2.5` (or any coding agent)
**Starting point:** git commit `c658d39` (master), version `project.yml` `1.3.3 / build 22`
**Assessment mode:** source reviewed read-only; this document is the only file created. No code was changed.
**Source specs:**
- `HERALD_STREAMING_FEATURE_REQUEST.md` → **Track A** (durable job event log)
- `HERALD_TALK_MIMO_FEATURE_REQUEST.md` → **Track B** (Hermes-native, MiMo-voiced Talk)

Both were reviewed together and grounded in `file:line`. **They are not independent:** Track B's
Hermes-native voice turn is built on the durable streaming coordinator delivered by Track A.
See **"Continuity between the two tracks"** below before sequencing work.

---

## Continuity between the two tracks (read first)

The two feature requests describe **one** conversation substrate with two front-ends. Track B
(Talk) explicitly asks to *reuse* the normal Hermes message/job stream (`HERALD_TALK…md` lines
88-90, 163-169, 203) rather than the current parallel `talk.delegate` path. That "normal stream"
is exactly what Track A rebuilds into a durable, resumable coordinator. Consequences:

1. **Track B depends on Track A Phase 2.** The Talk `TalkTurnClient` must wrap the new
   `JobStreamCoordinator` + `JobEventReducer` (Track A §2b/2c), **not** the legacy one-shot
   `LiveHeraldClient.streamJobEvents`. Build Talk's Hermes-native turn *after* the durable
   coordinator exists, or you re-inherit D2/D4 (no resume, false-fail on EOF) inside voice.
2. **One idempotency identity across text and voice.** A Talk utterance submits with a stable
   `clientMessageId` and the selected `conversationId`, same as chat (Track A invariant 4). A
   dropped ASR/TTS/SSE must reattach the same job — never resubmit a new turn
   (`HERALD_TALK…md` line 280). This is the same "transport is not execution" invariant (A-9).
3. **`SpeechTextRenderer` gets correct for free once events are structured.** Track B must never
   speak reasoning, tool labels, or Markdown control markers (`HERALD_TALK…md` lines 156, 222).
   Today that text is *produced* by the Markdown-marker scraper (Track A D6,
   `herald_api_executor.py:18`). After Track A Phase 3 emits semantic `reasoning.*`/`tool.*`
   events, the renderer simply drops non-`message.*` segments instead of regex-stripping prose.
   Do Track A Phase 3 first and the renderer is a filter, not a parser.
4. **Ending Talk injects no duplicate transcript.** Because the durable log already holds every
   turn (Track A `job_events`), Track B must **delete** end-of-session transcript injection
   (`relay/app/main.py:1591` `inject`; iOS injection in `LiveVoiceSessionService`) for
   Hermes-native turns. This resolves `HERALD_TALK…md` product req 4 and acceptance
   "ending a session does not duplicate messages."
5. **Shared version/CHANGELOG/xcodegen discipline** (ground rules) applies to both tracks. A
   commit may touch Track A or Track B, never silently both.

**Net sequencing:** Track A Phases 0–3 land first (they fix the observed streaming bugs *and*
unblock voice). Track B Phase T0 (contract spike) can run in parallel with Track A. Track B
Phase T1 (Hermes-native push-to-talk) must not merge before Track A Phase 2. See the combined
commit sequence at the end.

---

## Source spec (Track A): `HERALD_STREAMING_FEATURE_REQUEST.md`

---

## Decisions already made (do not re-litigate)

1. **Database backend for the durable log = Postgres.** The field relay at `192.168.10.118:8010`
   runs Postgres via `DATABASE_URL`. `relay/app/config.py:26` still defaults to
   `sqlite:///./relay.db` for local dev, and `relay/app/database.py:16` branches on
   `is_sqlite`. **Design the `seq` allocation and job-row locking for Postgres**
   (`SELECT … FOR UPDATE`, real multi-worker fan-out). The code must still *import and run*
   under SQLite for local tests, but the multi-worker/row-lock correctness guarantees are only
   promised on Postgres. Where a construct is Postgres-only (e.g. `with_for_update()`), guard it
   so SQLite dev falls back to its implicit single-writer lock rather than crashing.
2. **Scope = full Phases 0–4**, including the new `HermesGatewayExecutor` (structured Hermes
   event protocol) and eventual v1 removal. Phase 3 depends on the Hermes host exposing the
   JSON-RPC gateway (`/api/ws`); if that endpoint is not reachable on `fih-ai-host`, Phase 3
   ships the adapter + capability probe but leaves `openai_v1_fallback` as the live path until
   the host is upgraded. **Confirm gateway reachability before starting Phase 3 code.**

### Track B (Talk) decisions — adopting the source doc's recommendations for this self-hosted, single-user deployment

These match `HERALD_TALK_MIMO_FEATURE_REQUEST.md §"Decisions to make"`. Herald here is
self-hosted, single-user (Curtis on `fih-ai-host`); the recommended defaults apply cleanly.
**If any of these is wrong for a future multi-user/managed-billing product, stop and re-scope
the relay work before building — the credential boundary in particular changes tier ownership.**

3. **Credential boundary = personal MiMo key in iOS Keychain** (not a relay proxy). Herald does
   not offer managed speech billing, so the phone talks to MiMo directly with the user's own
   key. Relay gets **no** ASR/TTS proxy endpoints in this scope. Migrate the key off
   `UserDefaults` (`SettingsScreen.swift:531,540`) into `KeychainSecureStore`.
4. **ASR default = MiMo `mimo-v2.5-asr`**, with an explicit local **Apple Speech fallback**
   (reuse `LiveSpeechService` capture) for users who decline cloud ASR.
5. **Endpointing = push-to-talk for Phase T1**, then calibrated local VAD in Phase T2.
6. **Response start = canonical completed Hermes text for T1**; early sentence-boundary
   synthesis only in Phase T3 after latency telemetry justifies it.
7. **Legacy OpenAI Realtime Talk = retained one migration release behind a clearly named
   compatibility flag**, then removed (its `talk.delegate`/`hermes_delegate` MCP path) if usage
   does not justify two stacks. It must not be labeled "Hermes-native Talk."

---

## Ground rules — read before editing

1. **One logical change = one commit = one dated `CHANGELOG.md` entry.** Do not fold multiple
   phases under a generic "streaming fixes" commit. Each phase below is at least one PR.
2. Every shippable change must:
   - bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for **both** `Herald` and
     `HeraldWidgets` in `project.yml` (currently `1.3.3` / `22` at `project.yml:80-81,137-138`);
   - update the README version badge;
   - add a dated `CHANGELOG.md` entry naming the behavior and files changed;
   - update relevant README/docs text;
   - run `xcodegen generate` (`project.yml`, not the generated `.xcodeproj`, is authoritative).
3. **The relay has no migration framework.** Schema changes are hand-written `_exec_safe(...)`
   statements in `relay/app/database.py` (see the existing block around `database.py:60-79`).
   New tables/columns ship as explicit idempotent DDL there **plus** the SQLAlchemy model, and
   the marching orders must include the exact `CREATE TABLE` / `ALTER TABLE` and operator
   run instructions. Never assume auto-migration.
4. **Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`.** New actors/reducers must be `Sendable`.
   Do not silence with `@unchecked Sendable`. Store/UI mutation stays on `@MainActor`.
5. **Do not hardcode secrets.** iOS → Keychain; relay/connector → env.
6. **`fih-ai-host` OOM/freeze history:** accepted-but-slow work is **not** failure. Nothing in
   this change may auto-retry or auto-fail a job merely because first token is slow or the host
   is briefly unreachable. This is the whole point of the watchdog fix (P0-6).
7. Unlock the Mac login keychain before **every** `xcodebuild`.
8. **Additive contract.** v2 events ship behind a relay capability (`job_stream_contract: 2`)
   with a v1 compatibility decoder retained until Phase 4. Never break a v1 client mid-rollout.

## Environment

| Thing | Value |
|---|---|
| **App repo** | `/Users/curtisfreeman/Herald` (git; branch history uses "build N" commits) |
| **iOS app** | `Herald/` target; Swift 6.2; strict concurrency complete; iOS 26 APIs for new UI |
| **Widgets** | `HeraldWidgets/`; App Group `group.net.fihonline.herald` |
| **Relay** | `relay/` FastAPI + SQLAlchemy; **Postgres in field**, SQLite dev; **no migrations → manual `_exec_safe` DDL in `database.py`**; field host `192.168.10.118:8010` |
| **Connector** | `connector/src/herald_connector/`; WebSocket RPC dispatcher in `client.py`; runs beside Hermes on the host |
| **Hermes host** | `fih-ai-host` at `192.168.10.118`; accepted-but-slow work must not be retried; hard-freezes multiple times/day |
| **Coding model** | Mimo `mimo-v2.5` |
| **Build machine** | MacBook Pro; unlock login keychain before each `xcodebuild` |
| **Project generation** | XcodeGen; edit `project.yml`, then run `xcodegen generate` |
| **Bundle / team** | `net.fihonline.herald` / `58U7UPFS53` |
| **Secrets** | iOS Keychain; relay/connector environment; never commit secrets |

---

## Confirmed defects — Track A (streaming), grounded in the working tree at `c658d39`

Each row was verified by reading the cited line, not from the spec.

| # | Sev | Defect | Evidence (`file:line`) |
|---|-----|--------|------------------------|
| D1 | P0 | Relay assigns `event["eventId"]` but the SSE writer never emits an `id:` line and serializes only `event["data"]`, so the sequence never reaches the wire. | `relay/app/main.py:308` (assigns `eventId`) vs `relay/app/main.py:2435-2441` (`emit_event` writes `event:`/`data:` only), and `:2433`, `:2463` (done frame, no `id:`). |
| D2 | P0 | iOS parses `id:` correctly but the relay never sends one, and `streamEvents(path:accessToken:)` has no cursor parameter and `makeRequest` never sets `Last-Event-ID`. | `Herald/Services/Support/RelayAPIClient.swift:191` (signature), `:258-259` (parses `id:`), `:160-184` (`makeRequest`, no `Last-Event-ID`). `lastEventID` is tracked at `LiveHeraldClient.swift:428,448` but is always `nil`. |
| D3 | P0 | `.messageSent` (relay merely *accepting* the job) yields the watchdog progress signal, disarming the 120s stall watchdog — directly contradicting the comment 25 lines above it. | `Herald/Stores/ChatStore.swift:234-237` (`case .messageSent: … progressContinuation?.yield(())`) vs the contract comment at `:209-211`. |
| D4 | P0 | On premature SSE EOF, if `getJobStatus` reports the job is still `queued`/`running`, iOS emits `.failed("Stream interrupted — job still …")` and finishes instead of reattaching. | `Herald/Services/Live/LiveHeraldClient.swift:258-260`; EOF path throws `StreamInterruptionError.prematureEnd` at `:491`, one-shot status check at `:240`. |
| D5 | P0 | Relay replay state is process-local and **destructive**: the pre-subscription buffer is `pop`-ed by the first subscriber, so restart / a second subscriber / multi-worker loses replay history. | `relay/app/main.py:286` (`app.state.job_event_buffers.pop(job_id, [])`), buffer capped/dropped at `:314-315`. |
| D6 | P0 | Connector derives tool activity by regex-scraping Markdown markers out of OpenAI-compatible assistant content. Presentation text and control events are coupled. | `connector/src/herald_connector/herald_api_executor.py:18` (`TOOL_PROGRESS_RE = re.compile(r"\n\`([^\n]+)\`\n")`), buffer/marker logic `:245,:305-313`. |
| D7 | P1 | iOS "auto retry" re-sends the same `clientMessageID`/bubble; the relay dedupes it back to the same job. It is a reattach mislabeled as retry. | `Herald/Stores/ChatStore.swift:181-184` (`stallRetryCounts`, `continue // re-send with the same bubble/IDs`), `maxAutoRetries` `:21`. |
| D8 | P1 | SSE queue-full drops whichever event arrives next — including a possible terminal `done`. | `relay/app/main.py:320-325`. |
| D9 | P1 | Connector `job.progress` frames carry no `source_seq`/`attempt`; there is no idempotency key for dedup on reconnect. | `connector/src/herald_connector/client.py:977-1004`. |
| D10 | P1 | The SSE completed-job fast path recognizes only `completed`/`failed`, never `cancelled`; `wait_for_job_completion` has the same gap. | `relay/app/main.py:2396` (`if job.status in ("completed", "failed")`), and `:341` (`{"completed", "failed"}`). |
| D11 | P1 | iOS uses one mutable stream slot (`streamingMessageID`/`streamingTask`) rather than job-keyed state; a session switch can redirect events into the wrong placeholder. | `Herald/Stores/ChatStore.swift:14-15`, cleared/overwritten at `:134,:319,:354,:378,:429`. |
| D12 | P2 | `MessageJob` has `claimed_connection_nonce` and `lease_expires_at` but **no `attempt` column**, and there is **no `JobEvent` model**. The durable log is net-new schema. | `relay/app/models.py:262` (`class MessageJob`), `:270,:273`; no `JobEvent` anywhere in `models.py`. |

---

## Confirmed defects — Track B (Talk), grounded in the working tree at `c658d39`

| # | Sev | Defect | Evidence (`file:line`) |
|---|-----|--------|------------------------|
| T1 | P1 | Hermes is not the guaranteed answer owner. Talk creates an **OpenAI Realtime** session that owns transcription/response/VAD/audio and only *optionally* calls `hermes_delegate`. A voice turn can be answered without ever reaching Hermes → persona/memory/model/history diverge from chat. | Connector `_create_openai_realtime_session` + OpenAI realtime secrets URL `connector/src/herald_connector/client.py:212,577`; delegate-only prompt `talk_support.py:221`; relay MCP tool `relay/app/talk_mcp.py:28,208`. iOS transport `Herald/Services/Live/LiveVoiceSessionService.swift:5,50,122-126` (WebRTC/`RealtimeSession`/`dataChannel`). |
| T2 | P1 | `MimoTTSService` is a whole-file, non-streaming proof of concept: requests `format: wav`, waits for the full HTTP body, decodes one base64 blob, plays via `AVAudioPlayer` only after synthesis finishes. No first-audio latency, queue depth, chunk error, or cancellation. `isPlaying` conflates network synthesis with device playback. | `Herald/Services/Live/MimoTTSService.swift:60` (`"format": "wav"`), `:93` (single base64 decode), `:27,109` (`AVAudioPlayer` post-synthesis), `:22` (`isPlaying`). |
| T3 | P0 (security) | The MiMo API key — a credential — is written to and read from `UserDefaults`, not the Keychain. | `Herald/Features/Settings/SettingsScreen.swift:531,540` (`UserDefaults.standard.set(… "mimo.apiKey")`), `:598` (read). |
| T4 | P1 | End-of-session transcript injection creates a parallel write path. With Hermes-native turns the messages already exist, so injection duplicates the conversation. | Relay `inject` endpoint `relay/app/main.py:1591`; connector `talk.delegate` maintains a **separate** Hermes session per voice session `client.py:1199-1200`. |
| T5 | P1 | MiMo auth header is unverified against the API contract: Herald sends `Authorization: Bearer`, MiMo cURL docs use `api-key`. Shipping without an integration test risks silent 401s. | `MimoTTSService.swift:67` (`Authorization: Bearer`) vs MiMo docs `api-key` header. |
| T6 | P2 | Three services each mutate the global `AVAudioSession` independently (record-only vs playback vs Realtime), so record/play transitions and Bluetooth/speaker routing are unreliable. | `LiveSpeechService` (record-only capture), `MimoTTSService` (playback), `LiveVoiceSessionService` (Realtime) all touch `AVAudioSession`. |
| T7 | P2 | `talk.prewarm`/readiness validates OpenAI key + Realtime model rather than "connector online + Hermes conversation ready + MiMo capability." Readiness reports the wrong thing for a Hermes-native pipeline. | Connector `_rpc_talk_prewarm` `client.py:1241`; readiness `client.py:631-644`; relay `/v1/talk/readiness`. |

---

## Reliability invariants (the acceptance bar for every item)

These are the invariants from the spec, restated as the pass/fail contract. Every commit must
say which invariant it preserves.

1. **One execution owner:** only the relay creates/requeues attempts.
2. **One ordered log:** all presentation events for a job share a monotonically increasing `seq`.
3. **Append before fan-out:** an event is durable before any SSE subscriber can observe it.
4. **At-least-once transport, exactly-once projection:** re-applying a seen `seq` is a no-op.
5. **Terminal dominance:** `completed`/`failed`/`cancelled` are immutable; exactly one terminal
   event per job; late nonterminal events are rejected.
6. **Attempt fencing:** events from an expired lease/attempt cannot mutate the current attempt.
7. **Boundary ordering:** buffered deltas flush before tool/segment/terminal events.
8. **Snapshot convergence:** the terminal event carries the canonical final message, not a flag.
9. **Transport is not execution:** SSE EOF / timeout / auth refresh / suspension never changes
   job state.
10. **Unknown additive events survive:** store, advance cursor, log/measure, continue.

---

# Work plan (phased; each phase is at least one PR)

> **Two tracks.** Track A phases are numbered `0–4`; Track B (Talk) phases are `T0–T3`.
> Track B `T1` must not merge before Track A `Phase 2`. `T0` may run in parallel with Track A.

# Track A — Durable, ordered, resumable job event log

## Phase 0 — Lock the contract with fixtures (no behavior change)

**Goal:** freeze the v2 envelope and event vocabulary as checked-in golden data before any layer
moves, so connector mapping, relay serialization, Swift decoding, and the reducer are all tested
against the *same* traces.

**Do:**
- Create `docs/STREAM_CONTRACT_V2.md`: the envelope (`contractVersion, jobId, conversationId,
  attempt, seq, type, timestamp, payload`), the event vocabulary table, terminal rules
  (`run.completed`/`run.failed`/`run.cancelled` only, exactly one), and the v1↔v2 compatibility
  map.
- Add golden fixtures under `connector/tests/fixtures/hermes/` and a shared copy consumed by iOS
  tests (`HeraldTests/Fixtures/StreamContractV2/`): text-only, reasoning, multiple interleaved
  tools, commentary, approval, error, cancellation, and a `/goal` continuation.
- Define the shared Python models in `connector/src/herald_connector/stream_contract.py` (new)
  and the Swift envelope in `Herald/Models/JobEvent.swift` (new). They must decode the same
  fixtures byte-for-byte.

**Acceptance:** fixtures parse in Python and Swift; a golden test asserts each fixture's event
sequence and terminal event; `docs/STREAM_CONTRACT_V2.md` is the single source of truth.

**Invariants exercised:** 2, 5, 8, 10.

---

## Phase 1 — Durable relay event log + real SSE replay (behind capability flag)

This is the highest-leverage phase: it fixes D1, D5, D8, D10 and makes resume *possible*.

### 1a. New `job_events` table (D12)

Add SQLAlchemy model `JobEvent` in `relay/app/models.py` and idempotent DDL in
`relay/app/database.py` alongside the existing `_exec_safe(...)` block (`database.py:60-79`):

```sql
CREATE TABLE IF NOT EXISTS job_events (
    id            TEXT PRIMARY KEY,
    job_id        TEXT NOT NULL REFERENCES message_jobs(id),
    seq           BIGINT NOT NULL,
    attempt       INTEGER NOT NULL,
    source_seq    BIGINT NOT NULL,
    type          TEXT NOT NULL,
    payload_json  JSONB NOT NULL,          -- TEXT on SQLite dev
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_job_events_job_seq        ON job_events(job_id, seq);
CREATE UNIQUE INDEX IF NOT EXISTS ux_job_events_job_attempt_src ON job_events(job_id, attempt, source_seq);
CREATE INDEX        IF NOT EXISTS ix_job_events_job_seq         ON job_events(job_id, seq);
```

Operator note (put in the CHANGELOG + a `docs/` runbook line): run these against the field
Postgres before deploying the new relay; they are idempotent.

Add `attempt` to `MessageJob` (`models.py:262`) plus `ALTER TABLE message_jobs ADD COLUMN IF
NOT EXISTS attempt INTEGER NOT NULL DEFAULT 0;`.

### 1b. Transactional append + snapshot (invariants 2, 3, 4)

Extract the queue/SSE machinery out of `main.py` into `relay/app/streaming.py` (new) and add an
append service in `relay/app/services.py`. The ingest of every connector event runs in one DB
transaction:

1. `SELECT … FOR UPDATE` the `message_jobs` row (Postgres; SQLite falls back to its implicit
   write lock — guard `with_for_update()` on `is_sqlite`).
2. Validate: job nonterminal, `attempt` matches the current claimed attempt, connection nonce
   matches `MessageJob.claimed_connection_nonce` (`models.py:270`), schema valid.
3. Dedup on `UNIQUE(job_id, attempt, source_seq)` — a duplicate is a no-op success.
4. Allocate the public `seq = COALESCE(MAX(seq),0)+1` for the job and insert the `JobEvent`.
5. Update the materialized job snapshot fields (partial text/reasoning/tools/phase) and lease.
6. Commit.
7. **Then** notify local subscribers (wake-up only; the notification carries no payload).

Replace the destructive in-memory buffer at `main.py:282-325` with this. `publish_job_event`
(`:304`) becomes "append to `job_events` then wake"; `subscribe_job_events` (`:282`) stops
`pop`-ing (D5) and instead the SSE endpoint queries `job_events`.

### 1c. Rewrite `GET /v1/jobs/{job_id}/events` (D1, D5, D8, D10)

At `relay/app/main.py:2378`:
- Read cursor from the `Last-Event-ID` header; accept `?after=<seq>` fallback.
- Replay all persisted `seq > cursor` ascending **from the DB**, emitting a real SSE frame with
  an `id: <seq>` line for every data event (fixes D1 — `emit_event` at `:2435` must add the
  `id:` line and serialize the full envelope, not just `event["data"]`).
- Then subscribe, wait on the wake-up, and re-query — the notifier never carries payload
  (survives restart/multi-worker/dropped notifications).
- Keepalive comments (`: keepalive`, `:2480`) consume no `seq`.
- Support unlimited concurrent subscribers with no destructive reads.
- Terminal fast path recognizes `completed`, `failed`, **and `cancelled`** (fixes D10 at
  `:2396`; also fix `wait_for_job_completion` at `:341`).
- If the requested cursor is older than retained history, emit `stream.reset` with the full
  current projection and `baseSeq`.
- Queue overflow must never drop a terminal event (fixes D8): terminal events bypass the lossy
  path; correctness comes from the DB query, so a slow consumer just re-reads.

### 1d. Snapshot endpoint additions

`GET /v1/jobs/{job_id}` (`main.py:2272`) must expose `attempt`, `lastSeq`, `phase`,
`leaseExpiresAt`, and a `projection` (partial `text`/`reasoning`/`tools`); terminal responses add
canonical `message`, `usage`, `diff`, sanitized `error`. Fields are additive — v1 clients ignore
them.

### 1e. Retention

Bounded history: keep `job_events` for a configurable window (default 24h) **after terminal
state**. Never expire events for a nonterminal job.

**Acceptance (Phase 1):**
- SSE frames carry `id: <seq>`; `?after=` and `Last-Event-ID` replay return only `seq > cursor`.
- Kill+restart the relay mid-job → replay continues from Postgres.
- Two subscribers on one job both get the full stream.
- A slow consumer cannot lose the terminal event.
- Attaching after `cancelled` returns terminal immediately.
- Transaction-failure test: an uncommitted event is never observable by any subscriber.

**Invariants exercised:** 2, 3, 4, 5, 8, 9.

---

## Phase 2 — Resilient iOS coordinator + reducer + watchdog fix

Fixes D2, D3, D4, D7, D11. Ship behind the relay capability `job_stream_contract: 2`; keep a v1
compatibility decoder.

### 2a. `RelayAPIClient.streamEvents` takes a cursor (D2)

At `RelayAPIClient.swift:191`: add a `lastEventID: String?` parameter; when non-nil set the
`Last-Event-ID` header in `makeRequest` (`:160`). Preserve transport failures as typed errors.
At EOF, flush a final partially-parsed frame **only** if SSE-terminated; otherwise reconnect from
the prior cursor rather than discarding (`:263`).

### 2b. `JobStreamCoordinator` actor (D4, D11)

New `Herald/Services/Live/JobStreamCoordinator.swift`, keyed by `jobId` (not the single
`streamingMessageID` slot). Responsibilities:
- Open SSE with persisted `Last-Event-ID`; decode `JobEventEnvelope`; reject wrong-job events;
  detect `seq` gaps (pause, reconnect from last contiguous seq, never append past a gap).
- Bounded exponential backoff + jitter on transport/auth failure.
- After each disconnect, `GET /v1/jobs/{job_id}`: terminal → apply snapshot; `queued`/`running`
  → **reconnect** (this is the D4 fix — never `.failed` for a live job); expired → recoverable
  protocol error + conversation refresh.
- Survive background/foreground; persist `(jobId, conversationId, clientMessageId, placeholderId,
  lastAppliedSeq)`; reattach on conversation open / app foreground.
- Stop only on a terminal event, confirmed local cancel, or nonretryable protocol/auth error.

Replace the `LiveHeraldClient.streamJobEvents` one-shot loop (`LiveHeraldClient.swift:227,422`)
and delete the `queued`/`running` → `.failed` branch (`:258-260`).

### 2c. Pure `JobEventReducer` (invariant 4)

New reducer producing `JobProjection` (per the spec's struct). Returns the unchanged projection
for duplicates (`seq <= lastAppliedSeq`) and stale attempts; correlates tools by `toolCallId`;
preserves multiple assistant segments around tool boundaries; applies terminal snapshot
atomically. `ChatStore` **observes projections** instead of concatenating events in the big
switch at `ChatStore.swift:231-390`. Delta-flush throttling stays a view concern *after*
reduction. Replace `streamingMessageID` (`:14-15`) with a job→placeholder map (D11).

### 2d. Watchdog becomes an inactivity monitor (D3)

At `ChatStore.swift:224-237`:
- `.messageSent`/`job.accepted` must **not** yield the progress signal (delete the
  `progressContinuation?.yield(())` at `:237`).
- `run.started`, heartbeat, text/reasoning/tool, requeue, and terminal events reset the deadline.
- `queued` jobs enter a separate "waiting for host" state — no auto-fail (respects the OOM/freeze
  reality in ground rule 6).
- On deadline expiry, fetch authoritative status first; reconnect/wait if nonterminal; **never**
  repost the message.
- Make durations injectable (`watchdogTimeout` `:20`) so tests run in ms.
- Remove/rename `maxAutoRetries`/`stallRetryCounts` (`:21,:25`) — client-side resend of the same
  `clientMessageID` (D7, `:181-184`) is not a retry; the relay lease owns retries (Phase 3).

**Acceptance (Phase 2):**
- Disconnect after every event boundary → resume at `lastAppliedSeq+1`, no dup.
- Background 1/30/300s during text/reasoning/tool → converges to live or terminal.
- Token rotation mid-SSE → refresh + resume, no lost events.
- Session switch mid-stream → events stay on the originating job.
- App restart from persisted cursor → reattaches.
- Regression test: `.messageSent` does **not** disarm inactivity detection.

**Invariants exercised:** 1, 4, 6, 9, 10.

---

## Phase 3 — Structured Hermes connector adapter (D6, D9)

**Precondition:** confirm `fih-ai-host` exposes the Hermes JSON-RPC gateway (`/api/ws`). If not,
ship the adapter + capability probe but keep `openai_v1_fallback` as the live path.

- New `connector/src/herald_connector/hermes_gateway_executor.py`: speak the Hermes Desktop
  JSON-RPC WS protocol — capability-probe, start/resume session, `prompt.submit`, correlate by
  explicit `session_id` + current job `attempt`, map `message.*`/`reasoning.*`/`tool.*`/approval/
  error into the v2 vocabulary, use `message.complete.payload.text` as canonical, fence + discard
  late events after interrupt/attempt rollover.
- Connector attaches `attempt` + monotonic `source_seq` to every emitted frame (fixes D9 at
  `client.py:977-1004`), and coalesces only adjacent same-segment deltas **before** durable
  append so replay == live.
- Runs API (HTTP) is the fallback but passes through the **same** `HermesEventAdapter` +
  terminal reconciliation.
- Remove `TOOL_PROGRESS_RE` (D6, `herald_api_executor.py:18`) from the primary path; it may
  remain only inside the temporary v1 compatibility adapter.
- Report the active adapter (`gateway_v2` / `runs_v2` / `openai_v1_fallback`) in connector
  diagnostics.

**Acceptance:** golden mapping tests gateway-frame→v2; stable `toolCallId`/segment/`source_seq`;
late-event fencing; Runs API fallback terminal reconciliation; **regression proving ordinary
Markdown (backticks/code fences) can never be classified as tool activity.**

**Invariants exercised:** 2, 5, 6, 7, 8.

---

## Phase 3.5 — Server-owned attempts / lease retry (D7 completion)

- Increment `MessageJob.attempt` atomically on lease claim (not on iOS reconnect).
- Include `attempt` + lease fence in the connector execute frame (`build_job_execute_payload`,
  `main.py:637`).
- Expired lease → requeue the **same** job, append `run.requeued` (`fromAttempt`/`toAttempt`),
  never a second user message.
- Cap attempts in relay config; on exhaustion emit exactly one nonretryable terminal event.
- Retryable connector error keeps SSE open + job nonterminal.
- Optional explicit manual-retry endpoint only if product wants a *new* execution after terminal
  failure (creates a new job linked to the original intent).

**Acceptance:** lease expiry → exactly one new attempt, all old-attempt events fenced; reposting
the same `clientMessageId` never creates a duplicate job/user message; terminal-vs-Stop race →
one immutable terminal state.

**Invariants exercised:** 1, 5, 6.

---

## Phase 4 — Remove v1 streaming

Only after dogfood metrics show adoption and `openai_v1_fallback` usage under the agreed
threshold. Require a minimum connector/relay version, then delete: in-memory replay buffers, the
Markdown marker parser, fake word-by-word streaming, and client-side "retry."

---

# Track B — Hermes-native, MiMo-voiced Talk

**Architecture:** replace the speech-to-speech OpenAI Realtime agent with a composed
`ASR → Hermes → TTS` pipeline. MiMo replaces only the speech edges; **Hermes owns every turn**
via the Track A durable stream. Target shape:

```text
TalkAudioCapture -> MimoASRService -> TalkTurnClient(JobStreamCoordinator) -> SpeechTextRenderer -> MimoTTSService(stream) -> PCMPlaybackQueue
```

A single `HermesTalkCoordinator` actor owns the state machine
(`idle→preparing→listening→endpointing→transcribing→thinking→synthesizing→speaking→listening`,
plus `interrupted|failed|ending`) and is the **sole owner of `AVAudioSession`** during Talk (fixes
T6). Keep `TalkStore`, `TalkSessionSnapshot`, `VoiceOrb`, `TranscriptView`, and Live Activity;
replace OpenAI-specific state meanings with provider-neutral states and add explicit
`transcribing`/`synthesizing`.

### Phase T0 — MiMo contract spike (can run parallel to Track A; fixes T5 verification)

- Verify MiMo auth: `Authorization: Bearer` vs `api-key` header against the live API reference,
  and cover it with an integration test (T5, `MimoTTSService.swift:67`).
- Capture representative iPhone utterances → supported WAV → confirm the 10 MB base64 ceiling
  behavior for `mimo-v2.5-asr` (`asr_options.language` ∈ `auto|zh|en`).
- Record exact ASR streamed-delta/final payload shapes and TTS termination/error chunk shapes;
  verify `pcm16` 24 kHz / 16-bit LE / mono on device.
- Measure whether closing the HTTP task actually stops TTS generation/billing (cancellation).
- **Exit:** checked-in fixtures (`HeraldTests/Fixtures/Mimo/…`) drive ASR/TTS parsers with no
  live credentials. No app behavior change yet.

### Phase T1 — Hermes-native push-to-talk (**requires Track A Phase 2 merged**)

Provider-neutral streaming contracts (replace the whole-file TTS abstraction):
```swift
protocol SpeechRecognizing { func transcribe(_ u: RecordedUtterance, language: SpeechLanguage) -> AsyncThrowingStream<TranscriptUpdate, Error>; func cancel() }
protocol SpeechSynthesizing { func audio(for text: String, voice: SpeechVoice, style: String?) -> AsyncThrowingStream<PCMChunk, Error>; func cancel() }
```
`PCMChunk` carries sample rate, channels, format, sequence, and terminal flag so playback never
guesses. New/changed files:
- `TalkAudioCapture` (new): mic buffers, metering, push-to-talk endpointing, WAV finalization,
  duration/byte cap under MiMo's limit. Separate the recorder from Apple's transcriber (today
  fused in `LiveSpeechService`) so the same utterance can go to MiMo **or** Apple fallback.
- `MimoASRService` (new): request construction, streamed response parsing, finalized transcript,
  retry classification. Only the **finalized** transcript is submitted to Hermes.
- `MimoTTSService` (rewrite): SSE/chat-completion streaming parse → ordered `pcm16` `PCMChunk`s
  with `stream: true`, built-in voice (Mia/Chloe/Milo/Dean). Keep non-streaming WAV only as a
  non-Talk fallback. Split network-synthesis state from playback state (fixes T2).
- `PCMPlaybackQueue` (new): `AVAudioEngine`/`AVAudioPlayerNode` scheduling at 24 kHz mono Int16,
  underflow metrics, drain completion, immediate flush-on-cancel.
- `SpeechTextRenderer` (new): canonical Hermes message → speakable text. Excludes reasoning,
  tool labels, URLs (where appropriate), diff bodies, raw JSON, Markdown fences, attachment
  syntax; preserves heading/list meaning with pauses. MiMo **style** goes in the `user` role,
  the exact **speech text** in the `assistant` role. **After Track A Phase 3 this is a segment
  filter over semantic events, not a Markdown scraper** (continuity §3).
- `TalkTurnClient` (new): a thin wrapper over the Track A `JobStreamCoordinator` +
  `JobEventReducer`, submitting with a stable `clientMessageId` + selected `conversationId`.
  **Not** `ChatStore` UI mutation, but the same durable job identity (continuity §1–2).
- `HermesTalkCoordinator` (new): orchestration/state transitions only; sole `AVAudioSession`
  owner (`.playAndRecord`/`.voiceChat`, speaker + Bluetooth HFP + interruption + route handling).

Behavior:
- Start Talk against the **currently selected conversation ID**; create local session metadata
  only — **no** OpenAI Realtime session.
- On endpoint → MiMo ASR → finalized text appended to transcript and submitted through
  `TalkTurnClient`. Project Hermes text/reasoning-status/tool-activity into Talk; **speak only
  message text**.
- On canonical completion → `SpeechTextRenderer` → streamed MiMo TTS → `PCMPlaybackQueue` →
  return to listening.
- **Delete end-of-session transcript injection** for Hermes-native turns (T4): remove the iOS
  injection in `LiveVoiceSessionService` and deprecate relay `inject` (`main.py:1591`) for this
  path. Ending Talk writes only session metadata.
- Remove `hermes_delegate` from the primary flow (T1). The legacy Realtime stack stays behind a
  clearly named compatibility flag (decision 7), not labeled "Hermes-native."
- Explicit **tap-to-interrupt** while thinking/speaking: cancel job where supported, cancel TTS
  HTTP task, flush scheduled PCM, then listen. Never persist truncated synthesized text as the
  Hermes answer — canonical text stays intact in chat; Talk records only ms actually heard.
- Move the MiMo key to `KeychainSecureStore`; `SettingsScreen` shows configured/not-configured +
  replace/remove only (fixes T3, `SettingsScreen.swift:531,540`).
- Apple Speech fallback path (decision 4) when the user declines cloud ASR.

**Exit:** a multi-turn Talk session and the equivalent typed chat produce **one shared ordered
conversation**, every assistant answer traceable to a canonical Hermes `message_id`, no duplicate
turns.

### Phase T2 — Automatic turn-taking

Calibrated local endpointing/VAD; auto-resume listening after playback drains; local barge-in
(energy/VAD ducks/stops TTS, records, submits after endpointing); harden routes, interruptions,
foreground/background recovery, CarPlay. **Exit:** 20-turn hands-free sessions with no duplicate
turns, stuck states, feedback loops, or audio-session resets.

### Phase T3 — Safe early speech (latency)

Segment **stable** Hermes text only at sentence boundaries; queue independently identified TTS
segments in order; stop segmenting when tool/reasoning boundaries make text unstable; reconcile
spoken segments against the canonical final answer and measure divergence. **Exit:** materially
lower time-to-first-audio with **zero** reordered/duplicated/noncanonical spoken sentences.

### Track B relay/connector notes

- **No relay ASR/TTS proxy** in this scope (decision 3 — device-held key). Keep persisting
  `VoiceSession` (duration, conversation, provider/model/voice, error summary, latency) and
  associate each `VoiceTurn` with `conversation_id`, user `message_id`, assistant `message_id`,
  job ID; idempotent by `clientTurnId` (`main.py:1555-1585`). Redact audio/transcript from logs.
- **Connector readiness** (`talk.prewarm`/readiness, `client.py:631-644,1241`) must check
  connector-online + selected Hermes conversation available + normal message execution ready +
  MiMo capability at the device boundary — **not** OpenAI key/Realtime model (fixes T7). No new
  `talk.delegate`; reuse the same Hermes session/execution as chat.
- Failure semantics (Talk source doc table) must respect **layer identity**: ASR retry reuses
  the same captured utterance; Hermes retry/reattach reuses the same `clientMessageId`+job
  (Track A coordinator); TTS retry reuses the same canonical assistant message + renderer
  version. A dropped edge **never** resubmits a new Hermes turn (continuity §2).

**Privacy copy (pre-launch):** disclose that finalized audio → MiMo ASR and Hermes answer text →
MiMo TTS are cloud calls while Hermes stays self-hosted; recordings ephemeral by default;
speakable text only (no reasoning/tool internals) sent to TTS; no keys/audio/transcripts in logs.

---

## Release compliance — App Store encryption declaration (independent; ship anytime)

**Decision (owner-confirmed 2026-07-20):** declare **exempt** and set the key **now** so it covers
both the current WebRTC build and the post-Track-B HTTPS-only build. Distribution is **public,
worldwide (incl. France)**, so the secondary reporting obligations below are real, not hypothetical.

**Grounded review of Herald's iOS cryptography (the app target is what Apple asks about):**
- HTTPS/TLS to the relay via `URLSession` — Apple OS encryption (exempt).
- SHA-256 via CryptoKit for App Attest + push-token hashing (`AppAttestService.swift:39-41`,
  `PushBrokerRegistrationStore.swift:16`) — standard, used for authentication/attestation.
- Keychain (`KeychainSecureStore.swift`) — OS-provided.
- WebRTC **DTLS-SRTP** for legacy Realtime Talk (`AppEntry.swift:142`) — standard IETF encryption
  via a third-party framework; **removed by Track B** (MiMo over HTTPS).
- **No proprietary/non-standard algorithms anywhere.** No custom AES/ChaCha of user data.

Apple's first-level answer is therefore **"Standard encryption algorithms in addition to Apple's
OS"** (not "None," because CryptoKit SHA-256 + WebRTC are standard algorithms used beyond OS TLS).
That usage is limited to standard TLS + hashing + authentication + standard voice transport, which
qualifies for exemption — so Herald declares exemption via Info.plist rather than uploading
documentation per submission.

### Task for Mimo

1. Add to the **Herald app target** Info.plist (`Herald/Resources/Info.plist`, referenced at
   `project.yml:86`):
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```
   The `HeraldWidgets` extension uses `GENERATE_INFOPLIST_FILE` (`project.yml:155,168`) and ships
   no independent encryption, so no widget entry is required; if a future review flags it, add the
   same `<false/>` key to the widget target.
2. This makes the App Store Connect "Export Compliance" prompt stop appearing per submission.
3. Standalone change: still gets its own version bump, CHANGELOG entry, README/docs note, and
   `xcodegen generate`. **No dependency on either track** — can land immediately (recommend
   bundling with the security fix PR **B2** since both are small pre-submission hygiene items).

### Secondary obligations to CONFIRM before public worldwide submission (owner/legal, not code)

These are **not** waived by the plist key; they attach to relying on the standard-encryption
exemption for worldwide distribution. This doc flags them; it does not assert they are all
mandatory — confirm with a compliance contact:

- **US BIS annual self-classification report** (EAR §740.17(b)/§742.15(b), ECCN 5D992.c): apps
  using standard/mass-market encryption beyond pure authentication generally owe a year-end
  self-classification email to BIS and the ENC/NSA address. Standard TLS/auth-only *may* be
  fully exempt; WebRTC/voice pushes toward "reportable." Confirm which applies.
- **France encryption declaration** (ANSSI): France requires a declaration for apps distributing
  cryptography. Apple surfaces this under the France availability terms; confirm coverage.
- Re-confirm the classification **after Track B removes WebRTC** — the app then rests on
  HTTPS/TLS + hashing only, which is the strongest exemption position and may reduce the above.

**⚠️ This is a legal export-compliance attestation the app owner signs.** Mimo implements the
plist key as directed; the owner is responsible for the BIS/France determinations above.

---

## Observability & release gates

Add structured fields `jobId`, `attempt`, `seq`, `lastAppliedSeq`, adapter version to logs/
metrics. **Never log message content, reasoning, credentials, or raw approval commands.**

Metrics (Track A): jobs accepted/started/completed/failed/cancelled/requeued; time queued / to
first semantic progress / to terminal; SSE connections/reconnects/resume-cursor/replayed-events/
sequence-gaps/resets; duplicate/stale connector events rejected; reducer duplicates ignored /
gaps detected; terminal snapshot corrections; active adapter.

Metrics (Track B / Talk latency budget): timestamps for mic start; speech start + local endpoint;
ASR request start / first delta / final; relay acceptance / Hermes first progress / first text /
canonical completion; TTS request start / first chunk / first scheduled buffer / first audible
frame / drain; next-listen readiness. Distinguish **ASR vs Hermes vs TTS vs playback** failures.
Initial p50 targets to validate (not guarantees): endpoint→final-ASR < 1.5 s;
final-ASR→first-Hermes-progress < 1.0 s; canonical-completion→first-audio < 1.0 s; no queue
underflow after playback begins; tap-interrupt→silence < 150 ms. **Never** log keys, base64 audio,
or transcript bodies.

Release gates (Track A): zero unrecovered sequence gaps in dogfood; zero nonterminal UI states for
server-terminal jobs; zero canonical-message mismatches after reconciliation; no increase in
duplicate jobs/messages; v1 fallback below threshold before Phase 4.

Release gates (Track B): every finalized utterance submitted exactly once to the selected Hermes
conversation; no assistant voice content without a canonical Hermes `message_id`; ending a session
creates no duplicate messages; ASR/Hermes/TTS/playback failures independently recoverable; MiMo
key never in `UserDefaults`/source/logs/binary; privacy copy accurately describes the cloud speech
boundary.

---

## End-to-end chaos assertion (definition of done)

Run Hermes → connector → relay → simulated iOS. At each event boundary randomly duplicate
frames, close either socket, restart relay state, delay reads, refresh auth, request cancel.
Assert (not "stayed connected"):

```text
client terminal state    == relay terminal state
client canonical message == relay canonical message
client lastAppliedSeq     == relay lastSeq
exactly one user intent/job and at most one terminal assistant message
```

No further streaming patch is accepted without stating which invariant it preserves, which
`seq`/`attempt` owns the event, and how the client recovers if the process dies immediately
after that line executes.

**Track B integration assertion:** drive user-utterance → MiMo ASR fixture → Herald job fixture
→ MiMo audio fixture → playback completion, and assert: ASR retry does not duplicate a Hermes
message; Hermes SSE reconnect neither replays speech nor submits a new turn; TTS retry does not
rerun Hermes; barge-in cancels playback while the canonical assistant message stays intact;
ending Talk creates no duplicate transcript messages; MiMo-unavailable falls back to Apple Speech
when enabled.

---

## Suggested commit sequence

| PR | Phase | Touches | Ships |
|----|-------|---------|-------|
| 1 | 0 | `docs/STREAM_CONTRACT_V2.md`, `stream_contract.py`, `Herald/Models/JobEvent.swift`, fixtures | Frozen contract + golden decode tests. No behavior change. |
| 2 | 1a/1b | `relay/app/models.py`, `relay/app/database.py`, `relay/app/services.py`, `relay/app/streaming.py` | `job_events` table + `attempt` column + transactional append. |
| 3 | 1c/1d/1e | `relay/app/main.py` | Real `id:` SSE, `Last-Event-ID`/`?after=` replay, `cancelled` terminal, snapshot fields, retention. Capability `job_stream_contract: 2`. |
| 4 | 2a/2b | `RelayAPIClient.swift`, `LiveHeraldClient.swift`, `JobStreamCoordinator.swift`, `HeraldClientProtocol.swift` | Cursor-aware SSE + resumable coordinator (D2, D4, D11). |
| 5 | 2c/2d | `Herald/Stores/ChatStore.swift`, `JobEventReducer.swift` | Pure reducer + inactivity watchdog (D3, D7-client). |
| 6 | 3 | `hermes_gateway_executor.py`, `client.py`, `herald_api_executor.py` | Structured Hermes adapter, drop `TOOL_PROGRESS_RE` from primary path (D6, D9). |
| 7 | 3.5 | `relay/app/main.py`, `relay/app/services.py`, `connector/.../client.py` | Server-owned attempts + lease retry (D7-server). |
| 8 | 4 | (removals) | Delete v1 streaming after metrics clear the gate. |
| B1 | T0 | `HeraldTests/Fixtures/Mimo/…`, MiMo request/parse spikes | MiMo auth verified (T5) + ASR/TTS fixtures. **Parallel-safe.** No behavior change. |
| B2 | T3 (security) | `SettingsScreen.swift`, `KeychainSecureStore.swift`, `Herald/Resources/Info.plist` | Move `mimo.apiKey` off `UserDefaults` → Keychain (T3) **+ add `ITSAppUsesNonExemptEncryption=false`** (see "Release compliance" section). Ship early — standalone pre-submission hygiene. |
| B3 | T1 | `HermesTalkCoordinator.swift`, `TalkTurnClient.swift`, `TalkAudioCapture.swift`, `MimoASRService.swift`, `MimoTTSService.swift`, `PCMPlaybackQueue.swift`, `SpeechTextRenderer.swift`, `TalkStore.swift`, relay `main.py` (deprecate `inject`), connector readiness | Hermes-native push-to-talk (T1, T2-partial, T4, T6, T7). **Requires PR 4 (Track A Phase 2) merged.** |
| B4 | T2 | Talk coordinator + audio routing | Automatic turn-taking, barge-in, route/interruption hardening. |
| B5 | T3 | `SpeechTextRenderer`, TTS segmenter | Safe early sentence-boundary synthesis. Only after latency telemetry. |
| B6 | — | (removals) | Retire legacy OpenAI Realtime Talk + `hermes_delegate`/`talk.delegate` if usage doesn't justify two stacks (decision 7). |

**Ordering constraints:** B1 and B2 have no dependency (do them first — B2 is a pure security
fix worth shipping immediately). **B3 must not merge before PR 4.** Ideally B3 also lands after
PR 6 (Track A Phase 3) so `SpeechTextRenderer` filters semantic events instead of scraping
Markdown (continuity §3) — if B3 ships before PR 6, gate the renderer behind the v1 compat
decoder and revisit when structured events land.

Each PR carries its own version bump, CHANGELOG entry, docs update, and `xcodegen generate`.
