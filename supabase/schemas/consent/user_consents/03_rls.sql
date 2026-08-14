-- RLS policies for user_consents
-- Personal ownership on read and insert; no update or delete path for anyone,
-- which is what makes the table append-only. Withdrawal is an INSERT of a
-- 'withdrawn' row, never an UPDATE of the acceptance it supersedes.
--
-- Keyed on jwt_internal_user_id(), NOT auth.uid(): auth.uid() returns
-- users.credential_id while user_id here references users.id, so auth.uid()
-- would match nothing and read as "consent isn't syncing" rather than as a bug.
-- See README.md.

ALTER TABLE "public"."user_consents" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_consents_select_policy" ON "public"."user_consents"
  FOR SELECT TO "authenticated"
  USING ("user_id" = "public"."jwt_internal_user_id"());

-- WITH CHECK is what stops a user recording consent in someone else's name.
CREATE POLICY "user_consents_insert_policy" ON "public"."user_consents"
  FOR INSERT TO "authenticated"
  WITH CHECK ("user_id" = "public"."jwt_internal_user_id"());
