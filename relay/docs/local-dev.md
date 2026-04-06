# Local Development

Recommended local flow:

1. Start Postgres with Docker Compose from the `relay/` directory.
2. Run the relay with `PUBLIC_BASE_URL=http://127.0.0.1:8000/v1`.
3. Point the iOS app at `http://127.0.0.1:8000/v1` using the custom relay configuration in onboarding/settings.
4. Start the connector with `HERMES_MOBILE_RELAY_URL=http://127.0.0.1:8000/v1`.

Important env vars:

- `DATABASE_URL`
- `PUBLIC_BASE_URL`
- `INTERNAL_API_KEY`
- `HERMES_ADAPTER`
- `CONNECTOR_SETUP_SECRET` (optional)

For realistic end-to-end local development, prefer `HERMES_ADAPTER=connector`.
