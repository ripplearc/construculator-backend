-- Triggers for user_calculator_stores

-- updated_at is the conflict rule: PowerSync uploads a row with its
-- updated_at and the newer write stands (last write wins per row), so the
-- server stamps it on every UPDATE rather than trusting the client's clock.
CREATE OR REPLACE TRIGGER "set_user_calculator_stores_updated_at"
  BEFORE UPDATE ON "public"."user_calculator_stores"
  FOR EACH ROW EXECUTE FUNCTION "public"."set_current_timestamp_updated_at"();
