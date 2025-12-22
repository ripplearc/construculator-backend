BEGIN;

-- 1. Setup and Sanity Checks
DO $$
DECLARE
  has_col BOOL;
  has_func BOOL;
  test_role_id UUID := gen_random_uuid();
BEGIN
  -- Insert a role FIRST so the 'has_role' check passes
  INSERT INTO public.professional_roles (id, name) 
  VALUES (test_role_id, 'Test Role');

  -- Check for column existence
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' 
      AND table_name = 'users' 
      AND column_name = 'email'
  ) INTO has_col;

  IF NOT has_col THEN
    RAISE EXCEPTION 'users.email column not found';
  END IF;

  -- Check for function existence
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'check_email_exists'
  ) INTO has_func;

  IF NOT has_func THEN
    RAISE EXCEPTION 'function public.check_email_exists not found';
  END IF;

END;
$$ LANGUAGE plpgsql;

-- Setup: ensure there is at least one professional_role and insert a transient user
WITH maybe_existing AS (
  SELECT id FROM public.professional_roles LIMIT 1
), ensured AS (
  INSERT INTO public.professional_roles (id, name)
  SELECT gen_random_uuid(), 'test-role'
  WHERE NOT EXISTS (SELECT 1 FROM maybe_existing)
  RETURNING id
), role AS (
  SELECT id FROM maybe_existing
  UNION ALL
  SELECT id FROM ensured
)
INSERT INTO public.users (credential_id, email, first_name, last_name, professional_role, profile_photo_url, user_preferences)
VALUES (gen_random_uuid(), 'existing@example.com', 'Test', 'User', (SELECT id FROM role LIMIT 1), NULL, '{}'::jsonb);

-- Plan: 2 assertions
SELECT plan(2);

SELECT ok(public.check_email_exists('existing@example.com') IS TRUE, 'existing@example.com returns true');
SELECT ok(public.check_email_exists('nope@example.com') IS FALSE, 'nope@example.com returns false');

SELECT * FROM finish();

ROLLBACK;

