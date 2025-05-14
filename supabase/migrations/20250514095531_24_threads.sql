-- Create threads table
CREATE TABLE "threads" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "cost_item_id" uuid NOT NULL REFERENCES "cost_items"("id"),
  "creator_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "last_message_sender_id" uuid NOT NULL REFERENCES "users"("id"),
  "last_message" text NOT NULL,
  "resolution_status" thread_resolution_status_enum NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);
