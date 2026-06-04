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

-- Note: INSERT is intentionally excluded here.
-- User profile creation is handled by a trusted AFTER INSERT trigger on auth.users,
-- not by open RLS, to prevent duplicate profile rows.
