-- Indexes for user_consents

-- The only query the gate runs: newest record for one user and one consent
-- type. Equality on the first two columns, recorded_at DESC supplying the
-- order, so the newest row is read first with no sort.
-- Not UNIQUE — see 01_table.sql.
CREATE INDEX IF NOT EXISTS "user_consents_user_type_recorded_idx"
  ON "public"."user_consents" ("user_id", "consent_type", "recorded_at" DESC);
