# Your Rates Module

## Overview

`your_rates` is the contractor's personal saved-rate book: a per-company set
of rates a contractor has saved for reuse across estimates, backing
Equipment's recents list and rate search (CA-1145).

Built from Estimation v2 design doc Decision 37 ("store Your rates per
company, in the same table Decision 5 already requires") and Decision 55
("entries keep `(company_id, category, item_name)` as their lookup grouping,
but that grouping can now hold several entries, disambiguated by
`entry_label`").

## Table Structure

### Core Fields
- `id` - UUID primary key
- `company_id` - Foreign key to `companies` (no `ON DELETE` clause: a saved
  rate blocks a hard company delete, like every other `companies` reference)
- `category` - `cost_item_type_enum`: `'material'`, `'labor'`, or
  `'equipment'` (reused directly, not a new enum)
- `item_name` - Display name for the item, kept in the contractor's own spelling
- `item_name_key` - Generated and stored: `item_name` in lower case, every run of
  whitespace (spaces, tabs, new lines, non-breaking spaces) collapsed to one
  space, then trimmed. The collision
  constraint compares this column, so `Mini excavator`, `MINI  EXCAVATOR` and
  ` mini excavator ` are one name ("Names match without regard to capital
  letters or extra spaces", storyboard CUJ 6). Never written by a client

### Rate Fields
- `rate_amount` - `numeric(18,4)`, mirrors `cost_items.unit_price`
- `rate_currency` - `character varying(20)`, mirrors `cost_items.currency`
- `unit` - `character varying(50)`, nullable. Free text, not a Postgres enum
  — mirrors `cost_items.unit_measurement`, the existing precedent for
  storing the Flutter `Unit` enum's values
- `equipment_method` - `equipment_pricing_method_enum` (`'day'` / `'job'`),
  nullable; only meaningful for `category = 'equipment'`. Values are the
  wire contract with the Flutter `EquipmentPricingMethod` enum's `.name`
  output, not a design choice made here

### Grouping / Disambiguation
- `entry_label` - `character varying(100)`, nullable. Shown to the
  contractor so they can tell entries in the same grouping apart instead of
  the app silently overwriting one (Decision 55)

### Metadata
- `saved_at` - Client-supplied, `timestamptz`, NOT NULL, no default. Domain
  time (when the contractor saved the rate), not row-modification time —
  same precedent as `user_consents.recorded_at`
- `created_at` / `updated_at` - Standard row-modification timestamps,
  present on every table in this repo regardless of whether the Dart entity
  exposes them; `updated_at` is kept current by the shared
  `set_current_timestamp_updated_at()` trigger

## Business Rules

### Collision / save semantics (Decision 55)

A "collision" is on `(company_id, category, item_name_key, equipment_method)` plus the label — never on `id`,
which is an ordinary server-generated primary key, not chosen by the caller
and not part of collision detection.

Day and Job are separate rows: one machine saved with a day rate and with a job
price is two rows, each with its own price and unit ("Saved with both",
storyboard CUJ 6). A second save with the same name and the same basis is the
collision case below.

Saving an entry:
- No existing row in that `(company_id, category, item_name_key, equipment_method)` grouping →
  always succeeds, inserts a new row (with or without `entry_label`).
- An existing row in that grouping has the **exact same** `entry_label`
  (including both `NULL`) → update that row in place (silent overwrite).
- No existing row matches the label, and the incoming `entry_label` is
  `NULL` → **rejected** (two unlabeled Equipment rates under the same item
  name is the ticket's own rejection case).
- No existing row matches the label, and the incoming `entry_label` is a
  distinct non-`NULL` value → insert as a new row.

This branching logic lives in the Flutter repository (`YourRatesRepository`,
a separate PR) — it is query-then-decide application logic, not something
the database can express as a single constraint. What this schema provides
is the safety net beneath it: `your_rates_company_category_name_method_label_key`
(see `01_table.sql`), a `UNIQUE NULLS NOT DISTINCT` constraint on
`(company_id, category, item_name_key, equipment_method, entry_label)`. A plain
`UNIQUE` on the same columns would **not** catch
two `NULL`-labeled rows in the same grouping — Postgres treats `NULL <>
NULL` for uniqueness — `NULLS NOT DISTINCT` (Postgres 15+) makes two `NULL`s
count as equal for this constraint instead. The same constraint also serves
as the grouping lookup index and, being a real column-list constraint rather
than an expression index, is a valid
`upsert(onConflict: 'company_id,category,item_name_key,equipment_method,entry_label')` target for
the "exact same label" update-in-place case — the app does not use upsert
today, but this keeps the option open without a schema change.

### Design-doc note: no override / default-price columns

Decision 5 mentions "a per-line override and a default-price column" as
cheap future additions to this same table, once a "re-price to latest"
action ships. Neither Decision 5 nor Decision 55 gives concrete column
names, and the `YourRateEntry` Dart entity this table backs has no
override/default-price fields. This migration deliberately does **not** add
speculative columns for that — it is designed-but-not-yet-consumed
headroom, not a requirement of CA-1145. Flagging it here rather than
building it.

## Indexes

- `your_rates_pkey` - Primary key on `id`
- `your_rates_company_category_name_method_label_key` - `UNIQUE NULLS NOT DISTINCT`
  constraint on `(company_id, category, item_name_key, equipment_method, entry_label)`.
  Enforces the collision constraint above and doubles as the grouping lookup
  index — its leading columns satisfy `(company_id, category, item_name_key)`
  lookups without a separate, redundant index. Postgres builds a unique
  index for it automatically, and it is a valid
  `onConflict: 'company_id,category,item_name_key,equipment_method,entry_label'` upsert target.

## Row rules (CHECK constraints)

- `your_rates_item_name_not_blank` - `item_name_key` is not empty, so a name of only spaces, tabs or new lines is refused
- `your_rates_rate_amount_not_negative` - `rate_amount >= 0`
- `your_rates_rate_currency_not_blank` - `rate_currency` is not empty or only spaces
- `your_rates_equipment_method_equipment_only` - `equipment_method` is only
  set on `category = 'equipment'` rows

## RLS Policies

Company-scoped (Decision 37), via the shared `jwt_user_is_company_member()`
helper (`supabase/schemas/_shared/01_functions.sql`) — any membership, any
role. The ticket does not gate "Your rates" access by role.

- **SELECT** - a company member can view their company's saved rates
- **INSERT** - a company member can save a rate for their own company
- **UPDATE** - a company member can update their company's saved rates;
  `USING` and `WITH CHECK` both apply `jwt_user_is_company_member`, so a
  member cannot retarget a row to a company they don't belong to (mirrors
  `cost_estimates_update_policy`'s two-clause pattern)
- No **DELETE** policy, deliberately — neither Decision 55 nor the ticket
  mentions deleting a saved rate. Mirrors `user_consents`' own
  withheld-capability precedent: with no policy, DELETE succeeds having
  changed zero rows rather than erroring.

**RLS alone does not scope a read to one company.** `company_users` has a
unique index on `(user_id, company_id)` (migration 10), so one user can
belong to more than one company. For such a user, the SELECT policy's
`jwt_user_is_company_member` check returns true for every company they
belong to, so an unscoped `SELECT` returns the rows of **every** company
they are a member of, not just one. The Flutter repository (`search`,
`getByItemName`) therefore passes an explicit `companyId` on every read and
filters on it — that filter, not RLS, is what actually scopes a read to one
company. `save(entry)` carries `company_id` explicitly for the same reason,
and the INSERT/UPDATE policies' `WITH CHECK` verifies the caller is actually
a member of whichever company the row names.

## PowerSync

`your_rates` is synced via the `user_rates` stream
(`powersync/sync-config.yaml`), `auto_subscribe: false` (on-demand, like
`user_cost_estimates` — a feature not every session touches).

**This is a load-bearing security boundary, not a convenience filter.**
PowerSync replicates around Postgres RLS entirely — it reads from the
replication log, not through the API — so the stream's own `WHERE` clause
is the *entire* access-control story for what a client receives over sync.
The `user_rates` stream's `accessible_companies` CTE reimplements the exact
membership check `jwt_user_is_company_member()` performs for RLS:

```sql
SELECT company_id AS id FROM company_users
WHERE user_id = auth.parameter('$.app_metadata.internal_user_id')
```

Both `your_rates` and `company_users` are added to the `powersync`
publication in `20260923120100_46_add_your_rates_to_powersync.sql`.
`company_users` is not itself synced to any client — no stream selects from
it directly — it exists in the publication only so the CTE above can be
evaluated against replicated state, the same role `role_permissions` /
`permissions` play for the `user_cost_estimates` stream.

## Testing

See `supabase/tests/database/your_rates_test.sql`:
table/PK/FK/index shape, the unique constraint's collision behavior
(including the both-`NULL`-label case, a Day row next to a Job row, and names
that differ only by case or spaces), the CHECK rules, RLS SELECT/INSERT/UPDATE scoping
across two companies, the no-claim denial-by-default case, and the
`updated_at` trigger.
