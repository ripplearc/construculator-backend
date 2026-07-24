-- Project Tags Indexes

-- A tag can be applied to a project at most once. Also serves as the
-- project_id lookup index for the global_search tag-filter EXISTS probe.
CREATE UNIQUE INDEX IF NOT EXISTS "project_tag_uq" ON "public"."project_tags" ("project_id", "tag_id");

-- Supports finding all projects carrying a specific tag.
CREATE INDEX IF NOT EXISTS "project_tags_tag_id_idx" ON "public"."project_tags" ("tag_id");
