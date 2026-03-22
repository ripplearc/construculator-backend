-- Users Indexes
-- Performance indexes for common query patterns

CREATE INDEX "users_created_at_idx" ON "public"."users" USING "btree" ("created_at");


CREATE INDEX "users_professional_role_idx" ON "public"."users" USING "btree" ("professional_role");


CREATE INDEX "users_user_status_idx" ON "public"."users" USING "btree" ("user_status");


CREATE INDEX "idx_users_credential_id" ON "public"."users" USING "btree" ("credential_id");


CREATE INDEX "idx_users_id_credential" ON "public"."users" USING "btree" ("id", "credential_id");
