-- Create comment_mentions table
CREATE TABLE "comment_mentions" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "comment_id" uuid NOT NULL REFERENCES "comments"("id"),
  "mentioned_user_id" uuid NOT NULL REFERENCES "users"("id")
);
