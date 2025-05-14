-- Migration: Create all enums and types required by the schema

CREATE TYPE "user_profile_status_enum" AS ENUM (
  'active',
  'inactive'
);

CREATE TYPE "context_type_enum" AS ENUM (
  'project',
  'user_account'
);

CREATE TYPE "project_status_enum" AS ENUM (
  'active',
  'archived'
);

CREATE TYPE "membership_status_enum" AS ENUM (
  'invited',
  'joined',
  'declined'
);

CREATE TYPE "storage_provider_enum" AS ENUM (
  'google_drive',
  'one_drive',
  'dropbox'
);

CREATE TYPE "calculation_type_enum" AS ENUM (
  'area',
  'volume',
  'slope'
);

CREATE TYPE "markup_type_enum" AS ENUM (
  'overall',
  'granular'
);

CREATE TYPE "markup_value_type_enum" AS ENUM (
  'percentage',
  'amount'
);

CREATE TYPE "cost_item_type_enum" AS ENUM (
  'material',
  'labor',
  'equipment'
);

CREATE TYPE "labor_calc_method_enum" AS ENUM (
  'per_day',
  'per_hour',
  'per_unit'
);

CREATE TYPE "thread_resolution_status_enum" AS ENUM (
  'unresolved',
  'resolved'
);

CREATE TYPE "comment_status_enum" AS ENUM (
  'visible',
  'deleted'
);

CREATE TYPE "document_category_enum" AS ENUM (
  'Drawing',
  'RFI',
  'Receipts',
  'Other'
);

CREATE TYPE "attachment_parent_type_enum" AS ENUM (
  'CostEstimate',
  'Calculation'
);

CREATE TYPE "attachment_type_enum" AS ENUM (
  'Photo',
  'Document'
);

CREATE TYPE "general_status_enum" AS ENUM (
  'active',
  'inactive'
);

CREATE TYPE "notification_type_enum" AS ENUM (
  'project_invite',
  'comment_mention',
  'task_assigned',
  'estimate_locked',
  'file_validated',
  'invite_accepted',
  'invite_declined'
);

CREATE TYPE "notification_read_status_enum" AS ENUM (
  'unread',
  'read'
);
