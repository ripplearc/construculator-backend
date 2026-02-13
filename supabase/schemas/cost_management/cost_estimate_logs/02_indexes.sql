-- Cost Estimate Logs Indexes
-- Performance indexes for common query patterns

CREATE INDEX "cost_estimate_logs_activity_idx" ON "public"."cost_estimate_logs" USING "btree" ("activity");


CREATE INDEX "cost_estimate_logs_deleted_at_idx" ON "public"."cost_estimate_logs" USING "btree" ("deleted_at");


CREATE INDEX "cost_estimate_logs_estimate_id_idx" ON "public"."cost_estimate_logs" USING "btree" ("estimate_id");


CREATE INDEX "cost_estimate_logs_logged_at_idx" ON "public"."cost_estimate_logs" USING "btree" ("logged_at");


CREATE INDEX "cost_estimate_logs_user_id_idx" ON "public"."cost_estimate_logs" USING "btree" ("user_id");
