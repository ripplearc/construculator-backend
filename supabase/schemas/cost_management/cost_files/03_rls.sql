-- Cost Files RLS Policies

-- RLS is intentionally enabled here to enforce default-deny.
-- TODO: [CA-298] https://ripplearc.youtrack.cloud/issue/CA-298
-- Permissive policies will be added in a PR related to this particular feature

ALTER TABLE "public"."cost_files" ENABLE ROW LEVEL SECURITY;
