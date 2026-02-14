CREATE TYPE "public"."attachment_parent_type_enum" AS ENUM (
    'CostEstimate',
    'Calculation'
);


ALTER TYPE "public"."attachment_parent_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."attachment_type_enum" AS ENUM (
    'Photo',
    'Document'
);


ALTER TYPE "public"."attachment_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."calculation_type_enum" AS ENUM (
    'area',
    'volume',
    'slope'
);


ALTER TYPE "public"."calculation_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."comment_status_enum" AS ENUM (
    'visible',
    'deleted'
);


ALTER TYPE "public"."comment_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."context_type_enum" AS ENUM (
    'project',
    'user_account'
);


ALTER TYPE "public"."context_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."cost_item_type_enum" AS ENUM (
    'material',
    'labor',
    'equipment'
);


ALTER TYPE "public"."cost_item_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."document_category_enum" AS ENUM (
    'Drawing',
    'RFI',
    'Receipts',
    'Other'
);


ALTER TYPE "public"."document_category_enum" OWNER TO "postgres";


CREATE TYPE "public"."general_status_enum" AS ENUM (
    'active',
    'inactive'
);


ALTER TYPE "public"."general_status_enum" OWNER TO "postgres";

CREATE TYPE "public"."labor_calc_method_enum" AS ENUM (
    'per_day',
    'per_hour',
    'per_unit'
);


ALTER TYPE "public"."labor_calc_method_enum" OWNER TO "postgres";


CREATE TYPE "public"."markup_type_enum" AS ENUM (
    'overall',
    'granular'
);


ALTER TYPE "public"."markup_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."markup_value_type_enum" AS ENUM (
    'percentage',
    'amount'
);


ALTER TYPE "public"."markup_value_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."membership_status_enum" AS ENUM (
    'invited',
    'joined',
    'declined'
);


ALTER TYPE "public"."membership_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."notification_read_status_enum" AS ENUM (
    'unread',
    'read'
);


ALTER TYPE "public"."notification_read_status_enum" OWNER TO "postgres";

CREATE TYPE "public"."notification_type_enum" AS ENUM (
    'project_invite',
    'comment_mention',
    'task_assigned',
    'estimate_locked',
    'file_validated',
    'invite_accepted',
    'invite_declined'
);


ALTER TYPE "public"."notification_type_enum" OWNER TO "postgres";

CREATE TYPE "public"."project_status_enum" AS ENUM (
    'active',
    'archived'
);


ALTER TYPE "public"."project_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."storage_provider_enum" AS ENUM (
    'google_drive',
    'one_drive',
    'dropbox'
);


ALTER TYPE "public"."storage_provider_enum" OWNER TO "postgres";


CREATE TYPE "public"."thread_resolution_status_enum" AS ENUM (
    'unresolved',
    'resolved'
);


ALTER TYPE "public"."thread_resolution_status_enum" OWNER TO "postgres";


CREATE TYPE "public"."user_profile_status_enum" AS ENUM (
    'active',
    'inactive'
);


ALTER TYPE "public"."user_profile_status_enum" OWNER TO "postgres";
