# User Calculator Stores Module

## Overview

`user_calculator_stores` holds the calculator's **trade stores** — the
editable lists behind the material keys (UX Design Doc term 2.16, Appendix
B): drywall sheet sizes, masonry piece sizes, footing cross-sections,
on-centre spacings, the fence's spacing and rails per section, rates per
unit, waste per unit and named densities. Introduced in CA-1076 (Engine
ticket I1; design: Calculation Module Design Doc, Appendix E).

Only the rows the user **added or changed** live here. The seed defaults of
Appendix B ship inside the app and are laid over these rows at read time, so
a fresh account has no rows, a user who never edits a store never writes one,
and a changed seed is one row that names the seed it replaces.

The stores follow the user's account: the sync stream in
`powersync/sync-config.yaml` delivers a user's rows to every phone they sign
in on, and a soft delete made on one phone hides the row on the others.

## Table Structure

- `id` — UUID primary key, assigned on insert
- `user_id` — FK to `users.id`, `ON DELETE CASCADE`: a trade store is the
  user's own preference, so deleting the account deletes its rows, as
  `company_users.user_id` does. `user_consents` keeps `NO ACTION` because it
  is an evidence log; that reasoning does not apply here
- `store_kind` — `calculator_store_kind_enum`: `sheet_size`, `masonry_piece`,
  `footing_section`, `on_centre_spacing`, `fence_config`, `rate`, `waste`,
  `density`
- `values` — `jsonb`, `CHECK (jsonb_typeof = 'object')`. The entry's fields
  in the engine's canonical units (whole ticks of 1/64 inch, hundredths of a
  pound, percent, dollars). The keys belong to the app's row mapper, not to
  the database; a changed seed carries the seed's key in `"seed"`
- `unit_system` — `'imperial'` or `'metric'` (`CHECK`). Sheet sizes are
  seeded per system, so a user-added size belongs to the system it was typed
  in
- `created_at`, `updated_at` — `updated_at` is stamped by
  `set_user_calculator_stores_updated_at` on every `UPDATE`; an `INSERT`
  keeps the values the phone sent
- `deleted_at` — Soft delete. The app sets it through an `UPDATE`; the row
  stays so a deleted seed keeps hiding the shipped default on every phone

`values` is a reserved word, so every statement quotes it, as this repo quotes
every identifier.

## Business Rules

### Seeds are never stored

The app ships Appendix B's defaults and applies them at read time. A seed the
user edits becomes one row carrying `"seed"` in its `values`; a seed the user
deletes becomes a row with `deleted_at` set and the seed's key, so the
deletion syncs too.

### Last upload to arrive wins

The server sets `updated_at` on every `UPDATE`, whatever the phone sent, so
the column records when the server applied the write, not what a phone's
clock said. Which phone edited first does not matter: the last upload to
reach the server stands. An `INSERT` keeps the phone's `created_at` and
`updated_at`; a new row has nothing to conflict with.

### One live row per changed seed

`user_calculator_stores_live_seed_key` allows one live row per
`(user_id, store_kind, unit_system, values->>'seed')`. Two phones that edit
the same default while offline would otherwise each insert a row that never
merges. Rows the user adds themselves have no `"seed"` key and are not
restricted; a soft-deleted row frees its key.

### Soft delete

Delete from the app is an `UPDATE` setting `deleted_at`. A deleted seed must
leave a row behind, carrying the seed's key, or the shipped default would
come back on every phone; user-added rows take the same path so the app has
one delete. The `DELETE` policy lets a signed-in client (an API call or an
upload) hard-delete its own rows and nobody else's; the SQL editor runs as
`postgres` and never passes through it. A hard-delete job for retention is a
follow-up if policy requires it (design doc, Security Considerations).

## Indexes

- `user_calculator_stores_user_kind_idx` on `(user_id, store_kind) WHERE
  deleted_at IS NULL` — the one read the app makes, a user's live rows of
  one store
- `user_calculator_stores_live_seed_key`, unique, on `(user_id, store_kind,
  unit_system, (values->>'seed')) WHERE deleted_at IS NULL AND values ?
  'seed'` — one live row per changed seed

## RLS

Owner-only on every verb, keyed on `public.jwt_internal_user_id()`, **not**
`auth.uid()`. `auth.uid()` returns `users.credential_id` while `user_id` here
references `users.id` — the two never match, so policies written against
`auth.uid()` return zero rows for every user and the symptom reads like "the
stores aren't syncing". The helper lives in `schemas/_shared/01_functions.sql`.

- **SELECT**, **INSERT** (`WITH CHECK`), **UPDATE** (`USING` and `WITH
  CHECK`), **DELETE**: `user_id = jwt_internal_user_id()`
- No role sees another user's rows; there is no team, project or company
  visibility of a trade store

## PowerSync

- Publication: `ALTER PUBLICATION powersync ADD TABLE
  public.user_calculator_stores` (migration 52). A table outside the
  publication produces a stream that connects, reports healthy and delivers
  nothing
- Stream `user_calculator_stores` (auto-subscribed) in
  `powersync/sync-config.yaml`: every column including `deleted_at`, filtered
  on `auth.parameter('$.app_metadata.internal_user_id')`, the same claim the
  RLS reads. PowerSync bypasses RLS, so that `WHERE` is what keeps one user's
  rows off another user's phone

## Consumers

- The app's `TradeStoresRepository` (construculator-app, CA-1083) reads the
  stores and writes the user's changes. Its first version keeps the stores in
  `Table.localOnly` tables on the phone; the switch to this synced table is
  the app's half of this ticket and is tracked there

## Related Tables

- `users` — `user_id` references `users.id` with `ON DELETE CASCADE`;
  deleting the user (or the `auth.users` row above it, which cascades to
  `users`) removes their store rows
- The five settings of the calculator live in `users.user_preferences`
  (key `calculator`), not here
