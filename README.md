# HermesMobile

> **Note:** HermesMobile is an independent community project. It is not affiliated with, endorsed by, or part of [Nous Research](https://nousresearch.com/) or the official [Hermes Agent](https://github.com/NousResearch/hermes-agent) project.

HermesMobile is a self-hosted-first iOS companion for a user-owned Hermes runtime.

The stack has three parts:

- **iOS app**: chat, voice, camera, notifications, sensor capture
- **relay**: public HTTPS/WebSocket control plane for pairing, auth, jobs, SSE, talk bootstrap
- **connector**: host-side bridge that connects the relay to a local Hermes install

## Architecture

```text
iOS App ──HTTP/SSE──▶ Relay ──WebSocket──▶ Connector ──▶ Hermes Agent
                    │                          │
                    └──── pairing/auth/jobs ───┘
```

The relay is not the Hermes runtime. In connector mode, Hermes work runs on the user-owned machine where the connector is installed.

## Deployment Model

The distribution model is **self-hosted first**:

- users run their own relay
- users run their own connector on the machine where Hermes lives
- the iOS app can point at a custom relay URL

An optional hosted relay can exist in the future, but that is not the canonical setup shape for this repository.

## Quickstart

1. Read [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for the full environment-variable and override matrix.
2. Start the relay using the instructions in [relay/README.md](relay/README.md).
3. Install the connector using [connector/README.md](connector/README.md).
4. Run `hermes-mobile setup` on the Hermes host.
5. Run `hermes-mobile pair-phone` and pair the iPhone app with the short-lived code.

## Repo Guide

- [relay/README.md](relay/README.md): relay dev and deployment
- [connector/README.md](connector/README.md): connector install, setup, pairing, service management
- [docs/CONFIGURATION.md](docs/CONFIGURATION.md): environment variables, app config, private override strategy
- [currentlybuilt.md](currentlybuilt.md): internal implementation snapshot, not end-user onboarding

## Notes for Maintainers

- Tracked config files are now public-safe defaults.
- Personal deployment values such as Fly app names, hosted relay URLs, signing/team settings, and setup secrets should live in local/private overrides rather than tracked source.
