# Global Search — `search_history` Module

## Overview

The `search_history` table records every search term submitted by a user, scoped to the context in which the search was performed (dashboard, estimation, member, or calculation). It powers two features:

1. **Recent searches** — each user's own search history, returned per scope.
2. **Search suggestions** — personalised suggestions drawn first from the user's own frequently-repeated searches, then from the search history of teammates on shared projects.

---

## Table Structure

| Column | Type | Description |
|---|---|---|
| `id` | `uuid` | Primary key, auto-generated. |
| `user_id` | `uuid NOT NULL` | `auth.uid()` of the searching user. No FK — cross-schema boundary with `auth.users`. See Orphan Risk below. |
| `search_term` | `varchar(255) NOT NULL` | Normalised (lowercased, trimmed) search query. |
| `scope` | `varchar(50) NOT NULL` | Context of the search: `dashboard`, `estimation`, `member`, or `calculation`. |
| `search_count` | `int NOT NULL DEFAULT 1` | Number of times this term has been searched in this scope by this user. Incremented atomically by `trigger_increment_search_count`. |
| `has_results` | `boolean NOT NULL DEFAULT false` | Set to `true` by the caller after confirming the search returned at least one result. Only rows with `has_results = true` appear in suggestions. |
| `project_id` | `uuid REFERENCES projects(id) ON DELETE SET NULL` | Optional project context. Set to `NULL` if the project is deleted. |
| `created_at` | `timestamptz NOT NULL` | Row creation timestamp. |
| `updated_at` | `timestamptz NOT NULL` | Last modification timestamp. Maintained by `trigger_set_search_history_updated_at`. |

---

## Business Rules

### 1. Upsert on Conflict

Rows are written via upsert with `ON CONFLICT (user_id, search_term, scope)`. When the same user searches for the same term in the same scope again, the existing row is updated rather than a new one inserted. `search_count` is incremented atomically by the trigger.

### 2. `has_results` Contract

`has_results` defaults to `false` on every insert. The caller is responsible for re-upserting with `has_results = true` after confirming the search returned at least one result. Rows with `has_results = false` are saved in history (visible to the user in recent searches) but excluded from suggestions.

### 3. Teammate Visibility

Project members can read each other's `search_history` rows for shared projects (where `project_id` is non-NULL and matches a project both users belong to). This is intentional — it enables the teammate fallback in `get_search_suggestions`. Personal searches without a project context (`project_id IS NULL`) are never visible to teammates.

### 4. Orphan Risk

`user_id` has no foreign key to `auth.users` (cross-schema boundary). Rows are not cascade-deleted when a user is removed. A periodic cleanup job should purge rows where `user_id` no longer exists in `auth.users`.

> **TODO ([CA-597](https://ripplearc.youtrack.cloud/issue/CA-597)):** Implement periodic cleanup job to purge `search_history` rows where `user_id` no longer exists in `auth.users`.

---

## Indexes

| Name | Column(s) | Purpose |
|---|---|---|
| `search_history_user_term_scope_uq` | `(user_id, search_term, scope)` | Unique constraint; drives upsert conflict resolution. |
| `search_history_user_id_idx` | `user_id` | Fast lookup of all history for a user. |
| `search_history_project_id_idx` | `project_id` | Fast lookup of history for a project (teammate suggestions). |
| `search_history_has_results_idx` | `has_results` | Fast filtering for suggestion queries. |
| `search_history_created_at_idx` | `created_at` | Sorting recent searches by time. |

---

## Triggers

### `trigger_increment_search_count` — `BEFORE UPDATE`

Atomically increments `search_count` when an upsert conflict is resolved (i.e., when the same user searches the same term in the same scope again).

**WHEN guard:** fires only when `user_id`, `search_term`, and `scope` are all unchanged — scoping it to the repeat-search upsert path.

### `trigger_set_search_history_updated_at` — `BEFORE UPDATE`

Sets `updated_at = now()` on every row change.

---

## RLS Policies

| Policy | Operation | Rule |
|---|---|---|
| `search_history_select_policy` | SELECT | User can read their own rows (`user_id = auth.uid()`). |
| `search_history_insert_policy` | INSERT | User can insert rows for themselves (`user_id = auth.uid()`). |
| `search_history_update_policy` | UPDATE | User can update their own rows (`user_id = auth.uid()`). |
| `search_history_delete_policy` | DELETE | User can delete their own rows (`user_id = auth.uid()`). |
| `search_history_teammate_select_policy` | SELECT | User can read rows belonging to teammates on shared projects. Required for `get_search_suggestions` Step 2. |

---

## RPCs

### `public.global_search`

Full-text search across projects, cost estimates, and members. Returns a JSON object `{ projects, estimations, members }`.

**Parameters:**

| Parameter | Type | Description |
|---|---|---|
| `query` | `text` | Search string. |
| `filter_by_tag` | `text` | Reserved for future use — no-op until a project-tag schema exists. |
| `filter_by_date` | `timestamptz` | Optional date filter (results on or after this date). |
| `filter_by_owner` | `uuid` | Optional filter by creator user ID. |
| `scope` | `text` | Limits results to a specific entity type. `NULL` returns all. |
| `projects_offset` | `int` | Pagination offset for the projects result set (default 0). |
| `estimations_offset` | `int` | Pagination offset for the estimations result set (default 0). |
| `members_offset` | `int` | Pagination offset for the members result set (default 0). |
| `limit` | `int` | Pagination limit applied to each entity independently (default 20). Up to `3 × limit` rows may be returned in total. |

**Performance note:** all text matching uses leading-wildcard `LIKE`, which causes sequential scans at scale. A follow-up story should add `pg_trgm` GIN indexes or full-text search.

> **TODO ([CA-598](https://ripplearc.youtrack.cloud/issue/CA-598)):** Add `pg_trgm` GIN indexes or full-text search to replace leading-wildcard `LIKE`.

---

### `public.get_search_suggestions`

Returns up to 10 personalised search term suggestions using a 3-step priority:

1. **Personal history** — user's own searches with `has_results = true`, ordered by frequency.
2. **Teammate history** — searches from teammates on shared projects with `has_results = true`, deduplicated and ordered by frequency.
3. **Empty array** — if neither step finds results.

**Security:** `SECURITY INVOKER`. Anti-spoof guard rejects calls where the `user_id` parameter does not match `auth.uid()`.

---

## Migration Files

| File | Content |
|---|---|
| `20260401085103_32_search_tables.sql` | Consolidated diff-generated migration. Covers: `search_history` table, indexes, RLS enable + 5 policies, `global_search` and `get_search_suggestions` RPCs, `trigger_increment_search_count` and `trigger_set_search_history_updated_at` triggers. |

---

## Related Tables

- `projects` — referenced by `project_id` (ON DELETE SET NULL).
- `project_members` — used in RLS teammate policy and `get_search_suggestions` Step 2 join.
- `users` — joined via `credential_id` to bridge `auth.uid()` to the internal user record.
