-- Create user_favorites table
CREATE TABLE "user_favorites" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "user_id" uuid NOT NULL REFERENCES "users"("id"),
  "favoritable_type" text NOT NULL,
  "calculation_session_id" uuid REFERENCES "calculation_sessions"("id"),
  "cost_estimate_id" uuid REFERENCES "cost_estimates"("id"),
  "favorited_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE UNIQUE INDEX "user_fav_session_uq" ON "user_favorites" ("user_id", "calculation_session_id");
CREATE UNIQUE INDEX "user_fav_estimate_uq" ON "user_favorites" ("user_id", "cost_estimate_id");
CREATE INDEX ON "user_favorites" ("user_id", "favoritable_type");
CREATE INDEX ON "user_favorites" ("calculation_session_id");
CREATE INDEX ON "user_favorites" ("cost_estimate_id");
