-- Users Indexes
-- Performance indexes for common query patterns

CREATE INDEX "users_professional_role_idx" ON "public"."users" USING "btree" ("professional_role");


CREATE INDEX "users_user_status_idx" ON "public"."users" USING "btree" ("user_status");


CREATE INDEX "users_created_at_idx" ON "public"."users" USING "btree" ("created_at");


-- Case-insensitive email lookups (member invite RPCs, CA-807)
CREATE INDEX "idx_users_email_lower" ON "public"."users" (lower("email"));
