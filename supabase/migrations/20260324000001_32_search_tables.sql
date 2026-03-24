-- Create search_history table (per-user recent searches)
CREATE TABLE "search_history" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "user_id" uuid NOT NULL, -- auth.uid(); no FK (cross-schema boundary with auth.users)
  "search_term" varchar(255) NOT NULL,
  "scope" varchar(50) NOT NULL,
  "search_count" int NOT NULL DEFAULT 1,
  "has_results" boolean NOT NULL DEFAULT false,
  "project_id" uuid REFERENCES "projects"("id") ON DELETE SET NULL,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE UNIQUE INDEX "search_history_user_term_scope_uq" ON "search_history" ("user_id", "search_term", "scope");
CREATE INDEX "search_history_user_id_idx" ON "search_history" ("user_id");
CREATE INDEX "search_history_project_id_idx" ON "search_history" ("project_id");
CREATE INDEX "search_history_has_results_idx" ON "search_history" ("has_results") WHERE has_results = true;
CREATE INDEX "search_history_created_at_idx" ON "search_history" ("created_at");

-- ============================================================
-- ROLLBACK
-- DROP TABLE IF EXISTS "search_history" CASCADE;
-- ============================================================
