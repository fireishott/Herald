# Hermes Mobile: Current Build State

## What Exists Today

Hermes Mobile is now a real Hermes companion stack, not a mock shell.

The current system has three working pieces:

- The iOS app in [`/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile`](/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile)
- The public relay in [`/Users/dylan-mac-mini/Documents/HermesMobile/relay`](/Users/dylan-mac-mini/Documents/HermesMobile/relay)
- The host-side connector in [`/Users/dylan-mac-mini/Documents/HermesMobile/connector`](/Users/dylan-mac-mini/Documents/HermesMobile/connector)

## Core Product Shape

### Connector-first pairing

- The Hermes host is set up first with `hermes-mobile setup`
- The connector can generate a short phone pairing code with `hermes-mobile pair-phone`
- The phone pairs with an 8-character code such as `ABCD-EFGH` or by scanning the QR
- Release onboarding no longer asks for a relay URL or host enrollment from the phone

### Chat

- The app talks to the cloud relay, not directly to Hermes
- The relay persists conversation state and message jobs
- The connector claims jobs and executes Hermes locally on the user’s machine
- Chat supports:
  - synchronous replies when the host is online
  - queued pending state when the host is offline or slow
  - SSE streaming progress
  - tool activity status
  - inline code diff rendering for coding turns when the connector can detect git-visible file changes
  - durable message delivery states on user messages

### Talk mode

- The app has a real WebRTC-based talk stack for OpenAI Realtime
- Realtime credentials and model selection live on the connector host, not in the app
- The relay brokers talk readiness and short-lived session bootstrap
- Final transcript turns are persisted back to the relay
- Hermes memory and local sensor summaries are prefetched into a cached voice context snapshot
- A relay-hosted `hermes_delegate` tool can hand deeper requests back to the Hermes host

### Host tools and sensor context

- The connector can register a native MCP server in `~/.hermes/config.yaml`
- The `hermes_mobile` MCP server exposes phone-derived context such as location and health freshness
- The phone keeps a local outbox for sensor data and only clears it after relay/connector ACK
- Delivered sensor data is stored on the connector host, not on the relay

### Background host uptime

- The connector supports managed background execution
- macOS uses a per-user `launchd` LaunchAgent
- Windows gateway support is WSL2-only and uses a Windows Scheduled Task to start the WSL-hosted connector

## iOS App Shape

The app is now centered around a single primary chat surface rather than the older multi-tab shell.

Key surfaces:

- [`/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Onboarding/ConnectHermesScreen.swift`](/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Onboarding/ConnectHermesScreen.swift)
- [`/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Chat/ChatScreen.swift`](/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Chat/ChatScreen.swift)
- [`/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Talk/TalkModeScreen.swift`](/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Talk/TalkModeScreen.swift)
- [`/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Inbox/InboxScreen.swift`](/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Inbox/InboxScreen.swift)
- [`/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Settings/SettingsScreen.swift`](/Users/dylan-mac-mini/Documents/HermesMobile/HermesMobile/Features/Settings/SettingsScreen.swift)

Notable UI features already present:

- compact live thinking and tool-status UI
- expandable inline diffs for code-editing turns
- markdown rendering in assistant replies
- talk transcript state with latency markers
- host status and connector management entry points
- permissions and privacy controls

## Connector / Relay Architecture

### Relay

- public always-on control plane
- pairing and session bootstrap
- durable message job queue
- host presence tracking
- connector WebSocket control channel
- talk readiness and voice session bootstrap
- voice turn persistence

### Connector

- owns Hermes execution
- owns Realtime API configuration
- owns local MCP registration
- owns local sensor SQLite store
- owns background service installation
- uses Hermes through supported surfaces instead of patching Hermes source

## What Is Still Unfinished

### Product gaps

- Talk mode is not truly barge-in complete yet. The app reacts to speech-start events but does not yet send an explicit Realtime interruption/cancel command back to cut off assistant audio mid-turn.
- Inline diffs depend on git-visible changes in the Hermes workdir. They are a connector-side inference layer, not a Hermes-native structured diff stream.
- Camera/capture remains a stub.
- Terms of Service and Privacy Policy links in Settings are still placeholders.

### Integration gaps

- The app still uses `MockSyncCoordinator` and `MockMediaService` in the main container, so sync/media plumbing is not fully productionized yet.
- Background health and Always-authorized location still need real-device validation. Simulator coverage is not enough for those capabilities.
- Talk mode is foreground-only.

### Test gaps

- Connector and relay automated suites are in good shape.
- Focused iOS state/store tests pass.
- The full UI test suite is currently stale against the new single-surface app structure and fails until those expectations are updated.

## Verification Snapshot

Latest review pass:

- connector tests: passing
- relay tests: passing
- focused iOS state tests: passing
- full UI test suite: failing because onboarding/navigation expectations still target the old tab-based shell

## Near-term Next Work

1. Finish true talk barging by sending explicit Realtime interruption/cancel events.
2. Update stale UI tests to the current single-surface navigation model.
3. Replace placeholder About links with real URLs.
4. Decide whether inline diffs stay connector-side or move toward a Hermes-native structured diff event path later.
