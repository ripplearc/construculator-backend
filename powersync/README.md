# PowerSync Configuration

PowerSync enables offline-first data sync between Supabase and mobile/web clients.

## Local Development

### Prerequisites
- Docker Desktop running
- Supabase running: `npx supabase start`

### Start PowerSync

```bash
docker compose --file ./powersync/compose.yaml up -d
```

PowerSync dashboard: http://localhost:8080
API token: See `powersync/.env`

### Verify Setup

```bash
# Check JWKS endpoint
curl http://localhost:54321/auth/v1/.well-known/jwks.json

# Check PowerSync health
curl http://localhost:8080/api/health

# View logs
docker compose --file ./powersync/compose.yaml logs -f
```

### Stop PowerSync

```bash
docker compose --file ./powersync/compose.yaml down
```

## Configuration Files

| File | Purpose |
|------|---------|
| `compose.yaml` | Docker container configuration |
| `powersync.yaml` | PowerSync service settings |
| `sync-config.yaml` | Sync streams (TODO: CA-647) |
| `.env` | Environment variables |

## Database Replication Setup

Replication is **automatically configured** via Supabase migration:
```
supabase/migrations/20260506000000_powersync_replication_setup.sql
```

This creates:
- Replication slot: `powersync_slot`
- Publication: `powersync_publication`

No manual setup needed - runs on `supabase start` or `supabase db reset`.

## Sync Streams Configuration

**Status:** Not yet configured
**Task:** https://ripplearc.youtrack.cloud/issue/CA-647

See `docs/PowerSync.md` Section 5 for implementation guide.

Required streams:
- `my_user` (auto-subscribe)
- `user_projects` (auto-subscribe)
- `user_memberships` (auto-subscribe)
- `project_cost_data` (on-demand)

## Troubleshooting

### PowerSync won't start
```bash
# Check Supabase is running
npx supabase status

# Check Docker network exists
docker network ls | grep supabase

# View PowerSync logs
docker compose --file ./powersync/compose.yaml logs
```

### No data syncing
1. Check sync streams are configured in `sync-config.yaml`
2. Verify replication slot exists:
   ```sql
   SELECT * FROM pg_replication_slots WHERE slot_name = 'powersync_slot';
   ```
3. Check PowerSync logs for authorization errors

### JWKS endpoint fails
```bash
# Verify endpoint is accessible
curl http://localhost:54321/auth/v1/.well-known/jwks.json

# Should return JSON with non-empty "keys" array
# If empty, signing keys weren't generated (check supabase/signing_key.json)
```

## Resources

- [PowerSync Documentation](https://docs.powersync.com/)
- [PowerSync.md Wiki](../docs/PowerSync.md) - Complete integration guide
- [Supabase Integration](https://docs.powersync.com/integration-guides/supabase)
- [Sync Streams Reference](https://docs.powersync.com/usage/sync-streams)
