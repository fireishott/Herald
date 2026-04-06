# Fly.io deployment

This relay can be deployed to Fly.io from the `relay` directory.

## What this Fly deployment does

- Deploys the FastAPI relay as a public HTTPS service.
- Uses Fly Managed Postgres for persistence through `DATABASE_URL`.
- Works with user-owned connectors over WebSocket.

The relay does not need a local Hermes install when running in connector mode. Hermes stays on the user-owned host.

## Recommended first deploy

1. Install `flyctl`.
2. Log in with `flyctl auth login`.
3. From this `relay` directory, create or confirm the Fly app name.
4. Create a Managed Postgres cluster.
5. Attach the app to Postgres so Fly sets `DATABASE_URL`.
6. Set `INTERNAL_API_KEY` as a Fly secret.
7. Deploy with `fly deploy`.

## Example commands

```bash
cd relay

# Authenticate first.
flyctl auth login

# Create an app name that matches your PUBLIC_BASE_URL.
flyctl apps create hermes-mobile-relay

# Create Managed Postgres in the same primary region.
flyctl mpg create --name hermes-mobile-relay-db --region iad --plan basic

# List clusters to get the cluster ID, then attach it to the app.
flyctl mpg list
flyctl mpg attach <cluster-id> -a hermes-mobile-relay

# Set the relay's internal key as a secret.
flyctl secrets set INTERNAL_API_KEY=replace-this-with-a-real-secret -a hermes-mobile-relay
flyctl secrets set CONNECTOR_SETUP_SECRET=replace-this-with-a-bootstrap-secret -a hermes-mobile-relay

# Deploy the relay from this directory.
flyctl deploy
```

## After deploy

- `PUBLIC_BASE_URL` in `fly.toml` should match the final Fly app URL.
- The iOS app should point at the deployed relay URL through its custom relay setting or hosted-relay build config.
- If you want always-warm Machines instead of cold starts, change `min_machines_running` from `0` to `1`.
