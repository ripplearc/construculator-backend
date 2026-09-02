# User Consents Module

## Overview

`user_consents` is the append-only log of every consent decision a user has
made — **acceptances and withdrawals alike**, not just acceptances. Introduced
in CA-963 for the server-driven versioned consent flow (design: CA-962, parent
epic: CA-961).

Append-only is the design, not an implementation detail. Withdrawing consent
inserts a `withdrawn` row rather than deleting the `accepted` one, so the trail
separates *consented, then revoked* from *never consented* — a distinction that
matters to anyone auditing what a user agreed to and when. Only the newest row
per `(user_id, consent_type)` is meaningful to the gate; everything beneath it
is history.

## Table Structure

- `id` — UUID primary key. Assigned on insert; the client's
  `UserConsentDto.toInsertJson()` omits it
- `user_id` — FK to `users.id`. No `ON DELETE` clause, deliberately — see
  below
- `consent_type` — `consent_type_enum` (`terms_and_privacy`, `analytics`)
- `version` — Integer, `CHECK (version >= 0)`. The document version this record
  refers to
- `action` — `consent_action_enum` (`accepted`, `withdrawn`)
- `recorded_at` — When the user took the action. Client-supplied, and
  `CHECK (recorded_at <= now() + interval '1 day')` — see below
- `app_version` — Nullable audit metadata
- `platform` — Nullable audit metadata

No IP address and no user agent. CA-962 specifies `app_version` and `platform`
as the only context captured, and the table holds no PII beyond the user
reference itself.

### Why `version >= 0` and not `> 0`

`consent_versions.version` is `CHECK (version > 0)` and it is tempting to
mirror that here. **Don't.** A withdrawal records the version it revokes, and
`ConsentRepositoryImpl.recordWithdrawal` writes `0` when there is nothing on
file to revoke (`_effectiveAcceptedVersion(current) ?? 0`). A `> 0` check would
reject exactly those withdrawals, at runtime, on the path where a user is
trying to revoke consent.

**The client does not yet agree with this.** `UserConsentDto.fromJson` in
`construculator-app` rejects `version <= 0` on read-back, commented as
mirroring "the backend's check (version > 0); CA-963 §2" — but §2 is
`consent_versions`, a different table. The effect is that a legitimate
`version = 0` withdrawal written by this app syncs back, throws
`FormatException('Unreadable user consent row: version')`, and the repository
resolves that throw to a *status* — so revoking consent silently makes the
gate unreadable. The fix belongs in the app's DTO, not in this schema; tracked
against CA-963 and required before the consent gate goes live.

### Why `recorded_at` is bounded on the future side only

`recorded_at` is written by the client on every insert — `toInsertJson()` sends
it unconditionally, so the column's `DEFAULT now()` never actually fires. That
matters more here than it would on an ordinary audit column, because
`recorded_at` is the *ordering key*: the newest row per
`(user_id, consent_type)` is the one that decides the gate. Combined with an
INSERT policy that checks only *whose* row it is, and with no FK on
`(consent_type, version)`, every field that decides the gate — `recorded_at`,
`version`, `action` — is authored by the caller.

Left unbounded, a client could insert
`(action = 'accepted', version = 99, recorded_at = '2099-01-01')` for its own
user, and no later legitimate `withdrawn` row could ever sort above it. That
row would report consent-given indefinitely: it defeats a future re-consent
requirement, and for `analytics` it keeps capture enabled without a valid
acceptance behind it.

Forcing server time instead would be wrong. Consent decisions are taken
offline and synced later (PowerSync, CA-971), so the honest `recorded_at` is
frequently well in the past — a `BEFORE INSERT` trigger that overwrote it with
`now()`, or a symmetric bound, would discard exactly that legitimate history.
Only the future side needs closing, with a day of slack for device clock skew.

A `CHECK` rather than a trigger that clamps a future value down to `now()`:
this table is evidence. Rejecting a write that can't be true is honest;
silently rewriting the timestamp the user's own device reported, and then
storing the result as a record of what that user did, is not.

## Indexes

- `user_consents_user_type_recorded_idx` —
  `(user_id, consent_type, recorded_at DESC)`. Matches the only query the gate
  runs: newest record for one user and one consent type. Equality on the first
  two columns, `recorded_at DESC` supplying the order, so the newest row is
  read first with no sort.

## Deliberately Absent Constraints

All three of these look like reasonable review suggestions. None is correct:

- **No FK on `(consent_type, version)` to `consent_versions`.** The log must
  survive administrative correction of the versions table. A consent record is
  evidence of what a user did; it cannot become un-writable — or cascade away —
  because someone fixed a typo in a document URL upstream.
- **No `UNIQUE (user_id, consent_type, version)`.** A user may accept version 2,
  withdraw it, and accept version 2 again. All three are real events and all
  three belong in the log.
- **No `ON DELETE CASCADE` on the `users` FK.** Same reasoning as the
  `consent_versions` FK above, one table over: a consent record is evidence,
  and a hard delete of the user must not silently take that user's entire
  consent history with it. The bare FK (`NO ACTION`) blocks such a delete
  instead, which matches every other `users(id)` FK in this repo. Pinned by
  `user_consents_test.sql` — both the declared `confdeltype` and an actual
  refused delete — so the behavior can't drift back.

  There is no user-erasure path for this to defer to: `user_status` is only
  `active`/`inactive`, and nothing in the repo deletes a `users` row. So a
  future erasure flow (a GDPR right-to-erasure request, say) has to make an
  explicit decision about this log — what a compliance trail is owed on
  erasure is a legal question, not one the FK should answer silently.

## RLS

Keyed on `public.jwt_internal_user_id()`, **not** `auth.uid()`. `auth.uid()`
returns `users.credential_id` while `user_id` here references `users.id` — the
two never match, so policies written against `auth.uid()` return zero rows for
every user, and the symptom reads like "consent isn't syncing" rather than like
a bug. The helper lives in `schemas/_shared/01_functions.sql`.

- **SELECT** (`user_consents_select_policy`): `user_id = jwt_internal_user_id()`.
  Personal ownership; no cross-user or admin visibility.
- **INSERT** (`user_consents_insert_policy`): same predicate as `WITH CHECK` —
  this is what stops a user recording consent in someone else's name.
- **UPDATE / DELETE**: no policies, for any role, *including the row's owner*.
  This is what makes the table append-only. The absence is the enforcement
  point, not grants: `auto_expose_new_tables` (CA-729) gives the Data API roles
  full SQL-level access on every `db reset`, so RLS is the only thing between a
  client and a rewritten consent history.

  The denials do **not** fail alike, which matters when reading the tests: a
  blocked `INSERT` raises `42501`, while a blocked `UPDATE` or `DELETE` raises
  nothing — with no policy the rows are invisible to the statement, so it
  reports success having changed zero rows. All are pinned in
  `supabase/tests/database/user_consents_test.sql`, the write paths by
  asserting the row survives unchanged rather than by `throws_ok`.

## Consumers

- `ConsentRepositoryImpl` (`construculator-app/lib/libraries/consent/data/repositories/consent_repository_impl.dart`)
  — writes one row per accept and per withdraw, and reads the newest row to
  decide the gate.
- **CA-971** replaces the app's temporary `InMemoryConsentDataSource` with a
  PowerSync-backed local store reading this table, and adds the sync stream
  filtered to `auth.parameter('$.app_metadata.internal_user_id')`.

## Related Tables

- `consent_versions` — published document versions, and the
  `current_consent_versions` view the gate compares against. No FK links the
  two; see above.
- `users` — `user_id` references `users.id`. A hard delete of a user is
  blocked while consent rows exist; nothing cascades. See above.
