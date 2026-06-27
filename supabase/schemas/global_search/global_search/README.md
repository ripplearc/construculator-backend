# Global Search — `global_search` RPC Module

## Overview

`public.global_search` is the dashboard-wide search RPC: a single call searches across **projects**, **cost estimates**, and **members**, scoped by an optional `scope` param. It is distinct from the `project_search_history` module's `get_project_search_suggestions`, which only searches projects (see that module's README for the comparison table).

This directory documents the RPC itself. The tables it reads (`projects`, `cost_estimates`, `project_members`, `users`) are documented in their own modules (`core/projects`, `cost_management/cost_estimates`, `core/users`).

## RPC

### `public.global_search(query, filter_by_tag, filter_by_date_from, filter_by_date_to, filter_by_owner, scope, projects_offset, estimations_offset, members_offset, "limit")`

Returns `jsonb`: `{ projects: [...], estimations: [...], members: [...] }`.

| Param | Type | Default | Notes |
|---|---|---|---|
| `query` | `text` | required | Matched case-insensitively against name/description fields. |
| `filter_by_tag` | `text` | `NULL` | Reserved; not yet applied to any query. See [CA-596](https://ripplearc.youtrack.cloud/issue/CA-596). |
| `filter_by_date_from` | `timestamptz` | `NULL` | Inclusive lower bound on `updated_at`. |
| `filter_by_date_to` | `timestamptz` | `NULL` | Inclusive upper bound on `updated_at`. |
| `filter_by_owner` | `uuid` | `NULL` | Restricts projects/estimates to this `creator_user_id`. |
| `scope` | `text` | `NULL` | One of `'dashboard'`, `'estimation'`, `'member'`, or `NULL` for all three. |
| `projects_offset`, `estimations_offset`, `members_offset` | `integer` | `0` | Independent pagination offsets per result type. |
| `"limit"` | `integer` | `20` | Shared page size across all three result types. |

**Security:** `SECURITY INVOKER` (default — no explicit `SECURITY DEFINER`). Relies entirely on RLS for row visibility on `projects`, `cost_estimates`, and `project_members`/`users`; this function does not bypass RLS.

**Privacy:** the members result selects only `id`, `first_name`, `last_name`, `professional_role`, `profile_photo_url`. Never select `users.credential_id` here — a prior review caught credential_id leakage on this exact RPC.

### Date range filter (CA-752 / CA-170 / DASH-006)

`filter_by_date_from`/`filter_by_date_to` apply as an inclusive range on `updated_at` for both `projects` and `cost_estimates` (the design doc DASH-006 mentions only projects, but this function's own `SELECT` targets show estimations are filtered too — that pre-existing behavior, previously on `created_at`, is preserved here on `updated_at`).

- Either bound may be `NULL` to leave that side unbounded.
- An inverted range (`filter_by_date_from > filter_by_date_to`) raises `22023` rather than silently returning no rows, so the client can surface a validation message.
- Before CA-752, this filtered on `created_at` (the prior single `filter_by_date` param), and `projects.updated_at` had no trigger maintaining it — see `core/projects`' README for that fix.

## Source-of-Truth Workflow

Edit only the files in this folder, then generate the migration from a live local diff (the same pattern documented in the sibling `project_search_history` module):

```bash
# 1) Reset local DB to baseline (applies all existing migrations).
supabase db reset

# 2) Apply this module's schemas to the running local DB.
for f in supabase/schemas/global_search/global_search/0?_*.sql; do
  docker exec -i supabase_db_construculator-backend \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$f"
done

# 3) Emit the migration from the live diff.
TS=$(date -u +"%Y%m%d%H%M%S")
supabase db diff --from=migrations --to=local 2>/dev/null \
  | grep -v "^A new version\|^We recommend" \
  > "supabase/migrations/${TS}_global_search_function_update.sql"

# 4) Reset once more to confirm the generated migration applies cleanly.
supabase db reset
```

Review the generated migration file and commit both layers together. Do **not** hand-author migration files.

## Related Tables

- `search_history` (sibling module) — backs `get_search_suggestions`, separate from this RPC's own search logic.
- `project_search_history` (sibling module) — a completely independent, projects-only search surface; see its README for the comparison table.
