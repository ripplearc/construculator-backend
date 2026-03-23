-- Cost Files RLS Policies

-- RLS is intentionally enabled here to enforce default-deny.
-- Permissive policies will be added in a PR related to this pariticular feature

ALTER TABLE "public"."cost_files" ENABLE ROW LEVEL SECURITY;
