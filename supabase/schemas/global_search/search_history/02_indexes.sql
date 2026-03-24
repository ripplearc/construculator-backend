-- Indexes for search_history

-- Unique constraint: drives upsert conflict resolution (user/term/scope)
CREATE UNIQUE INDEX IF NOT EXISTS "search_history_user_term_scope_uq"
  ON "public"."search_history" ("user_id", "search_term", "scope");

CREATE INDEX IF NOT EXISTS "search_history_user_id_idx"
  ON "public"."search_history" ("user_id");

CREATE INDEX IF NOT EXISTS "search_history_project_id_idx"
  ON "public"."search_history" ("project_id");

-- Partial index: only indexes rows where suggestions are eligible.
-- Covers the WHERE has_results = true predicate in get_search_suggestions.
CREATE INDEX IF NOT EXISTS "search_history_has_results_idx"
  ON "public"."search_history" ("has_results") WHERE has_results = true;

CREATE INDEX IF NOT EXISTS "search_history_created_at_idx"
  ON "public"."search_history" ("created_at");
