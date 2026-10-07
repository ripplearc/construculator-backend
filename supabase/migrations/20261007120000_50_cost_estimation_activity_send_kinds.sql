-- CA-1271: Add the Send, PDF shared and cost-file-updated kinds to
-- cost_estimation_activity_type_enum.
--
-- CA-1147 added these kinds to the app's CostEstimationActivityType. Until
-- the enum carries them, no row of these kinds can be written, and the app
-- reads any it meets as `unknown`. Each label must equal the app's toJson()
-- output (snake_case of the Dart member name), pinned by
-- test/features/estimations/units/domain/entities/cost_estimation_activity_type_test.dart
-- in construculator-app.
--
-- This only adds values; nothing writes these rows yet. CA-1192 writes
-- cost_file_updated and CUJ 8 (CA-1177) writes the Send kinds.
--
-- ADD VALUE appends after the existing 16 labels, so their order and every
-- existing row are untouched. Postgres can't drop an enum value, so there is
-- no rollback short of recreating the type.
--
-- Written by hand: config.toml declares schema_paths = [], so there is no
-- declared schema to diff against. Mirrors supabase/schemas/_types/enums.sql.
-- https://ripplearc.youtrack.cloud/issue/CA-1271

ALTER TYPE "public"."cost_estimation_activity_type_enum" ADD VALUE 'cost_estimation_sent';
ALTER TYPE "public"."cost_estimation_activity_type_enum" ADD VALUE 'cost_estimation_send_failed';
ALTER TYPE "public"."cost_estimation_activity_type_enum" ADD VALUE 'cost_estimation_opened';
ALTER TYPE "public"."cost_estimation_activity_type_enum" ADD VALUE 'cost_estimation_revoked';
ALTER TYPE "public"."cost_estimation_activity_type_enum" ADD VALUE 'cost_estimation_approved';
ALTER TYPE "public"."cost_estimation_activity_type_enum" ADD VALUE 'cost_estimation_changes_requested';
ALTER TYPE "public"."cost_estimation_activity_type_enum" ADD VALUE 'cost_estimation_pdf_shared';
ALTER TYPE "public"."cost_estimation_activity_type_enum" ADD VALUE 'cost_file_updated';
