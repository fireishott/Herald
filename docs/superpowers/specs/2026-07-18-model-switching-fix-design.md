# Model Switching Fix, Models List Bugs, Wallpaper Default Cleanup

## Overview

Three fixes surfaced from real device testing:

1. **Model switching is fundamentally broken.** `/model <name>` sent as a chat message never reaches Hermes's command dispatcher — both connector transports (CLI `-q` single-shot and the API server's `/v1/chat/completions`) bypass slash-command resolution entirely and hand the text to the LLM as literal chat. There is no existing RPC or endpoint that switches the model. Root-caused via full read of the connector code and the actual hermes-agent source (`~/.hermes/hermes-agent`).

2. **`models.list` has real bugs** confirmed against the user's actual `~/.hermes/config.yaml`:
   - Provider `models:` declared as a YAML **list** (not dict) is silently dropped — the user's own `llamacpp-mtp` provider and its explicit `context_length: 65536` never surface.
   - Models resolved dynamically (the user's actual active model, `anthropic/claude-opus-4.6` via `model.provider: auto` → OpenRouter) are never enumerated — the picker only scans hand-declared `providers`/`custom_providers` in config.yaml.
   - Context-window resolution for local/custom models omits `base_url`/`provider`, so it can't probe local servers and falls back to a wrong default (128K hardcoded) instead of hermes-agent's real fallback (256K) or the correct config value (65536).
   - Cache key for context-window lookups uses only the top-level `model.base_url`, never a provider-specific one, so cache hits rarely occur for non-default providers.

3. **Wallpaper default is a placeholder that shouldn't ship.** No clean "Hermes logo silhouette" asset exists in the NousResearch/hermes-agent repo — the closest thing is a nearly-invisible dev-only easter egg image, and the repo's actual brand mark ("nous-girl") is Nous Research's identity, not ours to borrow into a shipping app.

**Scope decisions:**
- Model switching: global-default only (same scope as `/model <name> --global` in the TUI). Session-scoped override is out of reach without a hermes-agent change, which is out of scope.
- Models list: full fix, including reading the dynamic model catalog cache (`~/.hermes/models_dev_cache.json`), scoped to the user's configured provider only (not all 100+ providers in the cache — that would flood the picker with irrelevant duplicates).
- Wallpaper: drop the placeholder/logo concept entirely, replace `.default` with a theme-tinted solid/subtle-gradient consistent with the other presets.

---

## Section 1: Real Model Switching

### Connector

**New RPC handler:** `_rpc_model_set()` in `client.py`, alongside the existing `_rpc_models_list()`.

- Takes `{name: str, provider: str}` params
- Reads `~/.hermes/config.yaml`, sets `model.default = name`, `model.provider = provider`
- If the provider has a `base_url` in its config entry, also sets `model.base_url` to match
- Writes the config back to disk (preserving YAML formatting/comments as much as the yaml library allows — use `ruamel.yaml` round-trip mode if available, matching the existing fallback-import pattern already used elsewhere in `client.py`, else plain `yaml.safe_dump`)
- Returns the updated `_read_active_model()` result so the caller gets fresh confirmation data, not a stale/optimistic guess

```python
async def _rpc_model_set(self, params: dict) -> dict:
    hermes_home = self._resolve_hermes_home()
    config_path = hermes_home / "config.yaml"
    name = params.get("name")
    provider = params.get("provider")
    if not name or not provider:
        raise RuntimeError("model.set requires 'name' and 'provider'")

    # Read-modify-write config.yaml, preserving structure where possible
    ...

    return {"activeModel": self._read_active_model(hermes_home)}
```

**Dispatch entry:** `elif method == "model.set": result = await self._rpc_model_set(params)`

### Relay

**New endpoint:** `POST /v1/model`

```python
@app.post("/v1/model")
async def set_active_model(
    body: ModelSetRequest,
    auth: AuthContext = Depends(get_auth_context),
) -> dict:
    try:
        result = await send_connector_rpc(
            auth.user.id,
            method="model.set",
            params=body.model_dump(),
            timeout_seconds=10.0,
        )
        return success(result)
    except HTTPException as exc:
        raise exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
```

New schema: `ModelSetRequest { name: str, provider: str }`

This follows the write-endpoint pattern already established for cron create/update/delete (propagate errors, don't swallow them — the caller needs to know if the switch failed).

### iOS

**`ModelStore`:**
- New method `switchModel(to name: String, provider: String) async throws` — calls `POST /v1/model`, and on success, updates `activeModel`/`activeModelName` directly from the response (no more optimistic guessing, no more regex-parsing chat text)
- Remove the reliance on chat-message dispatch for switching

**`ChatStore`:**
- Remove `detectModelSwitch(in:)` — it parsed `"Model switched to..."` text that the LLM never actually produces through this path, since the real handler never ran
- `ModelSelectorSheet`'s selection callback calls `modelStore.switchModel(to:provider:)` directly instead of `chatStore.sendMessage("/model ...")`

**`ModelSelectorSheet`:**
- On successful switch, dismiss and show a brief confirmation (e.g., a toast or inline checkmark) since there's no chat-message round-trip to confirm it anymore
- On failure, show an inline error and keep the sheet open

---

## Section 2: Models List Bugs

All changes in `connector/src/hermes_mobile_connector/client.py`.

### Bug A: `models:` as a list

`_read_available_models._collect()` and `_context_length_from_config()` both currently do:
```python
if not isinstance(provider_models, dict):
    return
```

Fix: handle both shapes.
```python
if isinstance(provider_models, dict):
    for model_name, model_config in provider_models.items():
        ...
elif isinstance(provider_models, list):
    # List form: models are plain name strings, no per-model config.
    # Provider-level context_length (if present) applies to all of them.
    provider_context_length = provider.get("context_length")
    for model_name in provider_models:
        models.append({
            "name": str(model_name),
            "provider": str(provider_key),
            "providerName": str(provider_name),
            "contextWindow": provider_context_length,
            "isProviderDefault": model_name == default_model,
        })
```

### Bug B: Dynamic catalog models not enumerated

New helper `_read_dynamic_catalog_models(hermes_home, config)`:
- Determine the effective provider for the *active* model: read `model.provider` and `model.base_url` from config
- If `model.provider` is a real provider id (not `"auto"`/empty), look it up directly in `~/.hermes/models_dev_cache.json`
- If `model.provider` is `"auto"` (dynamic resolution), match by `model.base_url` against each cache provider's known base URL pattern (OpenRouter's is `openrouter.ai` — match substring against the `base_url` config value, since the cache doesn't store gateway base URLs directly; fall back gracefully if no match is found)
- Return that single provider's model list in the same shape as `_read_available_models()`, scoped to just that provider (not the full multi-hundred-provider cache) to avoid flooding the picker with irrelevant duplicates
- Merge (not duplicate) with the config.yaml-declared providers/models in `_rpc_models_list()`

```python
def _read_dynamic_catalog_models(hermes_home: Path, config: dict) -> list[dict]:
    cache_path = hermes_home / "models_dev_cache.json"
    if not cache_path.is_file():
        return []
    try:
        with open(cache_path, "r", encoding="utf-8") as f:
            catalog = json.load(f)
    except Exception:
        return []

    model_cfg = config.get("model", {})
    provider_id = model_cfg.get("provider")
    base_url = model_cfg.get("base_url", "")

    matched_provider_key = None
    if provider_id and provider_id != "auto" and provider_id in catalog:
        matched_provider_key = provider_id
    elif base_url:
        for key in catalog:
            if key in base_url:
                matched_provider_key = key
                break

    if not matched_provider_key:
        return []

    provider_entry = catalog[matched_provider_key]
    provider_models = provider_entry.get("models", {})
    default_model = model_cfg.get("default")

    results = []
    for model_id, model_meta in provider_models.items():
        context_limit = (model_meta.get("limit") or {}).get("context")
        results.append({
            "name": model_id,
            "provider": matched_provider_key,
            "providerName": provider_entry.get("name", matched_provider_key),
            "contextWindow": context_limit,
            "isProviderDefault": model_id == default_model,
        })
    return results
```

Called from `_rpc_models_list()`:
```python
def _rpc_models_list(self) -> dict:
    hermes_home = self._resolve_hermes_home()
    config = ...  # already-parsed config, reused
    models = self._read_available_models(hermes_home)
    models.extend(_read_dynamic_catalog_models(hermes_home, config))
    ...
```

### Bug C: Context-window resolution omits base_url/provider

`_context_window_for()` currently calls:
```python
f"from agent.model_metadata import get_model_context_length; print(get_model_context_length('{model_name}'))"
```

Fix: pass through `base_url` and `provider` (already available as parameters on the calling function, just not forwarded):
```python
f"from agent.model_metadata import get_model_context_length; "
f"print(get_model_context_length({model_name!r}, base_url={base_url!r}, provider={provider!r}))"
```

Also fix the exception fallback from `128_000` to `256_000` to match hermes-agent's actual documented final fallback (`agent/model_metadata.py` step 9).

### Bug D: Cache key mismatch

`_cached_context_window()` builds `f"{model_name}@{base_url}"` using only the top-level `model.base_url`. Fix: accept the actual per-provider `base_url` as a parameter (threaded from the caller, which already has it from the provider's config entry) instead of reaching for the top-level default.

---

## Section 3: Refresh UI

**`ModelSelectorSheet.swift`:**
- Add `.refreshable { await modelStore.loadModels(forceRefresh: true) }` to the model list (pull-to-refresh, standard SwiftUI pattern already used elsewhere in the app — e.g., `SkillsBrowserView`, `CronManagerView`)
- No new store logic needed — `loadModels(forceRefresh:)` already exists from the original model selector implementation

---

## Section 4: Wallpaper Default Cleanup

**`HermesMobile/Core/Theme.swift`:**
- Remove the `hexagon.fill` SF Symbol placeholder from `ChatWallpaperBackground.defaultBackground`
- Replace with a theme-tinted subtle radial gradient (background color to a faint accent-tinted edge), consistent visual weight with `.solid` but slightly more dynamic — no borrowed logo/mascot concept
- Update the code comment that references the (abandoned) "human designer drops in a logo silhouette" plan — this is now the permanent default, not a placeholder

```swift
@ViewBuilder
private var defaultBackground: some View {
    RadialGradient(
        colors: [tint.opacity(0.06), Color(.systemBackground)],
        center: .center,
        startRadius: 0,
        endRadius: 500
    )
}
```

---

## Implementation Order

1. **Connector: model.set RPC** — enables real switching
2. **Relay: POST /v1/model** — exposes it to iOS
3. **iOS: ModelStore.switchModel + ModelSelectorSheet wiring** — consumes it, removes fake chat-dispatch
4. **Connector: models.list bug fixes (A, C, D)** — config parsing + context window
5. **Connector: dynamic catalog (B)** — surfaces OpenRouter/auto-resolved models
6. **iOS: pull-to-refresh** — small UI addition
7. **iOS: wallpaper default cleanup** — unrelated but bundled since it's small

## Key Patterns

- **Connector:** read-modify-write for config.yaml mutations (new pattern, first RPC that writes instead of just reads)
- **Relay:** propagate errors on write endpoints (matches cron create/update/delete), don't swallow
- **iOS:** no more regex-parsing chat replies for state confirmation — RPC responses are the source of truth
- **Dynamic catalog:** scoped to the single configured provider, never the full cache dump
