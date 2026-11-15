-- CA-1207: let a company member delete a saved rate.
--
-- your_rates had RLS on and no DELETE policy, on purpose, because neither
-- Decision 55 nor the first ticket mentioned deleting a saved rate. Settled
-- Decision 8 (2026-10-28) now says any company member can delete one.
--
-- The app needs it for the undo of a late save. A Your rates save that takes
-- more than 2 seconds counts as failed. If the phone finishes the write later,
-- the app deletes the row on the phone again. PowerSync uploads the insert and
-- then the delete. With no DELETE policy Postgres deleted 0 rows and returned
-- no error, so the server kept the row and the next sync put it back on every
-- phone of the company, although the user had been told it was not saved.
--
-- Mirrors supabase/schemas/cost_management/your_rates/05_rls.sql.

CREATE POLICY "your_rates_delete_policy" ON "public"."your_rates"
    FOR DELETE
    TO "authenticated"
    USING ("public"."jwt_user_is_company_member"("company_id"));
