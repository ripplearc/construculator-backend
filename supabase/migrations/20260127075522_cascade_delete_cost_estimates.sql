-- Add cascading deletes and cleanup trigger for cost_estimates

-- Adjust foreign keys to cascade delete where appropriate
ALTER TABLE "cost_items" DROP CONSTRAINT IF EXISTS "cost_items_estimate_id_fkey";
ALTER TABLE "cost_items"
	ADD CONSTRAINT "cost_items_estimate_id_fkey"
	FOREIGN KEY ("estimate_id") REFERENCES "cost_estimates"("id") ON DELETE CASCADE;

ALTER TABLE "cost_estimate_logs" DROP CONSTRAINT IF EXISTS "cost_estimate_logs_estimate_id_fkey";
ALTER TABLE "cost_estimate_logs"
	ADD CONSTRAINT "cost_estimate_logs_estimate_id_fkey"
	FOREIGN KEY ("estimate_id") REFERENCES "cost_estimates"("id") ON DELETE CASCADE;

ALTER TABLE "user_favorites" DROP CONSTRAINT IF EXISTS "user_favorites_cost_estimate_id_fkey";
ALTER TABLE "user_favorites"
	ADD CONSTRAINT "user_favorites_cost_estimate_id_fkey"
	FOREIGN KEY ("cost_estimate_id") REFERENCES "cost_estimates"("id") ON DELETE CASCADE;

ALTER TABLE "attachments" DROP CONSTRAINT IF EXISTS "attachments_cost_estimate_id_fkey";
ALTER TABLE "attachments"
	ADD CONSTRAINT "attachments_cost_estimate_id_fkey"
	FOREIGN KEY ("cost_estimate_id") REFERENCES "cost_estimates"("id") ON DELETE SET NULL;

ALTER TABLE "notifications" DROP CONSTRAINT IF EXISTS "notifications_related_estimate_id_fkey";
ALTER TABLE "notifications"
	ADD CONSTRAINT "notifications_related_estimate_id_fkey"
	FOREIGN KEY ("related_estimate_id") REFERENCES "cost_estimates"("id") ON DELETE CASCADE;
