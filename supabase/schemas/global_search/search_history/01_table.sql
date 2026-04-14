-- search_history table
-- Stores per-user search terms with scope, frequency, and result metadata.
-- Powers recent searches and personalised suggestions.

CREATE TABLE IF NOT EXISTS "public"."search_history" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "user_id" uuid NOT NULL, -- auth.uid(); no FK (cross-schema boundary with auth.users)
  "search_term" varchar(255) NOT NULL,
  "scope" varchar(50) NOT NULL,
  "search_count" int NOT NULL DEFAULT 1,
  "has_results" boolean NOT NULL DEFAULT false,
  "project_id" uuid REFERENCES "public"."projects"("id") ON DELETE SET NULL,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

ALTER TABLE "public"."search_history" OWNER TO "postgres";
