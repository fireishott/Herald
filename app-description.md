# Hermes Mobile Product Description

## Summary

Hermes Mobile is a native iPhone companion for a user-owned Hermes host. It is not a generic agent browser and it is not a cloud-only chatbot. The phone stays focused on native UX, while the user’s Hermes machine remains the runtime that holds memory, tools, and provider configuration.

## Current Product Story

### Connector-first setup

The user sets up Hermes Mobile from the machine running Hermes:

1. install and configure the connector
2. pair the phone with a short code or QR
3. keep the connector alive as a background service

The app then becomes the personal companion interface for that host.

### Chat

Chat is the primary surface.

- messages are persisted on the relay
- Hermes work is executed on the user’s host connector
- replies can stream with compact thinking and tool activity
- coding turns can render inline diffs when the connector can detect workspace edits

### Talk mode

Talk mode uses OpenAI Realtime with WebRTC from the app, but the sensitive Realtime configuration lives on the connector host.

- the phone receives only short-lived session bootstrap data
- the host owns the OpenAI key and model preference
- Hermes memory and sensor context are prefetched into a lightweight voice context
- deeper tool or memory work can delegate back to Hermes

### Native companion features

- pairing and secure session bootstrap
- host status and lifecycle controls
- permissions for location, health, notifications, and microphone
- sensor context delivery from phone to host
- inbox surfaces for relay-driven actions

## Current Constraints

- Talk mode is foreground-only.
- True barge-in interruption is not fully finished yet.
- Background HealthKit and Always-on location still require real-device validation.
- Capture/media workflows are not complete.

## Positioning

Hermes Mobile should keep feeling like a native Hermes companion, even as the host-side architecture gradually becomes more runtime-agnostic behind the connector boundary.
