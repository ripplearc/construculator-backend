-- Cost Files Indexes
-- Performance indexes for common query patterns

CREATE INDEX "cost_files_active_idx" ON "public"."cost_files" USING "btree" ("project_id", "is_active_file");


CREATE INDEX "cost_files_project_id_idx" ON "public"."cost_files" USING "btree" ("project_id");


CREATE INDEX "cost_files_uploaded_by_user_id_idx" ON "public"."cost_files" USING "btree" ("uploaded_by_user_id");


CREATE INDEX "cost_files_version_idx" ON "public"."cost_files" USING "btree" ("version");
