-- CA-995: Add the missing FK from public.users.credential_id to
-- auth.users.id.
--
-- CA-749's independent review (PR #51) found that nothing enforced this
-- reference: a hand-inserted public.users row could silently point at a
-- nonexistent auth account. PR #51 fixed the seeded sample user (real
-- auth.users/auth.identities rows plus a regression test), but the class of
-- bug stayed creatable by anyone who wrote a public.users row by hand. This
-- closes that gap for every row, not just the seeded one.
--
-- ON DELETE CASCADE: matches this repo's convention for FKs where the child
-- row is owned by and has no life outside its parent (see
-- project_tags_project_id_fkey, project_tags_tag_id_fkey,
-- cost_estimate_logs_estimate_id_fkey, cost_items_estimate_id_fkey — all
-- ON DELETE CASCADE). A users row has no meaning once its auth.users account
-- is gone: credential_id is unique and required, so the relationship is
-- exactly one-to-one, and there is no scenario where the profile should
-- outlive its own credential.
--
-- Written by hand rather than via `supabase db diff`: config.toml declares
-- schema_paths = [], so the CLI has no declared schema to diff against (same
-- reason migrations 41-43 were hand-written). Mirrors the FK added to
-- supabase/schemas/core/users/01_table.sql — keep the two in step.
-- https://ripplearc.youtrack.cloud/issue/CA-995

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_credential_id_fkey" FOREIGN KEY ("credential_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
