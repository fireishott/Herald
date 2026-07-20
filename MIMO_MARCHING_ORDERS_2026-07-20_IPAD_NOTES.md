# Herald — Mimo Marching Orders: iPad Notes (PencilKit + Hermes Enrichment)

**Prepared:** 2026-07-20
**Audience:** Mimo `mimo-v2.5` (or any coding agent)
**Starting point:** Notes review baselined at `5dd5c67` (`1.7.0 / 36`). ⚠️ Tree has since advanced to **HEAD `1147c68`** (`v1.7.1 / 37`, Talk + streaming + reasoning work landed); **Track T** below is baselined there. Re-resolve all cited line numbers against the current HEAD before editing.
**Assessment mode:** source reviewed read-only; this document is the only file created. No code was changed.
**Source spec:** "Herald iPad Notes: feature request, code review, and MiMo implementation map" (delivered 2026-07-20, reviewed against `5dd5c67`). Every `file:line` in that spec was independently re-verified at this commit before these orders were written; all citations resolve. If the tree moves, re-resolve lines before editing.

---

## Relation to `CODEX_REVIEW_2026-07-20.md` (read before sequencing)

The untracked Codex review targeted `099c0cd` and found durable streaming non-functional. Since then, six fix commits landed (`899c61c` S1 relay sequencing, `ebb71a1` S3 iOS v1 fallback, `d43a4eb` S2 delta coalescing + terminal persist, `cc7557e` T2 Keychain key, `f1a8867` terminal plumbing, `5dd5c67` docs). Consequences for this work:

1. **Streaming P0s (S1–S3) are fixed in-tree but not re-proven in the field.** Notes Phase 3 builds note runs on the durable stream semantics — its **entry gate** is a verified end-to-end streamed chat turn against the production relay (SQLite relay on `192.168.10.101` behind Caddy — see "Relay operations in this environment"). Do not build note-run streaming on an unverified substrate.
2. **Codex T1 is still open:** `HermesTalkCoordinator` is constructed nowhere in the app tree (grep confirms). That is Talk work, not Notes work — do not fix it inside a Notes commit, and do not let Notes commits touch `HermesTalkCoordinator.swift`/`TalkTurnClient.swift`.
3. **Version drift again:** `project.yml:80-81,138-139` say `1.7.0 / build 36`; `README.md:14` badge says `1.7.1`. Reconcile in the first commit (see N0.1).

---

## Cross-cutting ground rules (apply to every commit)

1. **One logical change = one commit = one dated CHANGELOG entry.** No mixed commits; never mix Notes work with Talk/streaming fixes.
2. **Version bump everywhere, every shippable change:** `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in *both* targets (`project.yml:80-81` app, `:138-139` widgets), README badge (`README.md:14`), CHANGELOG. Then `xcodegen generate` — the `.xcodeproj` is generated; never hand-edit it. New Swift files under `Herald/` are picked up by the source glob; confirm they appear in the generated project.
3. **Swift 6 strict concurrency stays clean** (`SWIFT_STRICT_CONCURRENCY: complete`, `project.yml:16`). New stores are `@Observable @MainActor`; recognition/run coordinators are actors; parsers are pure `Sendable` types.
4. **Relay schema:** brand-new tables ride `Base.metadata.create_all` (`relay/app/database.py:40`); any change to an *existing* table is a manual idempotent ALTER in `_run_migrations` (`database.py:46`, `_exec_safe` pattern at `:50`) with both Postgres and SQLite variants (see the `app_state_updated_at` dual-dialect example at `database.py:105-110`). ⚠️ **Prod runs SQLite** (`.101`, `data/relay.db`) — so a Postgres-only statement wrapped in `_exec_safe` **silently no-ops in production** (that is exactly the Track R bug). Every DDL change must have a working SQLite path and be tested against SQLite first.
5. **Build machine:** unlock the login keychain before **every** `xcodebuild`; strip entitlements for the paid team per house pipeline.
6. **Preserve untracked files already in the tree:** `CODEX_REVIEW_2026-07-20.md`, `docs/screenshots/v1.7.0/`, `relay/relay.db-shm`, `relay/relay.db-wal`. Do not delete, move, or commit them as a side effect.
7. **Secrets:** iOS → Keychain, relay/connector → env. Never hardcode. Do not log drawing blobs, full OCR text, full prompts, or generated documents.
8. **Host reality:** `fih-ai-host` hard-freezes under memory pressure; first token can be slow. "Accepted but slow" is **not** failure — note-run watchdog/lease logic must follow the same rule as message jobs (`relay/app/services.py:1124` requeue semantics), never double-dispatch a slow enrichment.

---

## Decisions locked by the operator 2026-07-20 (do not re-litigate)

1. **Ink sync IS in v1.** The relay stores drawing blobs (`note_blobs` + binary endpoints, Phase 3). Local files remain authoritative for editing; relay is authoritative for cross-device availability.
2. **iPhone gets a read-only Notes tab in v1** (list + rendered ink preview + recognized/enriched text; no editor, no tool picker). Lands in Phase 4, *after* sync exists, so the tab is never dead.
3. **Enriched documents = immutable history + editable derived copy.** Every `EnrichedNoteRevision` is immutable; the UI edits a derived Markdown copy stored per note. Re-runs never clobber user edits.
4. **Adopted defaults** (operator may still override before Phase 3 starts): explicit "Enrich" every time (no auto-run in v1), device-preferred recognition languages, 30-day soft-delete recovery.
5. **v1 command allowlist is read-only:** `#research`, `#search`, `#talkingpoints`, `#summary`, `#actions`, `#questions`. No command may mutate external state. Unknown tags are data.
6. **Local metadata backend:** SwiftData recommended; Phase 0 gate 0.C decides. Drawing blobs are always atomic files in Application Support regardless — **never** UserDefaults (the `HeraldCanvasStore` pattern is explicitly off-limits, see map below).

---

## Environment

| Thing | Value |
|------|-------|
| **App repo** | `/Users/curtisfreeman/Herald` (git; branch history is "build N" commits) |
| **iOS app** | `Herald/` target, Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, deployment target iOS 18.0 (`project.yml:18`); gate iOS 26-era APIs (`PKStrokeRecognizer`) behind `#available` |
| **Widgets** | `HeraldWidgets/` extension, App Group `group.net.fihonline.herald` |
| **Relay** | `relay/` FastAPI + SQLAlchemy; **no migration framework → manual idempotent ALTERs** in `database.py:_run_migrations`. Production = `hermes-relay` docker container on **`192.168.10.101` (`fih-docker-vm`)** behind the `caddy` container on the same host; **DB is SQLite** (`data/relay.db`). `.118` is Hermes/connector only. ⚠️ The rebrand's FK-repoint migration is Postgres-only → SQLite prod carries orphan-FK debt; see "Relay operations in this environment" |
| **Connector** | `connector/src/herald_connector/`; Python WS client; RPC `elif` chain in `client.py:1202-1235`; runs beside Hermes on the host |
| **Hermes host** | `fih-ai-host` @ `192.168.10.118`; hard-freezes multiple times/day (OOM history) → expect slow first-token; watchdog must not retry accepted-but-slow jobs |
| **Coding model** | Mimo `mimo-v2.5` (in-app model selector); this is who these orders address |
| **Build machine** | MacBook Pro. **Unlock login keychain before every `xcodebuild`**; bump version in `project.yml` (both targets) + README badge + CHANGELOG; strip entitlements for the paid signing team |
| **Project gen** | XcodeGen — edit `project.yml`, run `xcodegen generate` |
| **Bundle / team** | `net.fihonline.herald` · `DEVELOPMENT_TEAM 58U7UPFS53` (`project.yml` is authoritative) |
| **Secrets** | Never hardcode. iOS → Keychain; relay/connector → env. Host-side security debt is out of scope |
| **Version state** | ⚠️ drifted: `project.yml` `1.7.0 / build 36`, README badge `1.7.1` — reconcile in commit N0.1 |
| **Tests** | iOS: `HeraldTests/` (+ `Fixtures/`), `HeraldUITests/`; relay: `relay/tests/` (`test_api.py`, `test_storage.py`, `test_streaming.py` are the precedents); connector: `connector/tests/` (`test_stream_contract.py`, `fixtures/`) |

---

## Relay operations in this environment (verified live 2026-07-20 — read before touching any relay)

**Actual architecture** (verified live 2026-07-20 by shelling into both hosts — this corrects the stale brief and my own first-pass guess earlier in this doc):

- **Production relay = `192.168.10.101` (`fih-docker-vm`).** The `caddy` container (`:443`) terminates `hermes-relay.fihonline.net` and proxies to the `hermes-relay` container on the **same** host (`:8010`→container `:8000`). **The relay DB is SQLite** — `DATABASE_URL=sqlite:///./data/relay.db` (persisted volume; `data/relay.db` + WAL), **not** Postgres. This is what the app and connector actually talk to; the connector is enrolled here as host `3780fc3d-…` (user `82a879ec-…`). There was no Caddy mis-route — `.101` is simply prod.
- **`fih-ai-host` (`.118`) is the Hermes compute host, not the relay.** It also runs a `hermes-relay-relay-1` + `hermes-relay-postgres-1` docker stack, but that Postgres is **not** in the request path — stale/secondary. Do not point schema changes or debugging at it.
- **`.118` is where the connector + Hermes run:** connector state `~/.herald/state.json`, CLI `~/.local/bin/hermes-mobile` (compat name for `herald`), `pair-phone` subcommand. `.118` freezes under memory pressure; when it does, Hermes is down but the `.101` relay stays up (note runs stall → "accepted but slow", not failure).

**Incident 2026-07-20 (RESOLVED):** `POST /v1/connector/phone-pairing-codes` on prod returned 500 — `sqlite3.IntegrityError: FOREIGN KEY constraint failed`, traceback at `create_phone_pairing_code` → `services.py:137` `db.commit()`. Root cause: the Hermes→Herald rebrand (`relay/app/database.py:_run_migrations`) renamed the hosts table, but the **child-FK repoint step is Postgres-only** (`ALTER TABLE … DROP/ADD CONSTRAINT`, wrapped in `_exec_safe` so it silently no-ops on SQLite). On the SQLite prod DB the orphan `hermes_hosts` table still lingers and **four tables kept FKs pointing at it**: `phone_pairing_codes`, `host_enrollment_invites`, `voice_sessions`, `message_jobs`. Current + future hosts live in `herald_hosts`, so any insert/commit binding those rows to a current host fails the FK.

**Fix applied (pairing only):** backed up `data/relay.db` → `data/relay.db.bak-20260720-pairingfix`, rebuilt `phone_pairing_codes` with `foreign_keys=OFF` (create-new → copy 28 rows → drop → rename) so its `host_id`/`created_by_host_id` FKs reference `herald_hosts`, restarted the `hermes-relay` container, verified health 200, minted codes. The 28 legacy rows are pre-existing, all expired, never re-mutated → harmless.

**Still latent (P1 relay debt — fix before those paths break):** `host_enrollment_invites`, `voice_sessions`, `message_jobs` still FK → `hermes_hosts`. New host enrollment, a voice session bound to the current host, or a message-job write that sets `host_id` to a `herald_hosts` id will 500 identically. Fix = the same table-rebuild for each, **and** make the rebrand FK-repoint dialect-aware in `_run_migrations` (on SQLite do create-copy-drop-rename instead of `ALTER … CONSTRAINT`), then drop the orphan `hermes_hosts`. This is a real relay commit for Mimo, independent of Notes.

Rules going forward:

1. **Production is `.101` SQLite behind Caddy on the same host — not `.118`, and not Postgres.** Fix `HERALD_PROJECT_BRIEF.md §9.2` (says field relay is `192.168.10.118:8010` Postgres — both wrong) on next edit. Shell in with the documented password-SSH ops pattern (`sshpass … fihadmin@192.168.10.101`); there is **no** key auth to `.101` yet — `ssh-copy-id` a key so future ops don't need the password inline.
2. **Any Postgres-only DDL in `_run_migrations` is a silent no-op on the SQLite prod DB.** That is the template for "relay misbehaves after a schema-bearing change." Audit `_run_migrations` for other `DROP/ADD CONSTRAINT` / `ALTER COLUMN` statements that never ran on `.101`.
3. **Schema deploys / manual ALTERs target `.101`'s `data/relay.db`.** Back up the file first (`cp data/relay.db data/relay.db.bak-<date>-<reason>`); prefer create-copy-drop-rename for FK changes; verify `PRAGMA foreign_key_check` before restarting the container.
4. **After any relay DB rebuild/wipe:** device tokens and connector credentials die with it — re-pair devices and re-enroll the connector deliberately.
5. **Marker-test routing when in doubt:** curl a unique path through the public URL and grep `docker logs hermes-relay` on `.101` — instantly shows where traffic lands.
6. **Notes Phase 3 streaming entry-gate and Track P acceptance** target prod `.101` through the public URL; the Phase 3 gate implicitly re-verifies routing + the FK health of the tables its runs touch.

---

## Verified code map (all anchors re-checked at `5dd5c67`)

| Anchor | What it is | Rule for Notes |
|---|---|---|
| `Herald/Features/Sidebar/iPadSidebarView.swift:6-31` | `SidebarSection` enum (chat/inbox/talk/settings) with `title`/`icon` switches | Add `.notes` case; every switch is exhaustive so the compiler finds them |
| `Herald/Features/Sidebar/iPadSidebarView.swift:449-452` | `bottomSections` **hard-codes** `[SidebarSection.chat, .inbox, .talk, .settings]` | The compiler will NOT catch this array — add `.notes` explicitly and add a navigation test that asserts it |
| `Herald/Features/Sidebar/AdaptiveRootView.swift:113-134` | `contentColumn` switch routing sections; `:6-28` iPad-vs-iPhone split; `:13-15` inspector width 280–480 pt | Route `.notes` → `NotesWorkspaceView` in the central detail column. A PencilKit page can never live in the inspector |
| `Herald/ContentView.swift:12-46` | iPhone `TabView` (chat/inbox/talk/settings) | Add read-only Notes tab in Phase 4 only |
| `Herald/Core/Router.swift:29-53` | `AppTab` enum mirrors the tabs | Add `.notes` in Phase 4 with the tab; deep link `herald://notes/{noteId}` no-ops gracefully where the note isn't locally present |
| `Herald/AppEntry.swift:113-135` | Environment injection of every store | Inject `notesStore` (and nothing else) here |
| `Herald/Stores/AppContainer.swift:47-70` | Store ownership/construction | Construct `NotesStore` + `NotesRepository` here; mock-injectable like the others |
| `Herald/Features/Canvas/HeraldCanvasStore.swift:8-19,57-60` | One string artifact per session in `UserDefaults` | **DO NOT reuse, rename, or extend.** Reuse `Design.*` tokens only |
| `Herald/Models/HeraldArtifact.swift:47-60` | id/sessionID/type/string content/date | Not a note model. Leave untouched |
| `Herald/Models/PendingAttachment.swift:20-24` | 350 KB per file, 4 per message | These limits are for chat attachments — **never** apply them to drawings |
| `Herald/Models/PendingAttachment.swift:169-190` | Atomic write into Application Support subdirectory | Reuse this *pattern* (own `Herald/Notes/` subdir, `.atomic` writes, sanitized names) |
| `Herald/Services/Live/JobStreamCoordinator.swift`, `JobEventReducer.swift` | Durable stream coordinator + reducer (v1.7.0, fixed by S1–S3) | `NoteRunCoordinator` wraps these semantics; do not write a second best-effort SSE client |
| `relay/app/models.py:230-299` | `Conversation`/`Message`/`MessageJob` (unique `user_message_id`, `attempt`)/`JobEvent` (`seq`, `attempt`, `source_seq`) | No note FKs into these tables. New note tables mirror the `JobEvent` sequencing shape |
| `relay/app/main.py:2127-2195` | `/v1/messages`: dedupe by `client_message_id`, append message, create job | **Never** submit notes through this endpoint. Copy its idempotency *shape* for `POST /v1/notes/{id}/runs` |
| `relay/app/services.py:1562,1628,1653,1660` | `append_job_event`, `get_job_events_after`, `get_job_last_seq`, `cleanup_old_job_events` | Mirror these for `note_run_events` (same seq/cursor/replay/retention semantics) |
| `connector/src/herald_connector/client.py:1202-1235` | `_handle_rpc_request` `elif` chain (`talk.*`, `commands.catalog`, `models.list`, `cron.*`) | Add `note.enrich` here, dispatching to a new note executor |
| `project.yml:18,80-81,138-139` | iOS 18.0 target; versions | Availability-gate recognizer APIs; bump both targets every change |

---

## Phase 0 — Spike and contracts (no production code until the exit gate passes)

**Commit N0.1 — version reconciliation (do this first, alone).**
Align `project.yml` (`:80-81`, `:138-139`) with the README badge (`README.md:14`): bump both to `1.7.1 / build 37` (badge already claims 1.7.1), add a CHANGELOG entry noting the reconciliation, `xcodegen generate`. Rollback point: trivial revert.

**N0.2 — SDK availability probe (throwaway branch, not merged).**
Create a scratch target/playground that compiles `PKStrokeRecognizer` behind `#available`, plus tool-picker custom items, Pencil double-tap (`UIPencilInteraction`), and squeeze APIs. **Record the exact availability annotations Xcode reports** — do not infer from the deployment target. Output: a short table pasted into `docs/NOTES_CONTRACT_V1.md` (N0.3).

**N0.3 — physical spike on hardware.**
On the oldest supported iPad with a Pencil: `PKDrawing.dataRepresentation()` round-trip fidelity; recognition quality on representative handwriting at Letter/A4 point scale; language support list; recognition cancellation; memory profile with a large multi-page drawing. Also verify the Vision fallback (`PKDrawing.image(from:scale:)` → accurate text recognition) on the same samples and record its relative accuracy.

**Commit N0.4 — `docs/NOTES_CONTRACT_V1.md` + fixtures.**
Check in the contract doc (schemas below, availability table from N0.2, spike results from N0.3, backend decision from 0.C) plus JSON fixtures in **three** places that must stay byte-identical: `HeraldTests/Fixtures/Notes/`, `relay/tests/fixtures/notes/`, `connector/tests/fixtures/notes/`. Request/response schemas:

```json
// enrichment request (client → relay → connector)
{
  "schemaVersion": 1,
  "noteId": "uuid",
  "clientRunId": "uuid",
  "sourceDrawingRevision": 12,
  "sourceTextRevision": 8,
  "recognizedText": "corrected OCR text",
  "directives": [
    {"id": "stable-id", "command": "research", "arguments": "battery supply chain",
     "sourceRange": {"location": 94, "length": 39}}
  ],
  "locale": "en-US",
  "timezone": "America/Los_Angeles"
}
```

```json
// enrichment result (connector → relay → client); schema-validated, never free prose
{
  "schemaVersion": 1,
  "title": "...",
  "markdown": "...",
  "sections": [{"kind": "summary", "title": "Summary", "markdown": "..."}],
  "commandResults": [{"directiveId": "...", "status": "completed", "sectionIndex": 1}],
  "citations": [{"title": "...", "url": "https://...", "accessedAt": "..."}],
  "warnings": []
}
```

**Gate 0.C — metadata backend decision.** SwiftData for the local note index (recommended; iOS 18 baseline supports it; the repo has no Core Data/SwiftData today so this is a deliberate introduction — flag to the operator if you find a blocking constraint) vs. a small SQLite repository. Either way: blobs in files, metadata transactional, `PKDrawing` bytes and rendered pages never in UserDefaults.

**Phase 0 exit gate:** N0.2 availability table recorded, N0.3 physical Pencil test passed, N0.4 contract + fixtures merged, 0.C decided. Only then does Phase 1 begin.

---

## Phase 1 — Local-first Notes and Pencil editor (iPad only)

New files:

```text
Herald/Models/HeraldNote.swift            // Note, NoteDrawingRevision (immutable), folder/pin metadata
Herald/Models/NoteRecognition.swift
Herald/Models/NoteDirective.swift
Herald/Features/Notes/NotesRepository.swift        // files + metadata index; the ONLY writer
Herald/Features/Notes/NotesStore.swift             // @Observable @MainActor, injected like ChatStore
Herald/Features/Notes/NotesWorkspaceView.swift     // Notes-owned list/editor split in the detail column
Herald/Features/Notes/NotesListView.swift
Herald/Features/Notes/NoteEditorView.swift
Herald/Features/Notes/PencilCanvasRepresentable.swift
Herald/Features/Notes/NotePaperBackground.swift
```

Modified files: `iPadSidebarView.swift` (enum + `bottomSections` array), `AdaptiveRootView.swift` (`contentColumn` → `.notes`; hide or repurpose the inspector while editing — decide with the operator only if you want it to show enrichment activity in Phase 4), `AppContainer.swift` + `AppEntry.swift` (construct/inject), `project.yml` only for version bumps.

Data model (local; mirrors the relay schema in Phase 3):

```text
Note: id, title, folderId?, pinned, createdAt, updatedAt,
      currentDrawingRevision, currentTextRevision, syncState, deletedAt?
NoteDrawingRevision (immutable): noteId, revision, blobPath, contentHash(SHA-256),
      canvasSize, pageStyle, createdAt, deviceId
```

Hard constraints:

- The `UIViewRepresentable` coordinator owns the `PKCanvasView`, its delegate, and `PKToolPicker` observation; the canvas must **not** be recreated on SwiftUI state refresh (assert identity in a test if practical).
- Persist only after a 300–750 ms settle debounce **and** at `background`/resign-active (hook the existing `scenePhase` handling pattern in `AppEntry.swift:136-141`). Atomic replace via the `PendingAttachment.stageLocally` pattern into `Application Support/Herald/Notes/<noteId>/rev-<n>.pkdrawing`; verify content hash after write.
- Drawing revision increments **only** when a new representation is persisted, not per delegate callback.
- Page scale ≈ Letter/A4 points; `PKToolPicker` gets a stable `stateAutosaveName`; `drawingPolicy` follows the system pencil-only preference — do not add a contradictory Herald setting. Do not hard-code squeeze/double-tap actions; honor `UIPencilInteraction` preferred actions.
- Undo/redo through the canvas undo manager; restore first-responder/tool-picker per window.
- Soft delete with restore; hard delete only after the 30-day window (enforced in repository, surfaced in UI).
- Accessibility: labels on all chrome, keyboard title entry, Dynamic Type around the canvas, high-contrast paper option.

Suggested commits: **N1.1** models + repository + repository unit tests → **N1.2** store + sidebar/routing + navigation tests (must assert `.notes` present in `bottomSections`) → **N1.3** canvas representable + editor UI → **N1.4** list management (create/rename/delete/pin/folder/search/sort) → **N1.5** persistence hardening (debounce, hash verify, force-quit recovery test).

**Phase 1 acceptance (on hardware):** create/edit/reopen/delete/restore several notes; force-quit mid-stroke loses at most the un-settled stroke batch, never corrupts the last committed revision; pencil vs. finger policy matches system settings; airplane mode changes nothing.

---

## Phase 2 — On-device recognition and directive review

New files:

```text
Herald/Services/Protocols/HandwritingRecognizing.swift   // protocol, Sendable
Herald/Services/Live/PencilStrokeRecognizer.swift        // PKStrokeRecognizer, availability-gated per N0.2
Herald/Services/Live/VisionHandwritingRecognizer.swift   // render + accurate recognition fallback
Herald/Features/Notes/NoteRecognitionCoordinator.swift   // actor, one per open note
Herald/Features/Notes/NoteDirectiveParser.swift          // pure, deterministic, Sendable
Herald/Features/Notes/RecognizedTextReviewView.swift
HeraldTests: MockHandwritingRecognizer + parser fixture tests
```

Rules:

- Coordinator cancels stale recognition tasks and drops any result whose `sourceDrawingRevision` no longer matches. Recognize after pencil-up settle, never per stroke.
- Persist `NoteRecognition`: engine kind, engine version (`recognitionVersion` where available), languages, source revision, raw text, `userCorrectedText?`, timestamp. Re-run when the revision or engine version advances. Surface lower confidence for the Vision path.
- Directive grammar (versioned, in the parser and in `docs/NOTES_CONTRACT_V1.md`):

```text
directive := line-start ws* "#" command (ws arguments)? line-end
command   := case-insensitive ASCII token from the v1 allowlist only
```

  `#` mid-sentence/URL/code/struck-through region is text. Unknown tags render as "unrecognized tag" and are never sent as intent. Parser runs on `userCorrectedText` when present, else raw text; emits stable directive IDs and a normalized fingerprint over `(noteId, sourceTextRevision, command, arguments, sourceRange)` so OCR churn and save retries cannot duplicate execution.
- Recognition never executes anything. Execution begins only at explicit "Enrich"/"Run commands" (locked decision 4).

**Phase 2 acceptance:** parser fixtures cover whitespace, case, duplicates, URLs, prose `#`, unknown commands, Unicode, misrecognized command, corrected OCR, revision-mismatch cancellation. OCR works offline on supported hardware; unsupported language degrades to "recognition unavailable", never blocks writing.

---

## Phase 3 — Relay Notes API, blob sync, and Hermes enrichment runs

**Entry gate:** one verified end-to-end streamed chat turn against the field relay (post S1–S3), reconnect included. Record the check in the phase's first CHANGELOG entry.

### 3a. Schema (new tables — ride `create_all`; no ALTERs to existing tables)

Add to `relay/app/models.py` (mirror existing style: `String(36)` ids, `utcnow` timestamps, ownership via `user_id` FK to `users`):

```text
notes                    id, user_id, title, folder_id?, pinned, current_drawing_revision,
                         current_text_revision, created_at, updated_at, deleted_at?
note_blobs               id, note_id, drawing_revision, content_hash, byte_size,
                         storage_path, created_at        (UNIQUE (note_id, drawing_revision))
note_recognitions        immutable OCR snapshot + engine metadata, keyed to drawing revision
note_runs                id, user_id, note_id, client_run_id, source_drawing_revision,
                         source_text_revision, requested_directives JSON, status,
                         attempt, lease_expires_at?, error_text?, result JSON?,
                         created_at, completed_at?       (UNIQUE (user_id, client_run_id))
note_run_events          id, run_id, seq, attempt, source_seq?, type, payload_json,
                         created_at                      (mirror JobEvent, models.py:291-299)
enriched_note_revisions  id, note_id, run_id, source_drawing_revision, source_text_revision,
                         schema_version, title, markdown, structured_sections JSON,
                         citations JSON, command_results JSON, is_stale, created_at
derived (client-side only): the user-editable Markdown copy — never a relay table; it syncs
                         as a note field if the operator later asks, not in v1
```

No FKs from any note table into `messages`/`message_jobs`/`job_events`. If you find yourself wanting to generalize `job_events` instead, stop and flag it — that is an architecture change requiring the operator.

### 3b. Endpoints (new router: `relay/app/notes.py`, not more code in `main.py`)

```text
GET    /v1/notes                              list (owner-scoped, excludes hard-deleted)
POST   /v1/notes
GET    /v1/notes/{noteId}
PATCH  /v1/notes/{noteId}                     requires If-Match on current revision → 412 on mismatch
DELETE /v1/notes/{noteId}                     soft delete; purge after 30 days
PUT    /v1/notes/{noteId}/blobs/{revision}    body = PKDrawing bytes; X-Content-SHA256 verified;
                                              size cap 25 MB (config-backed); 409 if revision exists
GET    /v1/notes/{noteId}/blobs/{revision}
POST   /v1/notes/{noteId}/recognitions
POST   /v1/notes/{noteId}/runs                idempotent on clientRunId (copy the dedupe shape
                                              from main.py:2134-2164)
GET    /v1/note-runs/{runId}
GET    /v1/note-runs/{runId}/events           cursor + replay, same semantics as job events
POST   /v1/note-runs/{runId}/cancel           terminal, idempotent
```

Ownership checks follow the house policy (404 for wrong owner, as `main.py:2168-2169` does for conversations). Audit records carry command names and run ids — never OCR text or note bodies. Blob upload happens only after a save debounce, never per stroke; iOS uploads in background with retry, and `syncState` on the note reflects it.

### 3c. Run lifecycle and the revision fence

`POST …/runs` snapshots the corrected OCR text + directives *into the run row* (immutable input). Terminal application rule: the run's result becomes the **current** `EnrichedNoteRevision` only if `(source_drawing_revision, source_text_revision)` still match the note's current revisions at completion; otherwise persist it with `is_stale = true`. A stale result is history, never an error. Cancellation is terminal. Lease/requeue follows `requeue_expired_message_jobs` semantics (`services.py:1124`) — accepted-but-slow is not failure (host OOM reality).

### 3d. Connector

- `connector/src/herald_connector/note_contract.py`: request/response dataclasses + strict schema validation (both directions), shared fixtures from N0.4.
- New RPC `note.enrich` in the `_handle_rpc_request` chain (`client.py:1209-1235`), dispatching to a note executor that reuses the existing Hermes runtime/session/tool capability (same substrate as the chat executors).
- Prompt boundary, non-negotiable: system/developer text defines the output schema + command policy; OCR text is delimited as **untrusted user-authored content** and never interpreted as Herald control messages; only parser-produced allowlisted directives become tool intent; web results require citations with access dates; no claimed source without a tool result; **no writes/messages/calendar/external mutation in v1**.
- An invalid terminal payload fails the run recoverably (schema error preserved in `error_text`); it is never saved as an enriched revision and never damages ink/OCR.

### Phase 3 acceptance

Duplicate `clientRunId` returns the original run (same shape as `/v1/messages` dedupe). Disconnect/reconnect resumes from cursor with no loss or duplication. Cancel is terminal. Wrong owner → 404. Late result → stale history. Malformed structured output → recoverable failure. Blob upload rejects hash mismatch and over-cap sizes; second device can fetch and render the blob. `relay/tests/test_api.py`-style CRUD + concurrency tests, `test_streaming.py`-style event replay tests, `connector/tests/test_stream_contract.py`-style contract tests all pass on clean **and** existing SQLite + Postgres databases. Allowlist enforcement is asserted **relay-side before dispatch**, not only in the prompt.

Suggested commits: **N3.1** models + `create_all` + storage tests → **N3.2** notes CRUD router + ownership/If-Match tests → **N3.3** blob endpoints + iOS upload/download in `LiveNotesClient` → **N3.4** run lifecycle + events + fence tests → **N3.5** connector `note.enrich` + contract tests → **N3.6** end-to-end against local relay + Hermes.

---

## Phase 4 — Enriched document UI, iPhone read-only tab, hardening

New files:

```text
Herald/Features/Notes/EnrichedNoteView.swift
Herald/Features/Notes/NoteCommandStatusView.swift        // detected → queued → running → terminal
Herald/Services/Live/LiveNotesClient.swift               // started in N3.3; completed here
Herald/Services/Live/NoteRunCoordinator.swift            // wraps JobStreamCoordinator/JobEventReducer semantics
Herald/Features/Notes/NoteReadOnlyView.swift             // iPhone: rendered ink + recognized + enriched
```

Modified: `Router.swift` (`AppTab.notes` + deep link), `ContentView.swift:12-46` (read-only Notes tab), `AdaptiveRootView.swift` (enrichment activity in the right panel if the inspector is used).

Behavior:

- Editor toggle **Ink / Recognized / Enriched**; ink always canonical. Enriched view edits the *derived copy*; "view original" reaches every immutable `EnrichedNoteRevision`.
- Stale banner: "Re-run from revision N", older result retained.
- Citations open only after standard URL validation. Export layers: PDF-with-ink, recognized text, enriched Markdown + citations — user selects.
- iPhone tab is read-only: renders synced blobs via `PKDrawing` imaging, no canvas, no tool picker; deep links to notes not yet synced show a graceful placeholder.

**Phase 4 acceptance matrix (hardware):** offline capture → later run; background/foreground during OCR and during a run; relay/connector restart mid-run; rotation; split-screen and Stage Manager widths (the `minChatWidth`/inspector constraints in `AdaptiveRootView.swift:13-15` must not squeeze the canvas below usable); large multi-page note; low storage; unsupported language; no Pencil; Pencil Pro squeeze + non-Pro double-tap; VoiceOver and keyboard-only.

---

## Track T — Talk / Streaming / Reasoning field debug (P0/P1; independent of Notes)

Reported from device 2026-07-20 15:50–15:52 PT after pairing was restored (real Hermes replies now land: ignyte profile, `deepseek-v4-flash`, cost line renders). Six defects, grounded below. **Tree moved to HEAD `1147c68` ("gate inline think blocks on Show Reasoning toggle") — past this doc's `5dd5c67` baseline; re-resolve the line numbers before editing.** Assess read-only, then fix one defect per commit with a version bump + CHANGELOG each (see T6).

### T1 (P0) — Talk still crashes

`c05da0a` (v1.7.1) claims the Talk startup crash is fixed (`TalkAudioCapture.swift` permission/format/prepare guards) and `HermesTalkCoordinator` is now constructed and attached (`Herald/Stores/AppContainer.swift:346-354`, wired via `TalkStore.attachHermesCoordinator` `TalkStore.swift:46`). Per the user it **still crashes**. The fix was incomplete — remaining suspects, in order: the audio-tap install on a non-nil-but-invalid input format; the `MimoASRService`/`MimoTTSService` credential path (`apiKeyHolder.get()` returning empty → force-unwrap or fatal downstream); `PCMPlaybackQueue` engine start. **This is a repro-needed item — do not guess the line.** Instrument: run Talk on device with a symbolicated debug build, capture the crash stack, and confirm which of `TalkAudioCapture` / `MimoASRService` / `PCMPlaybackQueue` / `HermesTalkCoordinator` frame is on top. Fix path follows the actual frame; acceptance = Start Talking → orb active → one full spoken round-trip → End, with no termination, plus a unit test around the specific failure (empty API key, invalid format) that returns a recoverable `.failed` state (`TalkStore` already models it).

### T2 (P0) — No token-by-token streaming; reply appears whole after "THINKING… 8s"

The reducer has both delta paths (`JobEventReducer.swift:96-102` reasoning, and the text-delta case alongside it) and the client yields `.reasoningDelta` at `LiveHeraldClient.swift:463-467`; the connector emits `text_delta`/`reasoning_delta` incrementally (`connector/src/herald_connector/herald_api_executor.py:23,275-284`). Yet on device the answer renders in one shot. Root cause is one of: (a) events are batched/only flushed at terminal in the relay durable-log read path (verify S1–S3 actually stream mid-job, not just persist), (b) the reducer projection mutates but the `@Observable` message the bubble reads is only reassigned on terminal, so SwiftUI never re-renders intermediate deltas, or (c) `LiveHeraldClient` buffers the `AsyncStream` and only surfaces text on `finish`. **Instrument first:** log event arrival timestamps at `LiveHeraldClient` yield and at each `JobEventReducer` case, and confirm whether deltas arrive spaced-out (server streams, client buffers) or all-at-once (server batches). Fix at whichever layer collapses the stream. Acceptance = visible incremental text growth for a multi-second `deepseek-v4-flash` turn, on device, over both the v2 and v1-fallback SSE paths.

### T3 (P1) — Reasoning renders twice ("vomit of text")

The same chain-of-thought appears verbatim twice in one turn. There are **two independent reasoning render paths**, and this turn hit both:
1. `ReasoningView` from `message.reasoning` (the streamed `reasoning_delta` → reducer `reasoningSegments`, `MessageBubble.swift:198-206`).
2. `ThinkingBlockView` from an inline `<think>` block parsed out of `message.content` (`MarkdownContentView.swift:49-51`).
So if the terminal Hermes text *also* carries the reasoning inline (as a `<think>` block or plain prose), it prints once as the reasoning box and again as content. A secondary suspect for exact-2x-within-the-box: the reducer appends a second `reasoningSegments` entry (segment-id handling at `JobEventReducer.swift:99-102`) — check whether `deepseek-v4-flash` sends `reasoning_content` **cumulatively** (full-so-far each chunk) while the reducer treats it as an additive delta (`+= payload.delta`), which would compound reasoning. **Decide one canonical home for reasoning** (the streamed `message.reasoning` → `ReasoningView`) and have the connector/relay strip the reasoning from terminal display content so path 2 never double-renders it. Acceptance = reasoning appears exactly once; cumulative-vs-delta reasoning is normalized in the reducer with a fixture test.

### T4 (P1) — "Show Reasoning" toggle does nothing

`showReasoning` gates both render paths (`ReasoningView` at `MessageBubble.swift:198`; `ThinkingBlockView` at `MarkdownContentView.swift:50`), and `1147c68` just added the inline gate. Yet reasoning still shows with the toggle off. That means reasoning is reaching the UI as **plain content text that is not recognized as a `<think>` block** (so neither gate matches it) — i.e., the gateway/connector is inlining `deepseek`/`mimo` `reasoning_content` into the terminal display string as prose. Fix belongs at the connector/relay boundary: reasoning must travel only as `reasoning_delta` events (never concatenated into the answer text), so the single `showReasoning` gate is authoritative. Ties directly to T3 (same root: reasoning leaking into content). Acceptance = toggling Show Reasoning off hides all chain-of-thought for a fresh turn on every model, with no reasoning residue in the answer body.

### T5 (P1) — Two sets of thinking dots; one disappears — which is real?

Two indicators race during the sent→first-token gap:
- **List-level** `ThinkingIndicatorView` (avatar "H" + live "Thinking… Xs" timer) at `ChatScreen.swift:627`.
- **Bubble-level** `streamingPlaceholder` = `TypingDotsView` at `MessageBubble.swift:196,210,280`, shown when the streaming message has empty content/reasoning.
Both can be on screen simultaneously (screenshot: top-level `…` plus the "H … THINKING… 8s" row), and one drops out when the streaming bubble gains content. The **authoritative** one is `ThinkingIndicatorView` (it's bound to the actual pending-job/elapsed state); `TypingDotsView` is a redundant placeholder. Fix = show exactly one: suppress the bubble `streamingPlaceholder` while the list-level `ThinkingIndicatorView` is active (or drop the list-level one once the bubble exists) so there is a single, continuous indicator. Acceptance = one thinking indicator from send through first token, no flicker/double-dots, on device.

### T6 (process, P1) — Ship discipline: version every update

`1147c68` ("gate inline think blocks…") shipped **after** the `v1.7.1` release commit `c05da0a` with **no version bump** — `project.yml` is still `1.7.1 / 37` and there's no `1.7.2` CHANGELOG entry. That violates ground rule 1/2 (one change = one commit = one version bump + dated CHANGELOG entry, both targets + README badge). This is the "Mimo didn't version the update" report. Remediate: fold the T1–T5 fixes into properly-versioned commits, and back-fill a CHANGELOG note that `1147c68` landed under `1.7.1` unversioned. Going forward, no user-visible behavior change merges without the version-bump trio.

**Sequencing:** T1 and T2 are P0 (Talk unusable; streaming is the core chat feel). T4 depends on the same connector/relay reasoning-plumbing fix as T3 — do T3/T4 together. T5 is UI-only. T6 wraps all of them. None of these touch Notes; they can land before or in parallel with Track R/P and Phase 0.

---

## Track R — Relay: SQLite FK-repoint debt from the Hermes→Herald rebrand (independent of Notes; P1)

Discovered live 2026-07-20 while minting pairing codes (full diagnosis in "Relay operations in this environment"). The rebrand's FK-repoint in `relay/app/database.py:_run_migrations` uses Postgres-only `ALTER TABLE … DROP/ADD CONSTRAINT`, wrapped in `_exec_safe`, so it **silently no-ops on the SQLite prod DB** (`.101`). Result: the orphan `hermes_hosts` table lingers and four tables keep FKs pointing at it while live hosts moved to `herald_hosts`. Any insert/commit binding one of these rows to a current host raises `FOREIGN KEY constraint failed`.

Affected tables: `phone_pairing_codes` (**already hand-fixed on prod 2026-07-20** — pairing works now), `host_enrollment_invites`, `voice_sessions`, `message_jobs` (still broken).

### Commit R1 — make the rebrand FK-repoint dialect-aware in `_run_migrations`

- Detect dialect (`db.dialect.name`). On Postgres keep the existing `DROP/ADD CONSTRAINT`. On **SQLite**, for each affected table do the create-copy-drop-rename rebuild with `PRAGMA foreign_keys=OFF` inside a transaction, producing a table whose `host_id`/`created_by_host_id` (and `redeemed_host_id` for invites) FKs reference `herald_hosts`.
- **Idempotent / restart-safe** (house rule, and required because `phone_pairing_codes` was already rebuilt by hand on prod): before rebuilding a table, read its `sqlite_master.sql`; skip if it already references `herald_hosts` and not `hermes_hosts`. So re-running the migration on the already-patched prod DB is a no-op for pairing and only repairs the remaining three.
- After all four reference `herald_hosts`, `DROP TABLE IF EXISTS hermes_hosts` (only once no FK references it — verify via `sqlite_master` scan).
- Guard the whole block so it also runs correctly on a **fresh** SQLite deploy where `create_all` already built correct tables (nothing to rebuild → skip).

### Commit R2 (optional, operator's call) — reconcile the split host tables

The 28 legacy `phone_pairing_codes` rows and older host references live under host-ids that were in `hermes_hosts`, not `herald_hosts`. R1 leaves those as harmless historical FK-violations (SQLite only checks rows it writes). If the operator wants a clean `PRAGMA foreign_key_check`, R2 migrates any still-referenced `hermes_hosts` rows into `herald_hosts` before the drop. Not required for correctness; flag before doing it (touches identity rows).

**Acceptance:** on a copy of the prod SQLite DB, `_run_migrations` runs clean and idempotently (twice = same result); `PRAGMA foreign_key_check` reports no violations on newly-written rows; `POST /v1/connector/phone-pairing-codes`, a fresh `herald enroll`, and a voice-session create all return 2xx; a message-job write that sets `host_id` to a `herald_hosts` id commits; re-running the migration on the hand-patched prod DB changes nothing. Back up `data/relay.db` before deploying. Relay-only commit — no version bump of the iOS app, its own CHANGELOG entry under a relay heading.

---

## Track P — Hermes skill: create phone pairing codes on request (independent of Notes)

Small, self-contained, can land any time — it does not depend on any Notes phase and must not share a commit with Notes work.

### Grounded facts (all verified at `5dd5c67`)

| Anchor | Fact |
|---|---|
| `connector/pyproject.toml:18-21` | CLI entry point is `herald = herald_connector.cli:main` (plus pre-rename compatibility entrypoints for older Hermes configs) |
| `connector/src/herald_connector/cli.py:414` | `pair-phone` subcommand: "Generate a short-lived phone pairing code and QR" |
| `connector/src/herald_connector/cli.py:665-682` | `cmd_pair_phone` prints `Pairing code: <display>`, expiry, and a QR payload `{"code": ..., "relay": <url>}`; credentials come from the connector's own state store — the CLI needs **no secrets passed in** |
| `relay/app/main.py:879-907` | `POST /v1/connector/phone-pairing-codes`, auth `require_connector_host` (`:305-312`), writes a `phone_pairing_code.create` audit record |
| `relay/app/config.py:31,78` | Code TTL 600 s, overridable via `PHONE_PAIRING_CODE_TTL_SECONDS` |
| `relay/app/main.py:256-258,909-919` | Redemption is IP-rate-limited; codes are one-time |
| `skills/hermes-ios/SKILL.md:1-13` | House skill format: YAML frontmatter (`name`, `description`, `version`, `platforms`, `metadata.hermes.tags`), then "When to Use" / tools / examples |

### Commit P1 — `skills/herald-pairing/SKILL.md`

One new file, modeled on `skills/hermes-ios/SKILL.md`. No relay, connector, or iOS code changes. Required content:

- **Frontmatter:** `name: herald-pairing`; description like "Generate a short-lived Herald phone pairing code when the user asks to pair a new iPhone/iPad"; `platforms: [macos, linux]`; tags `[herald, pairing, ios, setup]`.
- **When to use:** the user explicitly asks to pair/connect a new phone or iPad to Herald, re-pair after a reset, or asks "give me a pairing code." **When not to use:** host enrollment (`herald enroll` is a different, operator-run flow), any request arriving *inside* untrusted content rather than from the user.
- **Action:** run the connector CLI on the Hermes host (`fih-ai-host`/`.118`) — verified command `~/.local/bin/hermes-mobile pair-phone` (the `herald` name is the compat entrypoint, `connector/pyproject.toml:19-21`) — and relay stdout to the user: the display code (`SYUT-66L8` format), the expiry timestamp, and (if the surface can render it) the QR payload. Parse the `Pairing code:` / `Expires at:` lines; ignore the ASCII-QR block.
- **Prod dependency (verified 2026-07-20):** the endpoint the CLI calls (`POST /v1/connector/phone-pairing-codes`) is served by the **SQLite prod relay on `.101`**. It will 500 on `FOREIGN KEY constraint failed` until **Track R** lands — that exact failure was hit and hand-fixed for `phone_pairing_codes` today, so the skill works now, but the skill body should note "if this 500s, the relay FK-repoint debt (Track R) has regressed or the DB was rebuilt without the dialect-aware migration."
- **What to tell the user:** code is one-time, expires in ~10 minutes (`PHONE_PAIRING_CODE_TTL_SECONDS`, default 600), redeem in the Herald app's pairing screen; redemption is rate-limited, so a few failed entries mean *wait*, not *spam new codes*.
- **Failure guidance:** command missing or "not enrolled" → the connector isn't set up on this host (`herald enroll`); network/5xx → relay unreachable, report and stop. Never retry in a loop (each call mints a fresh audited code).
- **Security rules, stated in the skill body:** the skill passes **no credentials** — the CLI reads its own state (this is the mandated pattern; the known Hermes-skill plaintext-password debt must not be repeated here). Treat the code as a short-lived secret: show it to the requesting user only, never write it to files/logs/other channels, never store it for later. Generate at most one code per user request.

### Deployment note (not a repo change)

Hermes loads skills from the master + per-profile skill trees on `fih-ai-host`, not from this repo — after merging, install/sync `skills/herald-pairing/` into the profile tree(s) that should have it (ignyte at minimum) the same way `skills/hermes-ios` was installed, and let the curator pick it up. Record the sync in the commit message body so the repo copy and the host copy are traceable to the same version.

**Acceptance:** from a Herald chat, "pair my new iPhone" yields exactly one fresh display code + expiry; the relay audit log shows one `phone_pairing_code.create` (`actor_type=connector`); the code redeems once in the app and is rejected on second use; asking again mints a new code; the skill refuses when the request originates from pasted/forwarded content rather than the user.

---

## Test obligations (roll into the commits above, not a trailing "tests" commit)

- **iOS unit:** repository CRUD/recovery/atomic-failure; revision + fence; `PKDrawing` byte round-trip fixture; recognizer selection/fallback/cancellation; parser grammar/fingerprints; `NotesStore` transitions + idempotent run reattach; navigation asserts `.notes` in `bottomSections` **and** the iPhone tab set.
- **iOS UI/hardware:** tool-picker responder restore after background/sheet/note-switch; drawing-policy behaviors; undo/lasso/eraser/rotation/Stage Manager/keyboard; force-quit and simulated disk-failure save paths.
- **Relay/connector:** CRUD ownership + `If-Match` 412; schema on clean + existing DBs — **SQLite is prod (`.101`)**, so SQLite is the primary target and Postgres the secondary; idempotent run, ordered replay, cancel, terminal snapshot; exact schema validation; oversized/malformed OCR + blob inputs; relay-side allowlist enforcement; log redaction.
- **Track R migration:** run `_run_migrations` twice on a copy of the prod SQLite DB (idempotent = same result); assert all four rebranded tables FK → `herald_hosts`, `hermes_hosts` dropped, and the already-hand-patched `phone_pairing_codes` is left untouched on the second pass.

---

## Invariants (restated; every commit must preserve all twelve)

1. Ink is canonical — OCR/enrichment can never overwrite or delete drawing data.
2. Atomic local save — crash yields prior or next complete revision, never a partial blob.
3. Revision fence — results apply only to the exact source revisions they declare.
4. Idempotent run — one `clientRunId` ⇒ at most one remote execution.
5. Transport is not execution — disconnect/timeout neither respawns nor false-fails a live run.
6. OCR detection alone never triggers a remote tool.
7. Allowlist before prompt — enforced relay-side; unknown tags are data.
8. v1 tools are read-only.
9. Least disclosure — remote payload is corrected OCR + directive context; rendered image only when recognition needs visual disambiguation, and opt-in.
10. Auditable provenance — every generated section retains source revisions, directive, citations, run id.
11. Private logs — no blobs, full OCR, prompts, or generated docs in logs/telemetry.
12. Graceful degradation — writing and local viewing work with no Pencil, no host, no network, unsupported language.

---

## Commit sequence (independent PRs; each self-contained with version bump + CHANGELOG)

| # | Commit | Phase | Rollback point |
|---|---|---|---|
| 1 | N0.1 version reconciliation → `1.7.1 / 37` | 0 | trivial revert |
| 2 | N0.4 contract doc + tri-location fixtures | 0 | docs-only |
| — | **GATE:** availability table + hardware spike + backend decision recorded | 0 | — |
| 3–7 | N1.1–N1.5 local models/repo → sidebar → editor → list mgmt → persistence hardening | 1 | each commit leaves iPad app shippable; Notes hidden behind the sidebar entry only |
| 8–9 | N2 recognizers + coordinator; parser + review UI | 2 | recognition can be disabled without touching editing |
| — | **GATE:** field-relay streamed turn verified end-to-end | 3 | — |
| 10–15 | N3.1–N3.6 relay schema → CRUD → blobs → runs/events → connector → e2e | 3 | relay tables are additive; iOS sync behind `syncState`, editor never blocks on it |
| 16–18 | N4 enriched UI + run coordinator; iPhone read-only tab + deep links; hardening matrix | 4 | iPhone tab is the last user-visible switch flipped |
| P0, do first | T1 Talk crash (repro + stack), T2 no-streaming (instrument + fix) | T | each isolated to Talk/stream path; revertible per commit |
| P1 | T3+T4 reasoning double-render + toggle (one connector/relay reasoning-plumbing fix), T5 dedupe thinking indicators, T6 version back-fill + discipline | T | UI/plumbing only; no schema, no Notes |
| any (do early) | R1 dialect-aware FK-repoint in `_run_migrations` + drop orphan `hermes_hosts` | R | idempotent migration; back up `data/relay.db`; re-run reverts to no-op |
| optional | R2 reconcile split host tables (operator flag) | R | separate commit; skip unless clean `foreign_key_check` wanted |
| any | P1 `skills/herald-pairing/SKILL.md` (+ host-side skill-tree sync, out of repo) — depends on R1 for a durable prod endpoint | P | docs-only in repo; remove from skill tree to roll back |

## Flag-before-coding list (stop and ask the operator, per spec)

Any change that would: move ink off local-first authority; expand or shrink the relay blob scope; change iPhone beyond read-only; add a non-read-only command or any auto-run; generalize `job_events`/`MessageJob` instead of adding note tables; introduce SwiftData anywhere beyond the note index; or touch Talk/streaming files from a Notes commit.

## Operator action items (not Mimo's; surfaced 2026-07-20)

1. **SSH key to prod relay `.101`.** No key auth exists there today (had to use password SSH to fix the relay). `ssh-copy-id fihadmin@192.168.10.101` a key from an authorized box so relay ops don't need the password inline.
2. **Rotate the `fihadmin` password.** It was pasted in chat during this session and is the same credential already flagged as plaintext debt across the Hermes skill files (`[[hermes-skills-hardcoded-password]]`). Rotate and move to a secrets store; then update the connector/host configs that consume it.
3. **Correct `HERALD_PROJECT_BRIEF.md §9.2`** on its next edit: field relay is the **SQLite `hermes-relay` container on `192.168.10.101` behind Caddy**, not `192.168.10.118:8010` Postgres.
4. **Deploy Track R to prod** after it merges (back up `data/relay.db` first) so `host_enrollment_invites` / `voice_sessions` / `message_jobs` stop being one write away from the same 500.
