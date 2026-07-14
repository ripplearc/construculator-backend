# Global Search — `search_history_cleanup` Module

## Overview

Both `search_history.user_id` and `project_search_history.user_id` store `auth.uid()` with **no foreign key** to `auth.users` (cross-schema boundary). When a user is deleted from Supabase Auth, their rows in these tables are not cascade-deleted and become orphaned — they accumulate indefinitely and pollute teammate suggestion queries.

This module implements the periodic cleanup called for by [CA-597](https://ripplearc.youtrack.cloud/issue/CA-597): a `pg_cron` job that deletes rows whose `user_id` no longer exists in `auth.users`, from **both** tables, without touching rows of active users.

---

## Function

### `public.purge_orphaned_search_history()` → `void`

Deletes rows from `search_history` and `project_search_history` where `user_id` has no matching row in `auth.users`.

- **`SECURITY DEFINER`** — required to read `auth.users` (invisible to the cron role under normal privileges) and to bypass the per-user RLS `DELETE` policies on both tables (each restricts deletes to `user_id = auth.uid()`).
- **`SET search_path = public, auth`** — pinned, per repo convention.
- Uses `NOT EXISTS` anti-joins against `auth.users(id)` (its PK). Note the plan is a seq scan + hash anti-join — every row must be checked, so the `user_id` indexes do **not** accelerate this query. That is fine at these tables' expected size (bounded by users × distinct terms); if they ever grow large, batch the DELETE.
- **Not exposed via the API.** `EXECUTE` is revoked from `PUBLIC`, `anon`, and `authenticated`, and granted only to `postgres` (the role `pg_cron` runs as) — this REVOKE is the primary access control. As defense-in-depth against an *authenticated* call, the body also rejects any request carrying a non-empty `request.jwt.claims` JWT (which PostgREST sets for authenticated requests and `pg_cron` never does) with `42501`. This second layer matters because the CLI's `auto_expose_new_tables` grant pass can re-grant `EXECUTE` to the Data API roles on `db reset` (a repo-wide issue tracked by [CA-729](https://ripplearc.youtrack.cloud/issue/CA-729), affecting every function). Note the guard does not by itself stop an *anon* call (no JWT — indistinguishable from the cron path); that path relies on the REVOKE, as with every other `SECURITY DEFINER` function in this schema.

---

## Schedule

`pg_cron` job **`purge-orphaned-search-history`**, defined in `07_cron.sql`:

| Setting | Value |
|---|---|
| Schedule | `0 3 * * *` — daily at 03:00 UTC (low-traffic window) |
| Command | `SELECT public.purge_orphaned_search_history();` |

Registration is idempotent: the job is unscheduled (if present) before being (re)scheduled, so re-applying the schema never errors or creates duplicates.

To change cadence, edit the cron expression in `07_cron.sql` and regenerate the migration.

---

## Files

| File | Content |
|---|---|
| `03_functions.sql` | `purge_orphaned_search_history()` + `GRANT`/`REVOKE`. |
| `07_cron.sql` | `CREATE EXTENSION IF NOT EXISTS pg_cron` + idempotent `cron.schedule(...)`. |

> **Migration note:** `pg_cron` objects live in the `cron` schema, which `supabase db diff` does not track. The `07_cron.sql` statements are the authoritative source and are carried into the generated migration by hand (annotated in the migration header, per the CA-737 precedent for annotated generated migrations).

---

## Verification

**pgTAP** — `supabase/tests/functions/purge_orphaned_search_history_test.sql`:
- Seeds `auth.users` with one active user and inserts rows for both that user and an orphan `user_id` into both tables.
- Calls `purge_orphaned_search_history()` and asserts orphan rows are gone from both tables while the active user's rows survive.

Run with `supabase test db`.

**Manual (local):**
```sql
-- Confirm the job registered:
SELECT jobname, schedule, command FROM cron.job;
-- Run the purge directly:
SELECT public.purge_orphaned_search_history();
```

---

## Related Tables

- `search_history` — Global Search history (see sibling [`search_history`](../search_history/README.md) module).
- `project_search_history` — Project Search history (see sibling [`project_search_history`](../project_search_history/README.md) module).
