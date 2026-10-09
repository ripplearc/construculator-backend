-- RLS policies for user_calculator_stores
-- Owner only, on every verb. A trade store is personal: no teammate, no
-- project and no company ever reads another user's rates or sheet sizes.
--
-- Keyed on jwt_internal_user_id(), NOT auth.uid(), as user_consents is:
-- auth.uid() returns users.credential_id while user_id here references
-- users.id, so auth.uid() would match nothing and read as "the stores are
-- not syncing" rather than as a bug. The sync stream in
-- powersync/sync-config.yaml filters on the same claim.
--
-- Delete from the app is a soft delete (deleted_at set through an UPDATE).
-- The DELETE policy lets a signed-in client, an API call or an upload, hard
-- delete its own rows and nobody else's; the SQL editor runs as postgres
-- and never passes through it.

ALTER TABLE "public"."user_calculator_stores" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_calculator_stores_select_policy" ON "public"."user_calculator_stores"
  FOR SELECT TO "authenticated"
  USING ("user_id" = "public"."jwt_internal_user_id"());

-- WITH CHECK is what stops a user writing a row in someone else's name.
CREATE POLICY "user_calculator_stores_insert_policy" ON "public"."user_calculator_stores"
  FOR INSERT TO "authenticated"
  WITH CHECK ("user_id" = "public"."jwt_internal_user_id"());

CREATE POLICY "user_calculator_stores_update_policy" ON "public"."user_calculator_stores"
  FOR UPDATE TO "authenticated"
  USING ("user_id" = "public"."jwt_internal_user_id"())
  WITH CHECK ("user_id" = "public"."jwt_internal_user_id"());

CREATE POLICY "user_calculator_stores_delete_policy" ON "public"."user_calculator_stores"
  FOR DELETE TO "authenticated"
  USING ("user_id" = "public"."jwt_internal_user_id"());
