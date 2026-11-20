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
- `item_name_key` - Generated and stored: `item_name` in lower case (through
  `rate_key_lower()`, see below), every run of
  whitespace collapsed to one space, then trimmed. The whitespace set is `\s`
  plus U+00A0, U+2007, U+202F and U+FEFF, and U+0085 is trimmed at the ends, the
  same characters as `entry_label_key` and the phone. The collision
  constraint compares this column, so `Mini excavator`, `MINI  EXCAVATOR` and
  ` mini excavator ` are one name ("Names match without regard to capital
  letters or extra spaces", storyboard CUJ 6). Never written by a client.
  Rebuilt by migration 60, so it is the last column, after `entry_label_key`

- `entry_label_key` - Generated and stored: `entry_label` built like
  `item_name_key` (lower case through `rate_key_lower()`, runs of whitespace
  collapsed to one space,
  trimmed), and `NULL` when nothing is left. The whitespace set is `\s` plus
  U+00A0, U+2007, U+202F and U+FEFF, and U+0085 is trimmed at the ends, the same
  characters the phone treats as space. So a label of only spaces counts as
  no label. The collision constraint compares this column. Never written by a
  client, and not in the `user_rates` stream: the phone builds its own key.
  Added by migration 60 (`20261104100000_60_your_rates_label_key.sql`), so it is
  after `last_used_at`

### Rate Fields
- `rate_key_lower(text)` - Function used by both key columns. It is Postgres
  `lower()`, except that 410 capital letters keep their case (Cherokee, Osage,
  Adlam, Georgian Mtavruli and some Latin letters). The phone's Dart
  `toLowerCase()` leaves those letters alone, so the database and the phone make
  the same key for every letter (owner decision, 1 November 2026). It is
  `IMMUTABLE`, which the generated columns need. If a later Dart release
  lower-cases more letters, the list in the function must grow.
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
- `last_used_at` - Client-supplied, `timestamptz`, nullable, no default. The
  last time a cost line was added with this rate, stamped by the phone that
  added the line (storyboard CUJ 6, "Used label"). NULL until the first use,
  so the app can say "Saved 3 days ago" for a rate that was never added and
  "Used 3 days ago" for one that was. Saving a new price moves `saved_at` and
  leaves this column alone. No CHECK against `saved_at`, because a save after
  the last use is a valid state (CA-1265). An update keeps the later of the
  stored and the incoming time (CA-1345, see Business Rules)
- `created_at` / `updated_at` - Standard row-modification timestamps,
  present on every table in this repo regardless of whether the Dart entity
  exposes them; `updated_at` is kept current by the shared
  `set_current_timestamp_updated_at()` trigger

## Business Rules

### Collision / save semantics (Decision 55)

Since CA-1306 the `id` is not random. It is `your_rate_id(company_id, category,
item_name_key, equipment_method, entry_label_key)`, a version 5 UUID, and the
check `your_rates_id_matches_identity` refuses any row whose `id` differs. The
column has no default, so an insert without an id fails with a not-null error.
Every phone computes the same id (`YourRateId` in the app), so two phones that
save one rate offline end with one row and the last upload wins (storyboard
CUJ 6). The label key is part of the id, the same five columns as the unique
constraint below, so a second price for one name and method under another label
is a second row with its own id (owner decision on CA-1306 and CA-1336,
2026-11-06). No label and a blank label give the same id. A backslash or a `|` in the name
key or the label key gets a backslash before it, so a name and a label can never
run together into the id of another rate. Migration 63 gives
every existing row its computed id before it adds the check. `anon` cannot run
`your_rate_id`.

The examples both sides run are in the app's
`test/libraries/powersync/units/models/your_rate_id_examples.json`, which is the
one source. The list in `supabase/tests/database/your_rate_id_test.sql` is
written from it by `scripts/your_rate_id_examples_sql.py --write <path>`, and
`--check <path>` fails when the two differ.

Day and Job are separate rows: one machine saved with a day rate and with a job
price is two rows, each with its own price and unit ("Saved with both",
storyboard CUJ 6). A second save with the same name and the same basis is the
collision case below.

Saving an entry:
- No existing row in that `(company_id, category, item_name_key, equipment_method)` grouping →
  always succeeds, inserts a new row (with or without `entry_label`).
- An existing row in that grouping has the **same label** (same
  `entry_label_key`, so capital letters and extra spaces do not count;
  including both `NULL`) → update that row in place (silent overwrite).
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
`(company_id, category, item_name_key, equipment_method, entry_label_key)`. A plain
`UNIQUE` on the same columns would **not** catch
two `NULL`-labeled rows in the same grouping — Postgres treats `NULL <>
NULL` for uniqueness — `NULLS NOT DISTINCT` (Postgres 15+) makes two `NULL`s
count as equal for this constraint instead. The same constraint also serves
as the grouping lookup index and, being a real column-list constraint rather
than an expression index, is a valid
`upsert(onConflict: 'company_id,category,item_name_key,equipment_method,entry_label_key')` target for
the "exact same label" update-in-place case. The phone's upload upserts on
`id`, not on this key, but the key stays a valid target without a schema change.

### Last use keeps the later time (CA-1345)

The phone stamps `last_used_at` itself, and its upload can wait in the queue
for days, so two phones can upload uses of the same rate out of order. The
storyboard (CUJ 6, "Used label") counts from the last time the rate was added
to any estimate, so the later time must win. This is the one deliberate
exception to the storyboard's general rule for two phones changing the same
saved rate ("the change the server receives last wins"), which still holds for
every other column.

`trigger_keep_later_your_rates_last_used_at` (`BEFORE INSERT OR UPDATE`,
function `keep_later_your_rates_last_used_at()`) first checks the incoming time
(see below). On update it then sets
`NEW.last_used_at := GREATEST(OLD.last_used_at, NEW.last_used_at)`. `GREATEST`
ignores `NULL`, so:

- a first use (stored value empty) sets the value
- a later time replaces the stored one
- an earlier time leaves the stored one unchanged
- an empty time never erases a stored one, so a full-row upload from a phone
  that has not seen the use cannot clear it

Every other column in the same update is still applied. Every way the phone
changes an existing row reaches the trigger: a `patch` is an update, a `put` is
an upsert on `id` that takes the update path when the row exists, and the
connector's fallback for a duplicate name sends a full-row update to the row
that already holds it. The rule applies to every role, so a manual correction
that moves the value back has to disable the trigger first. The `user_rates`
stream sends the stored time, so every phone is shown the later one.

The times are the phones' own clocks, so the incoming time is checked on insert
and on update, before the comparison:

- a time more than 1 day after the server's `now()` is stored as `now()`, so a
  phone with a clock set far ahead cannot make a rate show as just used until
  that date has passed
- `infinity` and `-infinity` are refused with an error (`22023`). The app cannot
  send one, so only a direct API call can
- a time up to 1 day ahead, and any past time, is kept as sent

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
  constraint on `(company_id, category, item_name_key, equipment_method, entry_label_key)`.
  Enforces the collision constraint above and doubles as the grouping lookup
  index — its leading columns satisfy `(company_id, category, item_name_key)`
  lookups without a separate, redundant index. Postgres builds a unique
  index for it automatically, and it is a valid
  `onConflict: 'company_id,category,item_name_key,equipment_method,entry_label_key'` upsert target.

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
- **DELETE** - a company member can delete their company's saved rates
  (Settled Decision 8, 2026-10-28). `USING` applies
  `jwt_user_is_company_member`, so a member deleting a row of another company
  deletes zero rows and gets no error. The app needs it to undo a save that
  finished after its 2 second limit.

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
`updated_at` trigger. `your_rates_last_used_at_test.sql` covers the
`last_used_at` column (CA-1265), and `your_rates_keep_later_last_used_at_test.sql`
covers the keep-later trigger (CA-1345): earlier, later and first use, the
exact boundary down to one microsecond, an empty time, other columns in the same
update, two rows in one statement, the upsert on `id` and on the unique key, a
time more than 1 day ahead on insert and on update, `infinity` and `-infinity`,
and a role other than `authenticated`.
