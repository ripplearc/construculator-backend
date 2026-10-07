BEGIN;

-- Tests for CA-1271: the Send, PDF shared and cost-file-updated kinds of
-- cost_estimation_activity_type_enum. Pins the full label set against the
-- app's toJson() wire values, and checks each new kind can be written to
-- cost_estimate_logs.

SELECT plan(9);

-- Wire contract: these labels are compared against strings the Flutter
-- client reads and writes (CostEstimationActivityType.toJson). A renamed or
-- reordered label silently turns into `unknown` on the client, so the exact
-- set is pinned. The first 16 are the original values and must not move.
SELECT is(
  (SELECT array_to_string(array_agg(e.enumlabel ORDER BY e.enumsortorder), ',') COLLATE "C"
     FROM pg_enum e
     JOIN pg_type t ON t.oid = e.enumtypid
     WHERE t.typname = 'cost_estimation_activity_type_enum'),
  ('cost_estimation_created,cost_estimation_renamed,cost_estimation_exported,'
   'cost_estimation_locked,cost_estimation_unlocked,cost_estimation_deleted,'
   'cost_item_added,cost_item_edited,cost_item_removed,cost_item_duplicated,'
   'task_assigned,task_unassigned,cost_file_uploaded,cost_file_deleted,'
   'attachment_added,attachment_removed,'
   'cost_estimation_sent,cost_estimation_send_failed,cost_estimation_opened,'
   'cost_estimation_revoked,cost_estimation_approved,'
   'cost_estimation_changes_requested,cost_estimation_pdf_shared,'
   'cost_file_updated') COLLATE "C",
  'cost_estimation_activity_type_enum carries exactly the client wire values, in order'
);

DO $$
DECLARE
  v_user_id uuid := '12710000-0000-0000-0000-000000000001';
  v_credential_id uuid := '12710000-0000-0000-0000-000000000002';
  v_role_id uuid := '12710000-0000-0000-0000-000000000003';
  v_project_id uuid := '12710000-0000-0000-0000-000000000004';
  v_estimate_id uuid := '12710000-0000-0000-0000-000000000005';
BEGIN
  INSERT INTO professional_roles (id, name) VALUES (v_role_id, 'Test Role');
  -- CA-995: users.credential_id FKs to auth.users(id), so a real auth
  -- account has to exist before it can be referenced here.
  INSERT INTO auth.users (
    "instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
    "raw_app_meta_data", "raw_user_meta_data", "created_at", "updated_at",
    "confirmation_token", "recovery_token", "email_change_token_new", "email_change"
  ) VALUES (
    '00000000-0000-0000-0000-000000000000', v_credential_id, 'authenticated', 'authenticated',
    'activity_enum_test@example.com', extensions.crypt('test-fixture-password', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', '{}', now(), now(), '', '', '', ''
  );
  INSERT INTO users (id, credential_id, email, first_name, last_name, professional_role, created_at, user_status, user_preferences, country_code)
    VALUES (v_user_id, v_credential_id, 'activity_enum_test@example.com', 'Enum', 'Test', v_role_id, now(), 'active', '{}', '+1');
  INSERT INTO projects (id, project_name, creator_user_id, created_at, updated_at, project_status)
    VALUES (v_project_id, 'Activity Enum Test Project', v_user_id, now(), now(), 'active');
  INSERT INTO cost_estimates (id, project_id, estimate_name, creator_user_id, markup_type, total_cost, is_locked)
    VALUES (v_estimate_id, v_project_id, 'Activity Enum Test Estimate', v_user_id, 'overall', 0, false);
END $$;

SELECT lives_ok(
  format(
    $$ INSERT INTO cost_estimate_logs (estimate_id, activity, description, user_id, details)
       VALUES ('12710000-0000-0000-0000-000000000005', %L, 'Test log entry',
               '12710000-0000-0000-0000-000000000001', '{}') $$,
    kind
  ),
  format('cost_estimate_logs accepts activity %s', kind)
)
FROM unnest(ARRAY[
  'cost_estimation_sent',
  'cost_estimation_send_failed',
  'cost_estimation_opened',
  'cost_estimation_revoked',
  'cost_estimation_approved',
  'cost_estimation_changes_requested',
  'cost_estimation_pdf_shared',
  'cost_file_updated'
]) AS kind;

SELECT * FROM finish();
ROLLBACK;
