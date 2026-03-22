-- Professional Roles Triggers

-- Update Timestamp
-- Automatically updates updated_at column on row modification
CREATE OR REPLACE TRIGGER "trigger_update_professional_roles_updated_at"
    BEFORE UPDATE ON "public"."professional_roles"
    FOR EACH ROW
    EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();
