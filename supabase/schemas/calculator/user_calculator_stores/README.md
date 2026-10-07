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
- `user_id` — FK to `users.id`. Bare (`NO ACTION`), like every other
  `users(id)` FK in this repo
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
  `set_user_calculator_stores_updated_at` on every `UPDATE`
- `deleted_at` — Soft delete. The app sets it through an `UPDATE`; the row
  stays for sync convergence and every phone hides it

`values` is a reserved word, so every statement quotes it, as this repo quotes
every identifier.

## Business Rules

### Seeds are never stored

The app ships Appendix B's defaults and applies them at read time. A seed the
user edits becomes one row carrying `"seed"` in its `values`; a seed the user
deletes becomes a row with `deleted_at` set and the seed's key, so the
deletion syncs too.

### Last write wins per row

PowerSync uploads a row with its `updated_at`, and the newer write stands.
The trigger stamps `updated_at` server-side so a phone with a wrong clock
cannot win a conflict it lost.

### Soft delete

Delete from the app is an `UPDATE` setting `deleted_at`. The `DELETE` policy
exists so a user can hard-delete their own rows from the SQL editor, and so
that nobody else can; a hard-delete job for retention is a follow-up if
policy requires it (design doc, Security Considerations).

## Indexes

- `user_calculator_stores_user_kind_idx` on `(user_id, store_kind) WHERE
  deleted_at IS NULL` — the one read the app makes, a user's live rows of
  one store

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
  public.user_calculator_stores` (migration 46). A table outside the
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

- `users` — `user_id` references `users.id`; a hard delete of a user with
  store rows is blocked, nothing cascades
- The five settings of the calculator live in `users.user_preferences`
  (key `calculator`), not here
