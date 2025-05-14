-- Create teams table
CREATE TABLE "teams" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "company_id" uuid NOT NULL REFERENCES "companies"("id"),
  "team_name" varchar(150) NOT NULL,
  "description" text,
  "created_by_user_id" uuid REFERENCES "users"("id"),
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE UNIQUE INDEX "company_team_name_uq" ON "teams" ("company_id", "team_name");
CREATE INDEX ON "teams" ("company_id");
CREATE INDEX ON "teams" ("created_by_user_id");
