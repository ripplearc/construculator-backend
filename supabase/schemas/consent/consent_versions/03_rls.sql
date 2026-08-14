-- RLS policies for consent_versions
-- Read-only for clients. No INSERT/UPDATE/DELETE policy for any role: the
-- absence is the enforcement point, since auto-expose (CA-729) grants the Data
-- API roles full SQL access. service_role bypasses RLS, which is how the seed
-- migration writes. Reads are unscoped — the terms are the same document for
-- everyone. See README.md.

ALTER TABLE "public"."consent_versions" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "consent_versions_select_policy" ON "public"."consent_versions"
  FOR SELECT TO "authenticated"
  USING (true);
