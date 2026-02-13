# Cost Estimate Logs Module

## Overview

The `cost_estimate_logs` table stores activity and audit logs for cost estimates. Each log entry records a specific action taken on an estimate, who performed it, when it occurred, and additional contextual details.

## Table Structure

### Core Fields
- `id` - UUID primary key
- `estimate_id` - Foreign key to cost_estimates table (CASCADE DELETE)
- `activity` - Type of activity (e.g., 'created', 'updated', 'locked')
- `description` - Human-readable description of what happened
- `user_id` - User who performed the action
- `details` - JSONB field with additional structured data
- `logged_at` - Timestamp when the activity occurred
- `deleted_at` - Soft delete timestamp (NULL = active)

## Business Rules

### 1. Audit Trail
Logs provide an immutable audit trail of all actions on cost estimates:
- Who did what
- When it happened
- What changed (stored in details JSONB)
- Why it happened (description field)

### 2. Soft Delete
- Logs are **never hard deleted** directly
- DELETE operations are converted to soft deletes (sets `deleted_at = now()`)
- Soft-deleted logs are automatically hidden by RLS policy

### 3. Cascade Delete
When a `cost_estimate` is deleted (soft or hard), all its logs are **hard deleted** automatically (ON DELETE CASCADE foreign key constraint).

This ensures orphaned logs are cleaned up when their parent estimate is removed.

### 4. Details Field
The `details` JSONB field stores activity-specific data, such as:
- Field changes: `{"field": "total_cost", "old_value": 1000, "new_value": 1200}`
- Bulk operations: `{"items_added": 5, "items_deleted": 2}`
- Lock information: `{"locked": true, "reason": "final review"}`
- Custom metadata: Any additional context

Format is flexible and can vary per activity type.

## Activity Types

The `activity` field uses the `cost_estimation_activity_type_enum` enum with the following values:

**Cost Estimate Activities:**
- `cost_estimation_created` - Estimate was created
- `cost_estimation_renamed` - Estimate name was changed
- `cost_estimation_exported` - Estimate was exported
- `cost_estimation_locked` - Estimate was locked
- `cost_estimation_unlocked` - Estimate was unlocked
- `cost_estimation_deleted` - Estimate was soft deleted

**Cost Item Activities:**
- `cost_item_added` - Cost item was added
- `cost_item_edited` - Cost item was modified
- `cost_item_removed` - Cost item was soft deleted
- `cost_item_duplicated` - Cost item was duplicated

**Task Activities:**
- `task_assigned` - Task was assigned
- `task_unassigned` - Task was unassigned

**File Activities:**
- `cost_file_uploaded` - Cost file was uploaded
- `cost_file_deleted` - Cost file was deleted

**Attachment Activities:**
- `attachment_added` - Attachment was added
- `attachment_removed` - Attachment was removed

## Permissions

Access to logs typically follows the same permissions as the parent estimate. Users who can view an estimate can view its activity logs.

## Functions

### `log_cost_estimate_activity()`
**Helper function** to create log entries.

**Parameters:**
- `p_estimate_id` - UUID of the estimate
- `p_activity` - Activity type enum value
- `p_description` - Human-readable description
- `p_user_id` - User who performed the action
- `p_details` - JSONB object with additional data (optional, defaults to `{}`)

**Usage:**
```sql
PERFORM log_cost_estimate_activity(
  estimate_id,
  'cost_item_added',
  'Cost item added: 2x4 Lumber',
  user_id,
  jsonb_build_object('costItemId', item_id, 'costItemType', 'material')
);
```

### `cost_estimate_logs_project_permission()`
**Helper function** to check project permissions for logs.

**Parameters:**
- `p_estimate_id` - UUID of the estimate
- `p_permission_key` - Permission to check (e.g., 'get_cost_estimations')

**Behavior:**
- Looks up project_id from the estimate
- Delegates to `user_has_project_permission()`
- Returns false if estimate not found

### `handle_soft_delete_cost_estimate_logs()`
**Trigger function** that runs before DELETE operations.

**Behavior**:
- Intercepts DELETE
- Converts to UPDATE setting `deleted_at = now()`
- Returns NULL (prevents actual DELETE)

## Triggers

1. `trigger_soft_delete_cost_estimate_logs` - BEFORE DELETE
   - Converts hard deletes to soft deletes

## Indexes

Performance indexes for common queries:
- `cost_estimate_logs_estimate_id_idx` - Filter by estimate (most common)
- `cost_estimate_logs_user_id_idx` - Filter by user who performed action
- `cost_estimate_logs_activity_idx` - Filter by activity type
- `cost_estimate_logs_logged_at_idx` - Sort by timestamp
- `cost_estimate_logs_deleted_at_idx` - Filter soft-deleted

## RLS Policies

### Permissive Policies
1. **cost_estimate_logs_select_policy** - View if has `get_cost_estimations` permission
   - Uses `cost_estimate_logs_project_permission()` to check access

### Restrictive Policy (must pass for all operations)
2. **exclude_soft_deleted_logs** - Hides rows where `deleted_at IS NOT NULL`

## Usage Examples

### Creating a Log Entry
```sql
INSERT INTO cost_estimate_logs (
  estimate_id,
  activity,
  description,
  user_id,
  details
) VALUES (
  'estimate-uuid',
  'item_added',
  'Added material item: 2x4 Lumber',
  'user-uuid',
  '{"item_id": "item-uuid", "item_type": "material", "item_name": "2x4 Lumber"}'::jsonb
);
```

### Querying Activity History
```sql
-- Get all logs for an estimate, newest first
SELECT
  logged_at,
  activity,
  description,
  details
FROM cost_estimate_logs
WHERE estimate_id = 'estimate-uuid'
ORDER BY logged_at DESC;
```

### Filtering by Activity Type
```sql
-- Get all lock/unlock events
SELECT *
FROM cost_estimate_logs
WHERE estimate_id = 'estimate-uuid'
  AND activity IN ('locked', 'unlocked')
ORDER BY logged_at;
```

### Tracking Field Changes
```sql
-- Find all updates to total_cost
SELECT
  logged_at,
  user_id,
  details->>'old_value' as old_cost,
  details->>'new_value' as new_cost
FROM cost_estimate_logs
WHERE estimate_id = 'estimate-uuid'
  AND activity = 'updated'
  AND details->>'field' = 'total_cost'
ORDER BY logged_at;
```

### Audit Report
```sql
-- Generate activity summary by user
SELECT
  user_id,
  activity,
  COUNT(*) as action_count,
  MIN(logged_at) as first_action,
  MAX(logged_at) as last_action
FROM cost_estimate_logs
WHERE estimate_id = 'estimate-uuid'
GROUP BY user_id, activity
ORDER BY action_count DESC;
```

## Related Tables

- `cost_estimates` - Parent table (CASCADE DELETE)
- `users` - User who performed the action

## Best Practices

### When to Create Logs
- **Always log**: Creates, deletes, locks, shares
- **Consider logging**: Significant field changes (name, description, total)
- **Maybe skip**: Minor updates like timestamps

### What to Include in Details
- **Old and new values** for field changes
- **Affected items** (IDs, names) for bulk operations
- **Reason or context** when available
- **Related entities** (files, comments, etc.)

### Log Retention
- Logs inherit lifecycle from parent estimate
- When estimate is hard deleted, logs go with it
- For compliance, consider exporting logs before deletion

## Testing

See test files:
- `supabase/tests/database/cost_estimate_logs_test.sql`
- `supabase/tests/database/cost_estimate_activity_logging_test.sql`
- `supabase/tests/database/cascade_delete_test.sql`
