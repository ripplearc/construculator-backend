-- Create comment_mentions table
CREATE TABLE "comment_mentions" (
  "id" uuid PRIMARY KEY DEFAULT (gen_random_uuid()),
  "comment_id" uuid NOT NULL REFERENCES "comments"("id"),
  "mentioned_user_id" uuid NOT NULL REFERENCES "users"("id"),
  "created_at" timestamptz NOT NULL DEFAULT (now())
);

CREATE UNIQUE INDEX "comment_mention_uq" ON "comment_mentions" ("comment_id", "mentioned_user_id");
CREATE INDEX ON "comment_mentions" ("comment_id");
CREATE INDEX ON "comment_mentions" ("mentioned_user_id");
