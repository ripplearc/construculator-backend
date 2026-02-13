-- Users RLS Policies

ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


-- Owner Full Access Policy
-- Users can fully manage their own profile

CREATE POLICY "users_owner_full_access" ON "public"."users" TO "authenticated" USING (("auth"."uid"() = "credential_id")) WITH CHECK (("auth"."uid"() = "credential_id"));
