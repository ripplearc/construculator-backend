-- Users RLS Policies

ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


-- Select Policy
-- Users can read their own profile

CREATE POLICY "users_select_own" ON "public"."users"
  FOR SELECT TO "authenticated"
  USING (("auth"."uid"() = "credential_id"));


-- Update Policy
-- Users can update their own profile

CREATE POLICY "users_update_own" ON "public"."users"
  FOR UPDATE TO "authenticated"
  USING (("auth"."uid"() = "credential_id"))
  WITH CHECK (("auth"."uid"() = "credential_id"));

-- Insert, Delete, Select, Update (migration 20251218175536_RLS_07_users_table_rules.sql)
-- The migrations create only this one policy on users. The select and update policies above are not in them.
-- The policy "users_owner_full_access" (FOR ALL, authenticated, auth.uid() = credential_id)
-- lets a signed-in user insert, read, update and delete their own row.
-- The app creates the profile row this way. No trigger on auth.users creates it.
-- The AFTER INSERT trigger on this table creates the personal company (07_personal_company_trigger.sql).
