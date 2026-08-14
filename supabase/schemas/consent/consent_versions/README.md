# Consent Versions Module

## Overview

`consent_versions` records the published version of each consent document. It
is the source of truth the app compares a user's acceptance against, introduced
in CA-963 for the server-driven versioned consent flow (design: CA-962, parent
epic: CA-961).

The table is **publication history, not current state**: every version ever
published stays in it. That is what keeps `user_consents` rows readable years
later, when a record referencing version 3 of the privacy policy has to be
interpretable against a document now on version 7. Clients therefore read the
[`current_consent_versions`](#view-current_consent_versions) view rather than
this table.

Rows are written **only by migration**. There is no runtime write path and no
RLS policy that would permit one.

## Table Structure

- `id` — UUID primary key
- `consent_type` — `consent_type_enum` (`terms_and_privacy`, `analytics`)
- `version` — Integer, `CHECK (version > 0)`. Monotonic per consent type
- `document_url` — Where the user reads the document. `CHECK` rejects blank
  values (see below)
- `effective_from` — When this version starts binding users. Defaults to `now()`
- `published_at` — Audit metadata: when the row was written. Never decides the
  gate

### Why `document_url` cannot be blank

The Flutter client's `ConsentVersionDto.fromJson` throws a `FormatException` on
an empty `document_url`, and `ConsentRepositoryImpl` resolves that throw to a
*status* rather than an error — deliberately, so an unreadable requirement
blocks instead of erroring. A blank URL would therefore produce a consent page
with nothing to read and no visible failure anywhere. The check rejects it at
write time instead.

## Constraints

- `consent_versions_type_version_uq` — `UNIQUE (consent_type, version)`. One row
  per document version. Doubles as the access path for
  `current_consent_versions`, which enters by `consent_type` and takes the
  highest `version`.
- `consent_versions_version_positive` — `CHECK (version > 0)`.
- `consent_versions_document_url_not_blank` — `CHECK (length(btrim(document_url)) > 0)`.

> **Note for the follow-up PR:** the `user_consents` log lands separately and
> its `version` column deliberately uses `>= 0`, **not** `> 0` — a withdrawal
> with nothing on file to revoke records version `0`. Don't copy this table's
> check across.

## View: `current_consent_versions`

One row per consent type — the version currently in force:

```sql
SELECT DISTINCT ON (consent_type) …
FROM consent_versions
WHERE effective_from <= now()
ORDER BY consent_type, version DESC;
```

Two rules that a caller reading the base table would have to reimplement, and
which the Flutter client got wrong before this view existed (it took the first
matching row, arbitrary once any document reached version 2):

1. Highest `version` wins, per consent type.
2. Rows with a future `effective_from` are not in force yet — which is what
   makes scheduled publication possible: insert the row ahead of time and it
   goes live on its own.

Declared `WITH (security_invoker = true)` so it evaluates under the caller's
permissions and the `consent_versions` SELECT policy still governs access.
Postgres 15+ only; `config.toml` pins `major_version = 15`.

## RLS

- **SELECT** (`consent_versions_select_policy`): `USING (true)` for
  `authenticated`. Unscoped by design — the published terms are the same
  document for everyone, and a user cannot be asked to accept something they
  are not allowed to read.
- **INSERT / UPDATE / DELETE**: no policies for any client role. Publishing is a
  migration-only act. The *absence* of policies is the enforcement point, not
  grants: `auto_expose_new_tables` (CA-729) hands the Data API roles full
  SQL-level access on every `db reset`, so grants deny nothing here.
  `service_role` bypasses RLS, which is how the seed migration writes.

  The three denials do **not** fail the same way, which matters when reading the
  tests: a blocked `INSERT` raises `42501`
  (*new row violates row-level security policy*), while a blocked `UPDATE` or
  `DELETE` raises nothing at all — with no policy the rows are simply invisible
  to the statement, so it reports success having changed zero rows. All three
  are pinned in `supabase/tests/database/consent_versions_test.sql`, the write
  paths by asserting the row is unchanged rather than by `throws_ok`.

## Consumers

- `RemoteConsentDataSource` (`construculator-app/lib/libraries/consent/data/data_source/remote_consent_data_source.dart`)
  — reads `current_consent_versions` directly over the Data API, deliberately
  bypassing local replication so a stalled sync cannot mask a newly published
  version.
- **CA-971** will replicate both consent tables through PowerSync for the
  offline-first read path. Any column list added there must match the client's
  `schema.dart` exactly.

## Seeding

`20260814…_42_seed_consent_versions_v1.sql` publishes version 1 of both consent
types. It is a **migration**, not a seeder: `supabase/seeders/` only runs on
local `start` / `db reset` and would never reach production.

> **The seeded `document_url` values are provisional** — no published legal
> document URL existed when this module was written. Confirm them before
> `CONSENT_GATE_ENABLED` is switched on in production.

## Related Tables

- `user_consents` — the append-only per-user log of acceptances and
  withdrawals, landing in the follow-up PR on this ticket. It will deliberately
  carry **no FK** to this table: the log has to survive administrative
  correction of the versions here, since a consent record is evidence of what a
  user did and must not cascade away because someone fixed a document URL.
