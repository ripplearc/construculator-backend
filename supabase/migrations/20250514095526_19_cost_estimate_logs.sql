-- Create cost_estimate_logs table
CREATE TABLE "cost_estimate_logs" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "estimate_id" uuid NOT NULL REFERENCES "cost_estimates"("id"),
  "activity" varchar NOT NULL,
  "description" text NOT NULL,
  "user_id" uuid NOT NULL REFERENCES "users"("id"),
  "details" jsonb NOT NULL,
  "logged_at" timestamptz NOT NULL DEFAULT (now())
);
