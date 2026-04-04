# Hermes Mobile Connector

`hermes-mobile` is the host-side process that runs next to a local Hermes install and bridges it to a public Hermes Mobile relay.

The connector is the durable host boundary for:

- Hermes execution
- host enrollment and phone pairing
- local MCP registration
- local sensor storage
- OpenAI Realtime talk configuration
- background service management

## Install

```bash
cd /Users/dylan-mac-mini/Documents/HermesMobile/connector
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
```

## Runtime configuration

The connector persists its runtime configuration after setup, but these environment variables are still the easiest way to define the initial Hermes execution context:

```bash
export HERMES_COMMAND=/absolute/path/to/hermes
export HERMES_WORKDIR=/path/to/your/hermes/project
export HERMES_PROVIDER=
export HERMES_MODEL=
export HERMES_TOOLSETS=
export HERMES_SOURCE=tool
export HERMES_HISTORY_LIMIT=20
```

Optional connector-local state directory:

```bash
export HERMES_MOBILE_CONNECTOR_HOME=~/.hermes-mobile
```

Relay target:

```bash
export HERMES_MOBILE_RELAY_URL=https://hermes-mobile-relay-dylan.fly.dev/v1
```

## Setup

Create or link the relay account from the Hermes host first:

```bash
hermes-mobile setup
```

During setup the connector can optionally:

- configure `mcp_servers.hermes_mobile` in `~/.hermes/config.yaml`
- validate that MCP entry with `hermes mcp test hermes_mobile`
- configure OpenAI Realtime talk mode with a connector-owned API key
- install or start the background connector service

If you want to skip MCP registration during setup:

```bash
hermes-mobile setup --skip-mcp
```

If Hermes chat is already open when setup finishes, the connector may report `Reload required`. Run `/reload-mcp` inside Hermes or start a fresh chat so the new `hermes_mobile` MCP server is loaded into the active session.

If you skip MCP config during setup, you can enable it later:

```bash
hermes-mobile configure-mcp
hermes-mobile validate-mcp
```

## Realtime talk configuration

Realtime talk configuration is connector-owned, not app-owned.

The connector wizard can configure this during `setup`, or you can do it later:

```bash
hermes-mobile configure-realtime
```

This stores the OpenAI API key in a connector-owned secrets file, not in relay state and not on the phone.

Useful related commands:

```bash
hermes-mobile configure-realtime --clear
hermes-mobile status
```

`status` reports whether talk is configured, the selected model preference, and the last validation result without printing secrets.

## Pair a phone

After setup, generate a short-lived phone pairing code and QR:

```bash
hermes-mobile pair-phone
```

Then open Hermes Mobile on the phone and scan the QR code or enter the displayed `ABCD-EFGH` code manually.

## Background service

You can keep the connector alive without an open terminal:

```bash
hermes-mobile service install
hermes-mobile service start
```

Management commands:

```bash
hermes-mobile service status
hermes-mobile service restart
hermes-mobile service stop
hermes-mobile service logs
hermes-mobile service uninstall
```

If you move to a new venv or Python path, rewrite the service artifacts with:

```bash
hermes-mobile service install --force
```

Platform behavior:

- macOS uses a per-user `launchd` LaunchAgent and starts after that user logs in.
- Windows gateway support is WSL2-only. The connector installs a Windows Scheduled Task that launches the WSL-hosted connector after Windows logon.
- Native Windows Hermes execution is not supported.

## Foreground debugging

```bash
hermes-mobile run
```

`run` is the foreground development/debugging path. For day-to-day uptime, prefer the managed service.

## What the connector does today

- opens one outbound authenticated WebSocket to the relay
- heartbeats while idle or during long jobs
- executes one Hermes job at a time
- preserves Hermes session continuity where possible
- exposes phone-derived context through a local MCP server
- supports chat streaming progress and final result delivery
- can attach git-visible inline diff data for coding turns
- builds a cached talk-mode voice context from Hermes memory files, memory-provider status, and sensor freshness

## Current limitations

- Talk mode bootstrap is implemented, but true barge-in interruption is not fully complete in the app yet.
- Inline diffs depend on git-visible file changes in the configured Hermes workdir.
- Background health delivery and Always-authorized background location still require a physical iPhone for full validation.

## Legacy enroll

The legacy host-enrollment path still exists for development and migration:

```bash
hermes-mobile enroll --code 'HC1:...'
```

You can inspect the stored enrollment and host config with:

```bash
hermes-mobile status
hermes-mobile service status
```
