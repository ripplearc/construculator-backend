-- Create notifications table
CREATE TABLE "notifications" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "recipient_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "triggering_user_id" uuid REFERENCES "users"("id"),
  "related_project_id" uuid REFERENCES "projects"("id"),
  "related_estimate_id" uuid REFERENCES "cost_estimates"("id"),
  "related_cost_item_id" uuid REFERENCES "cost_items"("id"),
  "related_comment_id" uuid REFERENCES "comments"("id"),
  "related_attachment_id" uuid REFERENCES "attachments"("id"),
  "notification_type" notification_type_enum NOT NULL,
  "notification_status" notification_read_status_enum NOT NULL DEFAULT 'unread',
  "status" general_status_enum NOT NULL DEFAULT 'active',
  "created_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE INDEX ON "notifications" ("recipient_user_id");
CREATE INDEX ON "notifications" ("notification_type");
CREATE INDEX ON "notifications" ("notification_status");
CREATE INDEX ON "notifications" ("created_at");
