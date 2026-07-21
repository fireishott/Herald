# Herald — Mimo Marching Orders: Reasoning, Streaming, Double Indicators, Push, Notes

**Prepared:** 2026-07-20 (evening session)
**Audience:** Mimo `mimo-v2.5` (or any coding agent)
**Starting point:** git commit `6b01045` (master, v1.7.2 / build 38), local branch **ahead 2 of origin** (`1147c68` think-block gating, `6b01045` iPad Notes)
**Assessment mode:** source reviewed read-only on the Mac **and live host inspected read-only over SSH**. This document is the only file created. No code, config, or deployment was changed.
**Companion docs:** `HERALD_PROJECT_BRIEF.md` §9 (method), `CODEX_REVIEW_2026-07-20.md` (P0-1…P0-3 analysis, still the definitive write-up of the relay dedupe bug), `MIMO_MARCHING_ORDERS_2026-07-20_STREAMING_DURABLE_LOG.md` (Track A contract work).

---

## Cross-cutting rules (restated from the brief — apply to every fix)

- Bump version everywhere (`project.yml` both targets, README badge, CHANGELOG, in-app label). One logical change = one commit = one dated CHANGELOG entry.
- Relay has **no migration framework** — schema changes ship exact manual `ALTER`/`CREATE` statements. Production relay is **Postgres**, not the repo's dev SQLite.
- Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete` — new async code must be concurrency-clean.
- Never hardcode secrets. iOS → Keychain; relay/connector → env.
- Host `fih-ai-host` hard-freezes (OOM history): "accepted but slow" ≠ failure. Watchdogs must not re-send slow-but-alive jobs.
- MBP builds: unlock login keychain before **every** `xcodebuild`; entitlement-stripping step for the paid team must be reviewed per F5 below.

## Environment block

| Thing | Value |
|------|-------|
| App repo (Mac) | `/Users/curtisfreeman/Herald` — master `6b01045`, v1.7.2 build 38, **ahead 2 of origin** |
| iOS app | `Herald/` target, Swift 6.2, strict concurrency, XcodeGen (`project.yml` is source of truth) |
| Widgets | `HeraldWidgets/`, App Group `group.net.fihonline.herald`, `NSSupportsLiveActivities: true` (`project.yml:103`) |
| Relay (repo) | `relay/` FastAPI; dev SQLite, prod `DATABASE_URL` Postgres |
| **Relay (DEPLOYED)** | Docker on host: container `hermes-relay-relay-1`, port `8010→8000`, compose project at **`/home/fihadmin/deploy/hermes-relay`** (⚠️ **not a git repo**), Postgres sidecar `hermes-relay-postgres-1`, Caddyfile present. Image created 2026-07-20T10:53Z **but built from pre-S1 code** (see F1) |
| Connector (DEPLOYED) | systemd `hermes-mobile-connector.service` → `/home/fihadmin/Hermes-iOS/connector/.venv/bin/herald run` |
| **Host checkout** | `~/Hermes-iOS` on host: git log at `39a6aeb` ("build 14" era; remotes: `fork`=fireishott/Herald, `origin`=dylan-buck/Hermes-iOS) with **~477 lines of uncommitted changes** that *do* include connector `sourceSeq`/`reasoning_delta` support |
| Hermes agent | `~/.hermes/hermes-agent` on host = **NousResearch/hermes-agent upstream, main @ `ad0ddfb15`** (this is the "Nous GH" reference — it's already installed and current) |
| Ignyte profile config | `~/.hermes/profiles/ignyte/config.yaml` (live gateway display config — see F2) |
| Hermes API server | ignyte api_server on host `:8642` (unsandboxed as fihadmin — accepted risk, don't re-flag) |
| Bundle / team | `net.fihonline.herald` · `DEVELOPMENT_TEAM 58U7UPFS53` |

## Lay of the land — read this before touching anything

The single most important fact of this assessment: **the streaming bugs are already fixed in the repo (S1 `899c61c`, S3 `ebb71a1`, S2 `d43a4eb`, terminal plumbing `f1a8867`) but the production relay container was built from code that predates all of them.** Verified live:

```
docker exec hermes-relay-relay-1 grep -c "sourceSeq" /app/app/main.py   → 0
```

Meanwhile the repo's relay passes `sourceSeq` through at `relay/app/main.py:2797-2798` and `publish_job_event` reads it at `relay/app/main.py:277-282`. The deployed relay therefore still has Codex **P0-1**: every `job.progress` event lands with `source_seq=0`, the `(job_id, attempt, source_seq)` dedupe in `append_job_event` (`relay/app/services.py:1586-1594`) drops **everything after the first event**, and the app receives `started` → keepalives → `done`. That is *the* mechanism behind "reply pops in whole at the end."

Deployment topology that produced this: code lives in `~/Hermes-iOS` (dirty, old HEAD), the relay is built from a **separate, non-git** `~/deploy/hermes-relay` directory, and the connector runs from the dirty checkout via systemd. There is no defined deploy procedure — that is a deliverable of these orders (F1b).

Chain (for reference): iOS app → relay `:8010` (Docker, Postgres) → connector (systemd, WS to relay) → hermes-agent api_server `/v1/chat/completions` SSE → ignyte agent → deepseek-v4-flash.

The upstream contract is healthy: hermes-agent's api_server emits `delta.reasoning_content` chunks (`gateway/platforms/api_server.py:2963`, forwarder at `:2704`) plus `event: hermes.tool.progress` frames, and the connector translates them correctly (`connector/src/herald_connector/herald_api_executor.py:280-291` → `reasoning_delta`; `client.py:993-1002` forwards with `sourceSeq`). **Nothing new needs inventing — the pipe is broken only at the relay deployment and at one gateway config flag.**

---

# Findings & fix paths (P0 → P2)

## F1 (P0) — "Wall of text, not streaming": deployed relay drops all deltas

**Root cause:** stale container, per Lay of the Land above. Not an iOS bug; not a connector bug (host connector working tree already emits `sourceSeq` + `reasoning_delta`).

**Fix path (deployment, not code):**
1. Reconcile the host checkout: commit or stash-review the ~477 uncommitted lines in `~/Hermes-iOS`, then fast-forward to `fireishott/Herald` master (contains `445ebea` recovery merge with S1–S3). The uncommitted connector changes appear to be a hand-applied subset of exactly those commits — diff before discarding.
2. Schema first (Postgres, no migrations): compare `relay/app/models.py` against the live DB; ship exact statements for anything missing — at minimum verify `job_events` table (durable log), `message_jobs.reasoning_effort` (`models.py:284`), and the 1.7.2 notes tables (`notes`, `note_blobs`, `note_recognitions`, `note_runs`, `note_run_events`, `enriched_note_revisions`). `docker exec hermes-relay-postgres-1 psql … '\d job_events'` etc.
3. Rebuild + redeploy the container from current relay code into `/home/fihadmin/deploy/hermes-relay` (`docker compose build relay && docker compose up -d relay`). Preserve `.env` (APNS_* etc.).
4. Restart `hermes-mobile-connector.service` after the checkout is reconciled.

**F1b — make deploys reproducible (P1 but do it now):** replace the loose `~/deploy/hermes-relay` copy with a git-tracked source (compose file pointing at the checkout, or a documented rsync step in a `deploy.sh`), and record the procedure in `MAINTAINER_NOTES.md`. The whole class of "fixed in repo, broken in prod" dies here.

**Acceptance:** send a chat message; text renders incrementally on device; `SELECT seq, type FROM job_events WHERE job_id='…' ORDER BY seq` shows a full ladder (`started`, many `text_delta`/`reasoning_delta`, terminal); killing the app mid-stream and reopening resumes via replay.

## F2 (P0) — Reasoning baked into the message text (and doubled): gateway config

**Root cause:** ignyte's live gateway config has `show_reasoning: true` globally (`~/.hermes/profiles/ignyte/config.yaml:393`) with `reasoning_style: code` (`:418`) and **no `api_server` platform override** (only `telegram`/`discord` at `:420-425`). With that flag on, hermes-agent prepends the reasoning to the *visible message text* — `gateway/run.py:12775`: `💭 **Reasoning:**\n```\n…\n```\n\n{response}` — for the api_server platform, *in addition to* streaming the same reasoning on the separate `reasoning_content` channel. Herald renders that fenced block as content (it is neither `<think>`-tagged nor in `message.reasoning`), which is the boxed "Reasoning" wall in the screenshots. Server-side reasoning rendering exists for dumb platforms (Discord); Herald is a rich client with its own reasoning UI.

**Fix path (config, no code):** add to `~/.hermes/profiles/ignyte/config.yaml` under `display.platforms`:
```yaml
    api_server:
      show_reasoning: false
```
(Exact key confirmed: `gateway/display_config.py` `_PLATFORM_DEFAULTS` has `"api_server"`; an explicit per-platform user override beats the global `true`.) Restart the gateway — **flag: gateway restart drops live sessions; schedule with Curtis.**

**Duplication (second identical copy of the reasoning inside the block):** the 💭-prepend accounts for one copy. Where the *second* contiguous copy comes from (model inlining reasoning into `content` as well, or a gateway double-append) — **repro needed, do not invent**: capture one raw stream with `curl -N` against the api_server `/v1/chat/completions` (key from host env; do this on the host, the port is LAN-exposed) and inspect whether `delta.content` already contains the reasoning text before the 💭 block is prepended. File the result in the fix PR description. If the copy is model-inline `<think>`, the app already strips it in the `.finished` path (`Herald/Stores/ChatStore.swift:277-280`); after F2 the strip heuristics (`ChatStore.swift:271-280`) become belt-and-braces — keep them.

**Acceptance:** after F1+F2, a deepseek-v4-flash turn shows reasoning **only** in the dimmed streaming `ReasoningView` (collapsing to "Thought for Xs"), the answer bubble contains only the answer, and no `💭`/`Reasoning` text appears in message content. The `🔥 · ignyte · …` runtime footer is a separate concern: `runtime_footer.enabled: false` is already set at `config.yaml:426-427`, yet a footer appeared in the screenshot — verify whether that footer came from an older turn or a different code path while you're in there.

## F3 (P0) — "Show Reasoning" toggle does nothing

The toggle itself is wired correctly end-to-end: `SettingsScreen.swift:796-800` writes `settingsStore.settings.showReasoning`; `MessageBubble.swift:198` gates `ReasoningView`; `MessageBubble.swift:273` passes it into `MarkdownContentView`, which gates inline `<think>` segments at `MarkdownContentView.swift:50` (added by local commit `1147c68`). It *appears* dead for three stacked reasons:

1. **The reasoning on screen is neither of the things the toggle gates.** It's the gateway's 💭 fenced code block inside `message.content` (F2) — a plain markdown segment the toggle cannot touch. Fixed by F2, not by app code.
2. **`message.reasoning` is always empty in production** because the deployed relay drops every `reasoning_delta` (F1) — so the `ReasoningView` branch never renders and toggling it is a no-op by vacuity. Fixed by F1.
3. **The `<think>`-gating fix `1147c68` is unpushed and possibly not in the build on Curtis's devices** (build 38 is defined locally; verify the installed build number in app Settings). Push origin and cut a build.

**App work in this item: none beyond shipping `1147c68`.** Re-test after F1+F2 before writing any new gating code. If, after both, historical messages still show stale walls of text, that's persisted content in the conversation cache/relay transcript from the broken era — offer Curtis a one-time strip or leave history as-is (fork to resolve with him, §9.9).

**Acceptance:** toggle ON → dimmed reasoning streams live above the answer and collapses when done; toggle OFF → no reasoning anywhere, including on old messages with populated `message.reasoning`; flipping the toggle updates already-rendered messages without app restart.

## F4 (P1) — Two sets of thinking dots

**Root cause — two indicators with overlapping truth windows:**
- `sendMessage` appends the assistant placeholder **immediately** (`Herald/Stores/ChatStore.swift:124-132`); while it's empty and streaming, `MessageBubble` renders `TypingDotsView` (`MessageBubble.swift:195-196` → `streamingPlaceholder` at `:279-282`).
- `ChatScreen` *also* shows `ThinkingIndicatorView` ("THINKING… 3S") whenever `pendingMessageSentAt != nil && streamingMessageID == nil` (`Herald/Features/Chat/ChatScreen.swift:625-629`).
- `streamingMessageID` is computed from `activeStreams`, which only gets its entry on `.messageSent` (`ChatStore.swift:214`). So **from send until the relay acks the job, both indicators are on screen simultaneously** — exactly the screenshot. With the production relay slow/stale, that window is long.

**Fix path (pick one source of truth — recommend (a)):**
- **(a)** Delete the `ThinkingIndicatorView` block from `ChatScreen.swift:625-629` and move its elapsed-time affordance into the placeholder bubble: extend `streamingPlaceholder` (`MessageBubble.swift:279-282`) to show dots + "Thinking… Ns" driven by `message.timestamp`. One indicator, anchored where the answer will appear.
- (b) Alternatively defer the placeholder append until `.messageSent` — rejected: it loses the instant visual ack and complicates the durable-log resume path.

**Acceptance:** at no point between tap-send and first token are two indicators visible; the single indicator shows elapsed seconds; it transitions in place into the streaming reasoning/answer.

## F5 (P0/P1) — Push notifications dead; no Live Activity (Dynamic Island / Lock Screen)

Two separate subsystems, three findings:

**F5a (P0) — `aps-environment` entitlement is missing.** `Herald/Herald.entitlements` contains HealthKit + App Group only — **no `aps-environment` key** (same for `HeraldWidgets/HeraldWidgets.entitlements`). Whatever the provisioning profile injects, the repo's signed entitlements don't declare push. Relay logs *do* show successful `POST /v1/push/register` calls from the field, so a token of some vintage is being registered — but with no `aps-environment` in the final signed app, APNs delivery to that token is exactly the kind of thing that fails silently. Fix: add `aps-environment` (`development` for debug, `production` for release — Xcode/XcodeGen handles the swap at signing) to both entitlement files via `project.yml`, and **audit the "strip entitlements for paid team" build step** (`~/Hermes-iOS-Builds/herald_testflight_build.sh`) to ensure it never strips this key. Then verify on the archive: `codesign -d --entitlements :- Herald.app | grep aps`.

**F5b (P0, server) — verify the send actually fires.** The deployed container *does* contain `maybe_send_message_push` (3 occurrences, verified), `APNS_*` env is set, and the `.p8` key exists at `$APNS_KEY_PATH` (`/data/AuthKey_LH5GM8356P.p8`). Container default `APNS_ENVIRONMENT=development` is fine because each registration carries its own environment from the app (`Herald/Stores/AppContainer.swift:679-681`: DEBUG→development, else production; relay uses `registration.push_environment` at `relay/app/main.py:434-440`). Remaining suspect: the foreground gate — `maybe_send_message_push` skips any device `device_is_foreground(…, stale_seconds=settings.app_presence_stale_seconds)` considers active (`main.py:407-408`). If presence pings never go stale, no push is ever attempted, and **nothing is logged on the skip path**. Fix: add one `logger.info` per skip/send decision, then repro: background the app, trigger a completion, read `docker logs hermes-relay-relay-1`. Fix whatever the log shows (likely presence staleness tuning). 2 push registrations exist in the prod DB, so registration plumbing works.

**F5c (P1, app) — Live Activity never starts for chat turns.** `LiveActivityService.startToolCall` is only invoked from the `.toolActivity` handler (`ChatStore.swift:246-247`) — and the deployed relay never delivers `tool_activity` events (F1), so the Activity never starts. Post-F1 it will appear for tool-using turns only. To get the full "status, brain, tools" treatment Curtis described: start the Activity at `.messageSent` with a `thinking` phase, update state on `.reasoningDelta` (brain) / `.toolActivity` (tool name) / first `.textDelta` (writing), end on `.finished`/`.failed` — surfaces: `LiveActivityService.swift:52-66`, attributes in `HeraldWidgets/HeraldActivityAttributes.swift`, UI in `HeraldWidgets/HeraldLiveActivity.swift`. `NSSupportsLiveActivities`/`FrequentUpdates` are already set (`project.yml:103-104`).

**Acceptance:** app backgrounded → completed response produces a lock-screen banner within seconds; during a turn, Dynamic Island/Lock Screen shows phase progression (thinking → tool name → writing → done); no push when the app is foreground.

## F6 (P1) — Notes: make it feel like native iPadOS Notes

Current state (all `Herald/Features/Notes/`): `NoteEditorView.swift` hosts a fixed-frame `ZStack` of `NotePaperBackground` under `PencilCanvasRepresentable`; `NotePaperBackground.swift` draws ruled lines only (`Color.secondary.opacity(0.08)` — invisible on the dark theme, per screenshot) and **ignores its `style` parameter** apart from on/off; the `.letter/.a4/.blank` picker (`NoteEditorView.swift:58-62`) therefore changes nothing visible; the canvas zooms 1–4× (`PencilCanvasRepresentable.swift:24-25`) while the paper stays static so lines shear away from ink under zoom/pan; no scrolling (content is one screen), no attachments, no typed text. Reference: Apple's Notes on iPadOS (lines & grids in three densities, paper scrolls/zooms with content, inline attachments, scanning).

**Fix path, in order:**
1. **Paper that's actually visible and honors the picker.** Extend `NotePageStyle` → `blank | lines(small/medium/large) | grid(small/medium/large)`; draw verticals for grid; theme-aware ink (dark: `white.opacity(0.12)`-ish; light: current grey) and keep the red margin line only for `lines`. Persist the choice per note (`HeraldNote` model + `NotesRepository`).
2. **Paper joined to the canvas, scrolling pages.** `PKCanvasView` *is* a `UIScrollView`: set `contentSize` to page-width × N pages and grow it as strokes approach the bottom (native "endless roll" behavior); render the paper into a view installed **behind the canvas's content** (subview of the canvas at index 0, sized to `contentSize`) or as a tiled pattern layer — so paper scrolls and zooms with the ink. This kills the shear bug and gives "scrolling pages" in one move. Redraw pattern on style change.
3. **Attachments.** Photo/scan insertion via `PHPickerViewController` + VisionKit `VNDocumentCameraViewController`; store through the existing blob machinery (`NotesRepository` SHA-256 blobs; relay `note_blobs` endpoint with its 25 MB cap already shipped in 1.7.2); v1 renders an attachment strip above the canvas (reuse `MessageAttachmentsView` patterns), not free-floating objects.
4. **Typed text (defer / fork with Curtis).** Native Notes is text-first with embedded drawings; Herald v1 is canvas-first. A TextKit page with inline drawing sections is a rewrite — decide with Curtis whether it's v2 (§9.9 fork; recommend deferring, the PencilKit canvas is the differentiator for #directives).

**Acceptance:** picker switches among blank/lines/grid at three densities and the change is visible on the dark theme; zooming/panning keeps ink glued to the paper; writing past the bottom grows the page and scrolls; a photo attached from the picker survives relaunch and syncs through the relay; existing notes open unchanged.

---

## Sequencing (independent PRs / actions, each with its own version bump + CHANGELOG)

1. **Ops-1 (no PR):** F1 relay redeploy + schema verification + connector checkout reconcile + restart. *Unblocks everything; do first.*
2. **Ops-2 (no PR):** F2 gateway config `api_server.show_reasoning: false` + scheduled gateway restart. Capture the F2 duplication repro while restarting anyway.
3. **PR-1:** push origin (`1147c68`, `6b01045`), cut build → F3 resolves by deployment; retest toggle.
4. **PR-2:** F4 single thinking indicator (iOS only).
5. **PR-3:** F5a entitlements + build-script audit; then F5b relay logging + presence fix (relay); then F5c Live Activity phases (iOS + widgets).
6. **PR-4:** F6 Notes phases 1–2 (paper + scrolling); **PR-5:** F6 phase 3 (attachments). Phase 4 pending Curtis's call.
7. **F1b:** deploy script + `MAINTAINER_NOTES.md` procedure — fold into Ops-1's follow-up PR.

## Forks to resolve with Curtis before coding

- History cleanup: strip 💭-era reasoning walls from persisted transcripts, or leave old messages as-is? (F3)
- Gateway restart window for the ignyte profile (F2) — sessions drop.
- Notes typed-text (native-parity) now or defer to v2? (F6.4)
