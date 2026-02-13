-- Cost Items Indexes
-- Performance indexes for common query patterns

CREATE INDEX "cost_items_created_at_idx" ON "public"."cost_items" USING "btree" ("created_at");


CREATE INDEX "cost_items_deleted_at_idx" ON "public"."cost_items" USING "btree" ("deleted_at");


CREATE INDEX "cost_items_estimate_id_idx" ON "public"."cost_items" USING "btree" ("estimate_id");


CREATE INDEX "cost_items_item_type_idx" ON "public"."cost_items" USING "btree" ("item_type");


CREATE INDEX "cost_items_updated_at_idx" ON "public"."cost_items" USING "btree" ("updated_at");
