-- user_consents table
-- Append-only log of every consent decision — withdrawals as well as
-- acceptances. Only the newest row per (user_id, consent_type) is meaningful
-- to the gate; everything beneath it is history. No IP or user agent: CA-962
-- specifies app_version and platform as the only context captured.
-- See README.md.

CREATE TABLE IF NOT EXISTS "public"."user_consents" (
  "id"           uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "user_id"      uuid NOT NULL REFERENCES "public"."users"("id"),
  "consent_type" "public"."consent_type_enum" NOT NULL,
  "version"      integer NOT NULL,
  "action"       "public"."consent_action_enum" NOT NULL,
  "recorded_at"  timestamptz NOT NULL DEFAULT (now()),
  "app_version"  text,
  "platform"     text,

  -- NOT `> 0`, unlike consent_versions.version. A withdrawal records the
  -- version it revokes, and the client writes 0 when there is nothing on file
  -- to revoke; `> 0` would reject exactly those withdrawals at runtime.
  CONSTRAINT "user_consents_version_non_negative" CHECK ("version" >= 0)
);

ALTER TABLE "public"."user_consents" OWNER TO "postgres";

-- Three things deliberately ABSENT, all of which look like reasonable
-- review suggestions:
--   * No FK to consent_versions — the log must survive administrative
--     correction of that table; a consent record is evidence and must not
--     cascade away because someone fixed a document URL.
--   * No UNIQUE on (user_id, consent_type, version) — accept, withdraw, then
--     accept the same version again is legitimate, and all three are real
--     events.
--   * No ON DELETE clause on the users FK — the same reasoning as above, one
--     table over. A hard delete of the user would otherwise take the whole
--     consent history with it, silently, which is the one thing a compliance
--     log cannot do. Bare (NO ACTION) blocks the delete instead, matching
--     every other users(id) FK in this repo. Note there is no user-erasure
--     path here to defer to: user_status is only active/inactive, and nothing
--     deletes a users row today. A future erasure flow has to decide what
--     happens to this log rather than inherit an answer from the DDL.
