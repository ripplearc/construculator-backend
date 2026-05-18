-- project_search_history table
-- Per-user search-term log for the dedicated Project Search feature.
-- Powers Project Search's "recent searches" and "suggestions" surfaces.
--
-- Project Search is a separate feature from Global Search:
--   * Global Search (search_history)   — searches across projects/members/estimates
--   * Project Search (this table)      — searches ONLY for projects
-- The two features are fully isolated: neither reads from nor writes to the
-- other's table.

CREATE TABLE IF NOT EXISTS "public"."project_search_history" (
  "id"           uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "user_id"      uuid NOT NULL, -- auth.uid(); no FK (cross-schema boundary with auth.users)
  "search_term"  varchar(255) NOT NULL,
  "has_results"  boolean NOT NULL DEFAULT false,
  "search_count" int NOT NULL DEFAULT 1,
  "created_at"   timestamptz NOT NULL DEFAULT (now()),
  "updated_at"   timestamptz NOT NULL DEFAULT (now())
);

ALTER TABLE "public"."project_search_history" OWNER TO "postgres";
