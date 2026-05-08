# PowerSync Self-Hosted Setup

PowerSync enables offline-first data sync between Supabase and mobile/web clients.

## Quick Start

### 1. Setup Environment
```bash
cd powersync
cp .env.example .env
# Edit .env and set PS_API_TOKEN (generate with: openssl rand -hex 32)
```

### 2. Generate JWT Signing Key

PowerSync verifies Supabase JWTs using an ES256 key pair. The private key must exist at
`supabase/signing_key.json` before starting services — it is gitignored and never committed.

```bash
# From the repo root 
printf '[]\n' > supabase/signing_key.json
npx supabase gen signing-key --algorithm ES256 --append
```

### 3. Start Services
```bash
# Start Supabase (if not already running)
npx supabase start

# Start PowerSync
docker compose up -d
```

### 4. Verify Connection
```bash
# Check replication is active
docker exec supabase_db_construculator-backend psql -U postgres -c \
  "SELECT slot_name, active FROM pg_replication_slots WHERE slot_name LIKE 'powersync%';"

# Should show: active = t

# Test data sync
docker exec supabase_db_construculator-backend psql -U postgres -d postgres -c \
  "INSERT INTO professional_roles (name) VALUES ('Test Role') RETURNING *;"

# Check PowerSync processed it
docker logs powersync --tail 10
# Should see: "Flushed ... updates" with 0s replication lag
```

## Environment Variables

All variables are required in `.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `PS_API_TOKEN`| API authentication token | Generate: `openssl rand -hex 32` |
| `PS_PORT` | PowerSync service port | `8081` |
| `PS_POSTGRES_URI` | PostgreSQL connection string | `postgresql://postgres:postgres@supabase_db_construculator-backend:5432/postgres` |
| `PS_JWKS_URI`  | Supabase Auth JWKS endpoint | `http://supabase_kong_construculator-backend:8000/auth/v1/.well-known/jwks.json` |

### Local Development

Use the values from `.env.example` as-is (just update `PS_API_TOKEN`).

### Production

- `PS_POSTGRES_URI`: Get from Supabase Dashboard → Settings → Database
  - Format: `postgresql://postgres.[ref]:[password]@aws-0-[region].pooler.supabase.com:5432/postgres`
- `PS_JWKS_URI`: `https://[project-ref].supabase.co/auth/v1/.well-known/jwks.json`
- `PS_PORT`: Choose available port (default: `8081`)

## Configuration Files

| File | Purpose |
|------|---------|
| `.env` | Environment variables |
| `compose.yaml` | Docker services (PowerSync + MongoDB) |
| `service.yaml` | PowerSync configuration |
| `sync-config.yaml` | Sync rules defining which tables to replicate |

## Database Setup

Replication is **automatically configured** via migration:
```
supabase/migrations/20260506000000_powersync_replication_setup.sql
```

Creates publication for `professional_roles` table. PowerSync auto-creates replication slots.

**To add more tables:** Supabase migrations are append-only — do **not** edit the existing
migration. Create a new migration (`npx supabase migration new add_<table>_to_powersync`) and
add the table(s) to the publication with `ALTER PUBLICATION`:

```sql
ALTER PUBLICATION powersync ADD TABLE public.your_new_table;
```

## Sync Rules

Edit `sync-config.yaml` to control what data syncs to clients:

```yaml
streams:
  global:
    auto_subscribe: true
    queries:
      - SELECT * FROM professional_roles
```

Restart PowerSync after changes: `docker compose restart powersync`

## Testing Sync Streams (without a frontend)

You can verify sync rules and JWT-scoped data without building a client. Use the hosted
[PowerSync Diagnostics App](https://diagnostics-app.powersync.com).

### 1. Get a JWT from local Supabase

Sign in against your local Supabase Auth to get an access token (replace credentials):

```bash
# Load Supabase anon key from your Supabase env
SUPABASE_URL="http://localhost:54321"
SUPABASE_ANON_KEY="<your local anon key from `npx supabase status`>"

curl -X POST "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"yourpassword"}' \
  | jq -r .access_token
```

The returned JWT carries the `app_metadata.internal_user_id` claim injected by the
`custom_access_token_hook` — that's what the sync rules filter on.

### 2. Connect the Diagnostics App

Open https://diagnostics-app.powersync.com and provide:

- **Endpoint**: `http://localhost:${PS_PORT}` (read `PS_PORT` from your `.env`, default `8081`)
- **Token**: the JWT from step 1

> Browsers may block HTTPS → `http://localhost`. If so, allow insecure content for the
> diagnostics origin, or use Firefox.

You'll see streams resolve, bucket contents, row counts, and any sync rule errors live.

### 3. (Optional) Hit the PowerSync API directly

Some admin endpoints require the service API token (not a user JWT). Read `PS_API_TOKEN`
from your `.env`:

```bash
# Load values from .env
source .env

# Health check
curl "http://localhost:${PS_PORT}/api/health"

# Admin endpoints use the API token
curl -H "Authorization: Bearer ${PS_API_TOKEN}" \
  "http://localhost:${PS_PORT}/probes/liveness"
```

## Troubleshooting

**PowerSync won't start:**
```bash
docker compose logs powersync
# Common issues:
# - PS_API_TOKEN not set in .env
# - Supabase not running (npx supabase status)
# - Docker network missing
```

**No data syncing:**
```bash
# 1. Check replication slot is active
docker exec supabase_db_construculator-backend psql -U postgres -c \
  "SELECT slot_name, active FROM pg_replication_slots WHERE slot_name LIKE 'powersync%';"

# 2. Verify table is in publication
docker exec supabase_db_construculator-backend psql -U postgres -c \
  "SELECT tablename FROM pg_publication_tables WHERE pubname = 'powersync';"

# 3. Check table is in sync rules (sync-config.yaml)

# 4. View PowerSync logs
docker logs powersync --tail 50
```

**Reset everything:**
```bash
docker compose down -v  # Remove containers and volumes
npx supabase db reset   # Reset database
docker compose up -d    # Start fresh
```

## Resources

- [PowerSync Docs](https://docs.powersync.com/)
- [Supabase Integration Guide](https://docs.powersync.com/integration-guides/supabase)
- [Sync Streams Reference](https://docs.powersync.com/usage/sync-streams)
