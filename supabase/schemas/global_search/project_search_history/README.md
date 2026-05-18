# Project Search — `project_search_history` Module

## Overview

The `project_search_history` table records every search term submitted by a user to the **Project Search** feature — a dedicated search surface whose only target is **projects**. It powers two surfaces:

1. **Recent searches** — the user's own most-recently submitted terms (ordered by `updated_at DESC`).
2. **Search suggestions** — the user's own most-frequently submitted terms that returned at least one result (ordered by `search_count DESC`).

### Project Search vs Global Search

Project Search is **completely independent** from Global Search:

| Feature | Backed by | Searches across |
|---|---|---|
| **Global Search** | `public.search_history` (with `scope` column) | projects + members + cost estimates |
| **Project Search** | `public.project_search_history` (this module) | projects only |

Neither feature reads from or writes to the other's table. A search submitted via Global Search lands in `search_history` and never appears in Project Search's recent/suggestions. The same applies in reverse.

---

## Table Structure

| Column | Type | Description |
|---|---|---|
| `id` | `uuid` | Primary key, auto-generated. |
| `user_id` | `uuid NOT NULL` | `auth.uid()` of the searching user. No FK — cross-schema boundary with `auth.users`. See Orphan Risk below. |
| `search_term` | `varchar(255) NOT NULL` | Normalised (lowercased, trimmed) search query. |
| `has_results` | `boolean NOT NULL DEFAULT false` | Set to `true` by the caller after confirming the search returned at least one result. Only rows with `has_results = true` appear in suggestions; recent searches show all rows. |
| `search_count` | `int NOT NULL DEFAULT 1` | Number of times this user has searched this term. Incremented atomically by `trigger_increment_project_search_count` on upsert conflicts. |
| `created_at` | `timestamptz NOT NULL` | Row creation timestamp. Preserved on upsert conflicts. |
| `updated_at` | `timestamptz NOT NULL` | Last modification timestamp. Maintained by `trigger_set_project_search_history_updated_at`. Drives the recent-searches ordering. |

---

## Business Rules

### 1. Upsert on Conflict

Rows are written via upsert with `ON CONFLICT (user_id, search_term)`. When the same user searches the same term again, the existing row is updated rather than a new one inserted. `search_count` is incremented atomically by the trigger, and `created_at` is preserved (BEFORE UPDATE triggers never touch it, and the upsert's `DO UPDATE SET` clause must not list `created_at`).

### 2. `has_results` Contract

`has_results` defaults to `false` on every insert. The caller is responsible for re-upserting with `has_results = true` after confirming the search returned at least one result. Rows with `has_results = false` are saved in history (visible to the user in recent searches) but excluded from suggestions.

### 3. Personal Only

Project Search history is personal — there is no teammate or cross-user visibility. A user only ever sees their own rows.

### 4. Orphan Risk

`user_id` has no foreign key to `auth.users` (cross-schema boundary). Rows are not cascade-deleted when a user is removed. A periodic cleanup job should purge rows where `user_id` no longer exists in `auth.users`.

> **TODO ([CA-597](https://ripplearc.youtrack.cloud/issue/CA-597)):** The same orphan-cleanup ticket that covers `search_history` should also purge `project_search_history` rows whose `user_id` no longer exists in `auth.users`. Extend the cleanup job's scope when CA-597 is implemented.

---

## Indexes

| Name | Column(s) | Purpose |
|---|---|---|
| `project_search_history_user_term_uq` | `(user_id, search_term)` | Unique constraint; drives upsert conflict resolution. |
| `project_search_history_user_id_idx` | `user_id` | Fast lookup of all history for a user. |
| `project_search_history_has_results_idx` | `has_results` (partial: `WHERE has_results = true`) | Fast filtering for suggestion queries. |
| `project_search_history_updated_at_idx` | `updated_at` | Sorting recent searches by time. |

---

## Triggers

Both trigger functions are reused from the global `search_history` module — they only touch `NEW.search_count` / `NEW.updated_at` and are table-agnostic.

### `trigger_increment_project_search_count` — `BEFORE UPDATE`

Atomically increments `search_count` when an upsert conflict is resolved.

**WHEN guard:** fires only when `user_id` and `search_term` are both unchanged — scoping it to the repeat-search upsert path.

### `trigger_set_project_search_history_updated_at` — `BEFORE UPDATE`

Sets `updated_at = now()` on every row change.

---

## RLS Policies

| Policy | Operation | Rule |
|---|---|---|
| `project_search_history_select_policy` | SELECT | User can read their own rows (`user_id = auth.uid()`). |
| `project_search_history_insert_policy` | INSERT | User can insert rows for themselves (`user_id = auth.uid()`). |
| `project_search_history_update_policy` | UPDATE | User can update their own rows (`user_id = auth.uid()`). |
| `project_search_history_delete_policy` | DELETE | User can delete their own rows (`user_id = auth.uid()`). |

---

## RPC

### `public.get_project_search_suggestions(user_id uuid)`

Returns up to 10 personalised search-term suggestions using a two-step priority:

1. **Personal history** — the caller's own searches with `has_results = true`, ordered by frequency.
2. **Empty array** — if the caller has no qualifying history.

**Security:** `SECURITY INVOKER`. Anti-spoof guard rejects calls where the `user_id` parameter does not match `auth.uid()` (raises `42501`).

**Privacy:** the RPC returns only `text[]` of search terms. It does not select `users.credential_id` or any other auth identifier.

**Recent searches** are read with a direct `SELECT` against the table (RLS-gated), so no dedicated RPC is required for that surface:

```sql
SELECT search_term, updated_at
FROM project_search_history
WHERE user_id = auth.uid()
ORDER BY updated_at DESC
LIMIT <n>;
```

---

## Source-of-Truth Workflow

Edit only the files in this folder. The standard `supabase db diff -f <name>` invocation uses a fresh shadow database; for this module a fresh shadow DB is acceptable (no cross-module FKs), but the same live-diff workflow is documented for parity with sibling modules:

```bash
# 1) Reset local DB to baseline (applies all existing migrations).
supabase db reset

# 2) Apply this module's schemas to the running local DB.
for f in supabase/schemas/global_search/project_search_history/0?_*.sql; do
  docker exec -i supabase_db_construculator-backend \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$f"
done

# 3) Emit the migration from the live diff. db diff prints to stdout
#    when invoked this way, so redirect into the migrations folder.
TS=$(date -u +"%Y%m%d%H%M%S")
supabase db diff --from=migrations --to=local 2>/dev/null \
  | grep -v "^A new version\|^We recommend" \
  > "supabase/migrations/${TS}_33_project_search_history.sql"

# 4) Reset once more to confirm the generated migration applies cleanly.
supabase db reset
```

Review the generated migration file and commit both layers together. Do **not** hand-author migration files.

---

## Related Tables

- `search_history` (sibling module) — the global search history. **Separate feature; this module does not read from or write to it.**
