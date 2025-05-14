-- Create comments table
CREATE TABLE "comments" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "thread_id" uuid NOT NULL REFERENCES "threads"("id"),
  "parent_comment_id" uuid REFERENCES "comments"("id"),
  "author_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "content" text NOT NULL,
  "status" comment_status_enum NOT NULL DEFAULT 'visible',
  "created_at" timestamptz NOT NULL DEFAULT (now()),
  "updated_at" timestamptz NOT NULL DEFAULT (now())
);
