# Configuration and Deployment

This repo is designed to be public-safe and self-hosted-first.

Tracked configuration files should contain generic defaults. Real deployment values should be injected through local env, local config files, or deployment secrets.

## Relay Environment Variables

Core:

- `PUBLIC_BASE_URL`
- `DATABASE_URL`
- `INTERNAL_API_KEY`
- `RELAY_ENVIRONMENT`

Connector mode:

- `HERMES_ADAPTER=connector`
- `CONNECTOR_SYNC_WAIT_SECONDS`
- `CONNECTOR_JOB_LEASE_SECONDS`
- `CONNECTOR_HEARTBEAT_TIMEOUT_SECONDS`
- `CONNECTOR_IDLE_POLL_INTERVAL_SECONDS`
- `CONNECTOR_SETUP_SECRET` (optional)

Pairing/rate limits:

- `PHONE_PAIRING_CODE_TTL_SECONDS`
- `PHONE_PAIRING_MAX_ATTEMPTS_PER_CODE`
- `PHONE_PAIRING_MAX_ATTEMPTS_PER_IP`
- `PHONE_PAIRING_RATE_LIMIT_WINDOW_SECONDS`
- `HOST_ENROLLMENT_CODE_TTL_SECONDS`

## Connector Environment Variables

Required for real use:

- `HERMES_MOBILE_RELAY_URL`
- `HERMES_COMMAND`

Common runtime context:

- `HERMES_WORKDIR`
- `HERMES_PROVIDER`
- `HERMES_MODEL`
- `HERMES_TOOLSETS`
- `HERMES_SOURCE`
- `HERMES_HISTORY_LIMIT`
- `HERMES_HOME`

Optional connector-local state:

- `HERMES_MOBILE_CONNECTOR_HOME`

Optional bootstrap protection:

- `CONNECTOR_SETUP_SECRET`

If the relay is configured with `CONNECTOR_SETUP_SECRET`, the connector must provide the same value before `hermes-mobile setup`.

## iOS App Build/Runtime Config

The app reads these values from `Info.plist`:

- `APP_HOSTED_RELAY_ENABLED`
- `APP_HOSTED_RELAY_URL`
- `APP_SUPPORT_URL`
- `APP_TERMS_URL`
- `APP_PRIVACY_URL`

Public-safe tracked defaults should leave hosted relay disabled.

The app supports custom relay URLs at runtime through user settings and onboarding. A hosted relay is optional and feature-flagged by the plist values above.

## Private Override Strategy

For personal or private deployments, keep these values out of tracked source:

- hosted relay URL
- Fly app name
- `CONNECTOR_SETUP_SECRET`
- Apple signing team / bundle IDs if they differ from public-safe defaults

Recommended approach:

- relay: local `.env`, deployment secrets, or untracked `fly.toml` override
- connector: shell env / service env
- iOS app: local plist/build-setting override for hosted relay values

## Personal Setup Checklist

If you are already running a private deployment, verify:

1. Your relay has the correct `PUBLIC_BASE_URL`.
2. Your connector service environment includes `HERMES_MOBILE_RELAY_URL`.
3. If `CONNECTOR_SETUP_SECRET` is enabled on the relay, it is also present in the connector environment before running `hermes-mobile setup`.
4. If you want the app to expose your hosted relay as an option, set `APP_HOSTED_RELAY_ENABLED=true` and `APP_HOSTED_RELAY_URL` locally in your app config.
