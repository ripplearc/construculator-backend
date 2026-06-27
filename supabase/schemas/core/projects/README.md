# Projects Module

## Overview

The `projects` table is the core unit of work in the application — every cost estimate, search result, and team membership is scoped to a project. The table itself and its indexes/RLS policies predate this `schemas/` folder and have not yet been backfilled here (see Scope below); only the `updated_at` trigger introduced in CA-752 is documented in this module so far.

## Table Structure (for reference — not yet backfilled into this folder)

- `id` - UUID primary key
- `project_name` - Project display name (required)
- `description` - Optional free-text description
- `creator_user_id` - FK to `users.id`
- `owning_company_id` - FK to `companies.id`
- `export_folder_link`, `export_storage_provider` - Export destination metadata
- `created_at`, `updated_at` - Timestamps
- `project_status` - `project_status_enum`

Defined in migration `20250514093706_12_projects.sql`. RLS policies are defined separately in `20251203040526_RLS_06_projects_rules.sql`.

## Triggers

### `trigger_update_projects_updated_at` — `BEFORE UPDATE`

Sets `updated_at = now()` on every row update via the shared `public.set_current_timestamp_updated_at()` function (defined in `supabase/schemas/_shared/01_functions.sql`, also used by `users`, `companies`, `professional_roles`).

**Why this was added (CA-752):** before this trigger existed, `projects.updated_at` was never bumped on edit — there was no mechanism maintaining it, unlike `cost_estimates`, which has its own permission-checking trigger that also sets `updated_at`. Any feature relying on `projects.updated_at` to mean "last modified" (e.g. the `global_search` date-range filter) would have been filtering on a column frozen at row creation.

**Asymmetry with `cost_estimates` (flagged in PR #43 review):** `projects.updated_at` is maintained by this dedicated, unconditional trigger — it fires for *any* `UPDATE`, regardless of role (authenticated, service role, migration script, etc.). `cost_estimates.updated_at`, by contrast, is set only as a side effect inside `check_cost_estimate_update_permissions()`, a permission-checking trigger that is scoped to `authenticated`-role updates (see `20260212011547_rls_cost_estimates_update.sql`). This works correctly for normal app traffic today, but a future service-role `UPDATE` on `cost_estimates` (e.g. a backfill or migration script) would silently leave `cost_estimates.updated_at` stale while `projects.updated_at` keeps auto-updating regardless of caller role. If you're writing a service-role migration that touches `cost_estimates`, set `updated_at` explicitly — don't rely on the trigger.

## Scope

This module currently only documents the trigger added in CA-752. The table definition, indexes, and RLS policies that already exist in `supabase/migrations/` have not yet been backfilled into `01_table.sql`/`02_indexes.sql`/`03_rls.sql` here — that backfill is out of scope for CA-752 and should be done as its own follow-up if/when this module needs full parity with `companies`/`users`/`professional_roles`.

## Related Tables

- `cost_estimates`, `project_members`, `project_search_history` — all scoped to a project via `project_id`.
- `companies` — a project's `owning_company_id` references this table.
