-- Your Rates RLS Policies
--
-- Scoped per company (Decision 37), via the jwt_user_is_company_member()
-- helper (supabase/schemas/_shared/01_functions.sql). Any membership, any
-- role -- the ticket doesn't gate "Your rates" access by role.

ALTER TABLE "public"."your_rates" ENABLE ROW LEVEL SECURITY;


-- SELECT Policy
-- A company member can view their company's saved rates.

CREATE POLICY "your_rates_select_policy" ON "public"."your_rates"
    FOR SELECT
    TO "authenticated"
    USING ("public"."jwt_user_is_company_member"("company_id"));


-- INSERT Policy
-- A company member can save a rate for their own company.

CREATE POLICY "your_rates_insert_policy" ON "public"."your_rates"
    FOR INSERT
    TO "authenticated"
    WITH CHECK ("public"."jwt_user_is_company_member"("company_id"));


-- UPDATE Policy
-- A company member can update their company's saved rates, and cannot
-- retarget a row to a company they don't belong to (both USING and
-- WITH CHECK, matching cost_estimates_update_policy's two-clause pattern).

CREATE POLICY "your_rates_update_policy" ON "public"."your_rates"
    FOR UPDATE
    TO "authenticated"
    USING ("public"."jwt_user_is_company_member"("company_id"))
    WITH CHECK ("public"."jwt_user_is_company_member"("company_id"));


-- DELETE Policy
-- A company member can delete their company's saved rates (Settled Decision 8,
-- 2026-10-28). The app needs it to undo a save that finished after the 2 second
-- limit: without the policy the server deleted 0 rows with no error and the
-- row came back on the next sync.

CREATE POLICY "your_rates_delete_policy" ON "public"."your_rates"
    FOR DELETE
    TO "authenticated"
    USING ("public"."jwt_user_is_company_member"("company_id"));
