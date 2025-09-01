# Secrets

## Environment variables

For local development on Base Sepolia, copy the provided example and fill in your own values:

```bash
cp .env.base-sepolia.example .env
```

For other networks, start from `.env.example` and update the endpoints and addresses accordingly.

## Mobile config

To mirror those values in the mobile app, copy the Base Sepolia config and customize it:

```bash
cp mobile/assets/config.base-sepolia.example.json mobile/assets/config.json
```

For other networks, start from `mobile/assets/config.example.json`.

Both `.env` and `mobile/assets/config.json` are ignored by git and should never be committed.
