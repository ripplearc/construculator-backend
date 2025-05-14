-- Create task_assignments table
CREATE TABLE "task_assignments" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "cost_item_id" uuid NOT NULL REFERENCES "cost_items"("id"),
  "assignee_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "assigned_by_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "assigned_at" timestamptz NOT NULL DEFAULT (now()),
  "status_updated_at" timestamptz NOT NULL DEFAULT (now()),
  "completed_at" timestamptz,
  "task_description" text
);

CREATE UNIQUE INDEX "cost_item_assignee_uq" ON "task_assignments" ("cost_item_id", "assignee_user_id");
CREATE INDEX ON "task_assignments" ("assignee_user_id");
CREATE INDEX ON "task_assignments" ("assigned_by_user_id");
