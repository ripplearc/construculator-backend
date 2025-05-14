-- Create user_favorites table
CREATE TABLE "user_favorites" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "user_id" uuid NOT NULL REFERENCES "users"("id"),
  "favoritable_type" text NOT NULL,
  "calculation_session_id" uuid REFERENCES "calculation_sessions"("id"),
  "cost_estimate_id" uuid REFERENCES "cost_estimates"("id"),
  "favorited_at" timestamptz NOT NULL DEFAULT (now())
);
