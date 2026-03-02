-- Cost Items RLS Policies

ALTER TABLE "public"."cost_items" ENABLE ROW LEVEL SECURITY;


-- Restrictive Policy - Hide Soft Deleted
-- Prevents access to soft-deleted items (deleted_at IS NOT NULL)

CREATE POLICY "exclude_soft_deleted_items" ON "public"."cost_items" AS RESTRICTIVE FOR ALL USING (("deleted_at" IS NULL));
