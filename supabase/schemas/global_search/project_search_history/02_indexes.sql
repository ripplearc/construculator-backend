-- Indexes for project_search_history

-- Unique constraint: drives upsert conflict resolution (user_id, search_term)
CREATE UNIQUE INDEX IF NOT EXISTS "project_search_history_user_term_uq"
  ON "public"."project_search_history" ("user_id", "search_term");

CREATE INDEX IF NOT EXISTS "project_search_history_user_id_idx"
  ON "public"."project_search_history" ("user_id");

-- Partial index: only indexes rows where suggestions are eligible.
-- Covers the WHERE has_results = true predicate in get_project_search_suggestions.
CREATE INDEX IF NOT EXISTS "project_search_history_has_results_idx"
  ON "public"."project_search_history" ("has_results") WHERE has_results = true;

-- Supports the recent-searches surface (ORDER BY updated_at DESC).
CREATE INDEX IF NOT EXISTS "project_search_history_updated_at_idx"
  ON "public"."project_search_history" ("updated_at");
