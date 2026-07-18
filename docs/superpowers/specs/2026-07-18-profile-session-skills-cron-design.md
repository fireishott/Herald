# Profile Selector, Session History Polish, Skills Browser, Cron Manager Design

## Overview

Add four features to Hermes iOS and six new relay endpoints. The iOS app gains a Profile Selector sheet, a Skills Browser screen, a Cron Manager screen, and session history UX polish. The relay gains passthrough RPC endpoints for profiles, skills, cron, memories, and tools. The connector gains corresponding RPC handlers.

**Scope decisions:**
- Profile Selector: switch + view summary (not full CRUD)
- Skills Browser: browse installed skills (read-only)
- Cron Manager: view, create, toggle, delete scheduled jobs
- Memories & Tools: relay endpoints only, no iOS UI yet
- Session History: UX polish of existing sidebar (no new endpoints)

---

## Section 1: Profile Selector

### iOS

**New files:**
- `HermesMobile/Features/Chat/ProfileSelectorSheet.swift` — SwiftUI sheet listing available profiles
- `HermesMobile/Stores/ProfileStore.swift` — `@Observable` store for profile data

**ProfileSelectorSheet:**
- Lists profiles with name, description, and skill count
- Active profile marked with checkmark
- Tap to switch — dispatches `/profile <name>` through chat path (same as model selector)
- Groups: active profile at top, rest alphabetically

**ProfileStore:**
- `@MainActor @Observable final class ProfileStore`
- Model: `HermesProfile { name, description, skillCount, isActive }`
- Calls `GET /v1/profiles` via `RelayAPIClient`
- 60-second cache interval (same as ModelStore)
- `markActive(name)` for optimistic local update; real confirmation from chat response
- `ChatStore.detectProfileSwitch()` parses agent response text to confirm switch

**Toolbar integration in ChatScreen.swift:**
- New profile chip next to model chip: profile name + `brain.head.profile` icon
- Tap opens ProfileSelectorSheet as popover
- Layout: `[Profile chip] [Model chip]` in toolbar

### Relay

**File:** `relay/app/main.py`

```python
@app.get("/v1/profiles")
async def profile_catalog(auth: AuthContext = Depends(get_auth_context)) -> dict:
    try:
        result = await send_connector_rpc(
            auth.user.id, method="profiles.list", timeout_seconds=10.0,
        )
        return success(result)
    except HTTPException:
        return success({"profiles": [], "activeProfile": None})
    except Exception:
        return success({"profiles": [], "activeProfile": None})
```

### Connector

**File:** `connector/src/hermes_mobile_connector/client.py`

New RPC handler `_rpc_profiles_list()`:
- Reads `~/.hermes/profiles/` directory — each subdirectory is a profile
- For each profile, reads `SOUL.md` first paragraph as description
- Reads `config.yaml` → `profile.default` for active profile
- Returns: `{"activeProfile": {"name": "ignyte", "description": "..."}, "profiles": [{"name": "ignyte", "description": "...", "skillCount": 101}, ...]}`

---

## Section 2: Session History Polish

### iOS Only (no relay/connector changes)

**Improvements to existing sidebar (`SessionListStore` + sidebar views):**

1. **Filter chips** above session list: All | Pinned | Archived
   - Archived hidden by default, shown only when Archived filter active
   - Pinned always shown at top within any filter

2. **Date section headers** in session list:
   - "Today", "Yesterday", "This Week", "Older"
   - Group by `lastActivity` date

3. **Preview text subtitles:**
   - Show `previewText` (already in `SessionSummary` model) as subtitle under each row

4. **Swipe actions:**
   - Leading: pin toggle
   - Trailing: archive, delete (destructive with confirmation)

5. **Empty states:**
   - No sessions: "No sessions yet" + "Start Chatting" button
   - No search results: "No results for '[query]'"

6. **Search bar** inline in sidebar (not separate screen)

---

## Section 3: Skills Browser

### iOS

**New files:**
- `HermesMobile/Features/Skills/SkillsBrowserView.swift` — full NavigationStack screen
- `HermesMobile/Stores/SkillsStore.swift` — `@Observable` store

**SkillsBrowserView:**
- `.searchable` modifier for filtering
- List grouped by category (if available), with section headers
- Each row: skill name, short description
- Tap → `SkillDetailView` with full description, when-to-use guidance, parameters
- Pull-to-refresh

**SkillsStore:**
- Model: `HermesSkill { name, description, category, path }`
- Calls `GET /v1/skills` via `RelayAPIClient`
- Local search/filter on fetched list
- 120-second cache (skills change infrequently)

**Sidebar entry:**
- "Skills" row with `wrench.and.screwdriver` icon
- On iPhone (no sidebar): entry point from Settings or a top-level NavigationTab

### Relay

```python
@app.get("/v1/skills")
async def skill_catalog(auth: AuthContext = Depends(get_auth_context)) -> dict:
    try:
        result = await send_connector_rpc(
            auth.user.id, method="skills.list", timeout_seconds=10.0,
        )
        return success(result)
    except HTTPException:
        return success({"skills": []})
    except Exception:
        return success({"skills": []})
```

### Connector

New RPC handler `_rpc_skills_list()`:
- Reads `~/.hermes/skills/` directory
- Parses SKILL.md frontmatter (name, description) from each skill
- Returns: `{"skills": [{"name": "brainstorming", "description": "...", "category": "...", "path": "..."}, ...]}`

---

## Section 4: Cron Manager

### iOS

**New files:**
- `HermesMobile/Features/Cron/CronManagerView.swift` — full NavigationStack screen
- `HermesMobile/Features/Cron/CronJobDetailView.swift` — detail/edit view
- `HermesMobile/Features/Cron/CreateCronJobSheet.swift` — creation form
- `HermesMobile/Stores/CronStore.swift` — `@Observable` store

**CronManagerView:**
- List of scheduled jobs: name, cron expression, next run, status indicator (active/paused)
- Toggle switch to enable/disable (calls `PATCH /v1/cron/{id}`)
- Swipe to delete (calls `DELETE /v1/cron/{id}`)
- "+" button opens `CreateCronJobSheet`
- Pull-to-refresh

**CronJobDetailView:**
- Full cron expression, human-readable schedule description
- Last run time + result
- Associated prompt
- Edit button (modify schedule or prompt)

**CreateCronJobSheet:**
- Fields: name, cron expression (with helper presets: hourly, daily, weekly), prompt
- Submit calls `POST /v1/cron`

**CronStore:**
- Model: `CronJob { id, name, schedule, prompt, enabled, lastRun, nextRun, lastResult }`
- CRUD: `fetchJobs()`, `createJob()`, `updateJob()`, `deleteJob()`, `toggleJob()`
- Calls `GET/POST/PATCH/DELETE /v1/cron`

**Sidebar entry:**
- "Cron Jobs" row with `clock.badge` icon

### Relay

```python
@app.get("/v1/cron")
async def cron_list(auth: AuthContext = Depends(get_auth_context)) -> dict:
    try:
        result = await send_connector_rpc(auth.user.id, method="cron.list", timeout_seconds=10.0)
        return success(result)
    except HTTPException:
        return success({"jobs": []})
    except Exception:
        return success({"jobs": []})

@app.post("/v1/cron")
async def cron_create(body: CronCreateRequest, auth: AuthContext = Depends(get_auth_context)) -> dict:
    try:
        result = await send_connector_rpc(
            auth.user.id, method="cron.create", params=body.dict(), timeout_seconds=10.0,
        )
        return success(result)
    except HTTPException as exc:
        raise exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

@app.patch("/v1/cron/{job_id}")
async def cron_update(job_id: str, body: CronUpdateRequest, auth: AuthContext = Depends(get_auth_context)) -> dict:
    try:
        result = await send_connector_rpc(
            auth.user.id, method="cron.update", params={"id": job_id, **body.dict()}, timeout_seconds=10.0,
        )
        return success(result)
    except HTTPException as exc:
        raise exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

@app.delete("/v1/cron/{job_id}")
async def cron_delete(job_id: str, auth: AuthContext = Depends(get_auth_context)) -> dict:
    try:
        result = await send_connector_rpc(
            auth.user.id, method="cron.delete", params={"id": job_id}, timeout_seconds=10.0,
        )
        return success(result)
    except HTTPException as exc:
        raise exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
```

**New Pydantic schemas in `relay/app/schemas.py`:**
- `CronCreateRequest { name: str, schedule: str, prompt: str }`
- `CronUpdateRequest { name: str | None, schedule: str | None, prompt: str | None, enabled: bool | None }`

### Connector

New RPC handlers:
- `_rpc_cron_list()` — queries Hermes scheduled jobs (via CLI `hermes cron list` or Hermes API)
- `_rpc_cron_create()` — creates job via `hermes cron add` or API
- `_rpc_cron_update()` — toggles/modifies via `hermes cron update` or API
- `_rpc_cron_delete()` — removes via `hermes cron remove` or API

**Note:** Implementation depends on Hermes's cron API/CLI capabilities. If Hermes only supports CLI, the connector shells out. If Hermes exposes an HTTP API for cron, the connector calls that instead.

---

## Section 5: Memories Endpoint (Relay-Only)

### Relay

```python
@app.get("/v1/memories")
async def memory_list(auth: AuthContext = Depends(get_auth_context)) -> dict:
    try:
        result = await send_connector_rpc(
            auth.user.id, method="memories.list", timeout_seconds=10.0,
        )
        return success(result)
    except HTTPException:
        return success({"memories": []})
    except Exception:
        return success({"memories": []})
```

### Connector

`_rpc_memories_list()` — reads `~/.hermes/memories/MEMORY.md` index, parses memory entries, returns list of names and one-line descriptions.

---

## Section 6: Tools Endpoint (Relay-Only)

### Relay

```python
@app.get("/v1/tools")
async def tool_list(auth: AuthContext = Depends(get_auth_context)) -> dict:
    try:
        result = await send_connector_rpc(
            auth.user.id, method="tools.list", timeout_seconds=10.0,
        )
        return success(result)
    except HTTPException:
        return success({"tools": []})
    except Exception:
        return success({"tools": []})
```

### Connector

`_rpc_tools_list()` — queries available MCP tools from Hermes runtime or config, returns list of tool names and descriptions.

---

## Implementation Order

1. **Relay endpoints first** — all 6 endpoints are independent, can be built in parallel
2. **Connector RPC handlers** — profiles, skills, cron (list/create/update/delete), memories, tools
3. **Profile Selector** — iOS sheet + store + toolbar chip + chat integration
4. **Session History Polish** — sidebar filter chips, date headers, swipe actions, empty states
5. **Skills Browser** — new sidebar screen + store
6. **Cron Manager** — new sidebar screen + store + CRUD

## Key Patterns to Follow

- **Relay:** Exact `/v1/models` passthrough pattern for every new endpoint
- **Connector:** Static helper methods, plain dict returns, if/elif RPC dispatch
- **iOS:** `@Observable` stores, protocol-first services, `RelayAPIClient` for networking
- **Profile switching:** Same chat-message dispatch pattern as model switching (`/profile <name>`)
- **Graceful degradation:** Every relay endpoint returns empty defaults on failure, never 500s to the client
