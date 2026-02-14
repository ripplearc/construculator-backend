-- Cost Estimates Indexes
-- Performance indexes for common query patterns

CREATE INDEX "cost_estimates_created_at_idx" ON "public"."cost_estimates" USING "btree" ("created_at");


CREATE INDEX "cost_estimates_creator_user_id_idx" ON "public"."cost_estimates" USING "btree" ("creator_user_id");


CREATE INDEX "cost_estimates_deleted_at_idx" ON "public"."cost_estimates" USING "btree" ("deleted_at");


CREATE INDEX "cost_estimates_is_locked_idx" ON "public"."cost_estimates" USING "btree" ("is_locked");


CREATE INDEX "cost_estimates_project_id_idx" ON "public"."cost_estimates" USING "btree" ("project_id");


CREATE INDEX "cost_estimates_updated_at_idx" ON "public"."cost_estimates" USING "btree" ("updated_at");

