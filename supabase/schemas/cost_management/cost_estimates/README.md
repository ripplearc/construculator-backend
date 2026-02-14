# Cost Estimates Module

## Overview

The `cost_estimates` table stores project cost estimates with configurable markup strategies and lock state management. Each estimate belongs to a project and can have either overall markup or granular markup (material/labor/equipment).

## Table Structure

### Core Fields
- `id` - UUID primary key
- `project_id` - Foreign key to projects table
- `estimate_name` - Display name for the estimate
- `estimate_description` - Optional detailed description
- `creator_user_id` - User who created the estimate

### Markup Configuration
- `markup_type` - Enum: 'overall' or 'granular'
- **Overall Markup** (when markup_type = 'overall'):
  - `overall_markup_value_type` - 'percentage' or 'amount'
  - `overall_markup_value` - The markup value
- **Granular Markup** (when markup_type = 'granular'):
  - `material_markup_value_type` + `material_markup_value`
  - `labor_markup_value_type` + `labor_markup_value`
  - `equipment_markup_value_type` + `equipment_markup_value`

### Lock State
- `is_locked` - Boolean flag
- `locked_by_user_id` - User who locked the estimate
- `locked_at` - Timestamp when locked

### Metadata
- `total_cost` - Calculated total cost (decimal 18,2)
- `created_at` - Creation timestamp
- `updated_at` - Last update timestamp
- `deleted_at` - Soft delete timestamp (NULL = active)

## Business Rules

### 1. Immutable Fields
The following fields **cannot be modified** after creation:
- `id`
- `project_id`
- `creator_user_id`
- `locked_by_user_id` (managed by trigger)
- `locked_at` (managed by trigger)
- `markup_type`
- All markup value fields
- `total_cost`
- `created_at`

Attempts to modify these fields will raise an exception.

### 2. Soft Delete
- Estimates are **never hard deleted**
- DELETE operations are converted to soft deletes (sets `deleted_at = now()`)
- Soft-deleted estimates are automatically hidden by RLS policy
- Related records are cleaned up on soft delete (see Cascade Behavior)

### 3. Locking Mechanism
- Estimates can be locked to prevent modifications
- Only users with `lock_cost_estimation` permission can lock/unlock
- When locked:
  - `is_locked` = true
  - `locked_by_user_id` = current user's ID (auto-populated)
  - `locked_at` = current timestamp (auto-populated)
- When unlocked:
  - `is_locked` = false
  - `locked_by_user_id` = NULL
  - `locked_at` = NULL

### 4. Cascade Delete Behavior
When an estimate is soft deleted, the following happens automatically:
- **Hard deletes**:
  - All `cost_items` for this estimate
  - All `cost_estimate_logs` for this estimate
  - All `user_favorites` referencing this estimate
- **Soft deletes** (status = 'inactive'):
  - All `attachments` for this estimate

## Permissions

All operations require specific project permissions:

| Operation | Required Permission |
|-----------|-------------------|
| SELECT (view) | `get_cost_estimations` |
| INSERT (create) | `add_cost_estimation` |
| UPDATE (edit) | `edit_cost_estimation` |
| UPDATE (delete_at) | `delete_cost_estimation` |
| UPDATE (lock) | `lock_cost_estimation` |
| DELETE | `delete_cost_estimation` |

Permissions are checked via `user_has_project_permission()` function.

## Functions

### `check_cost_estimate_update_permissions()`
**Trigger function** that runs before UPDATE operations.

**Responsibilities**:
1. Enforce immutable column restrictions
2. Check `delete_cost_estimation` permission for soft deletes
3. Check `lock_cost_estimation` permission for lock changes
4. Auto-populate `locked_by_user_id` and `locked_at` when locking
5. Auto-clear lock fields when unlocking
6. Update `updated_at` timestamp

### `handle_soft_delete_cost_estimates()`
**Trigger function** that runs before DELETE operations.

**Behavior**:
- Intercepts DELETE
- Converts to UPDATE setting `deleted_at = now()`
- Returns NULL (prevents actual DELETE)

### `handle_delete_cost_estimates()`
**Trigger function** that runs after soft delete (UPDATE with deleted_at).

**Responsibilities**:
- Delete related cost_items
- Delete related cost_estimate_logs
- Delete related user_favorites
- Mark related attachments as inactive

## Triggers

1. `trigger_check_cost_estimate_update_permissions` - BEFORE UPDATE
   - Enforces business rules on updates

2. `trigger_soft_delete_cost_estimates` - BEFORE DELETE
   - Converts hard deletes to soft deletes

3. `trigger_handle_delete_cost_estimates` - AFTER UPDATE
   - Cleans up related records when soft deleted

## Indexes

Performance indexes for common queries:
- `cost_estimates_project_id_idx` - Filter by project
- `cost_estimates_creator_user_id_idx` - Filter by creator
- `cost_estimates_is_locked_idx` - Filter by lock state
- `cost_estimates_deleted_at_idx` - Filter soft-deleted
- `cost_estimates_created_at_idx` - Sort by creation date
- `cost_estimates_updated_at_idx` - Sort by update date

## RLS Policies

### Permissive Policies (any can grant access)
1. **cost_estimates_select_policy** - View if has `get_cost_estimations`
2. **cost_estimates_insert_policy** - Create if has `add_cost_estimation`
3. **cost_estimates_update_policy** - Edit if has `edit_cost_estimation`
4. **cost_estimates_delete_policy** - Delete if has `delete_cost_estimation`

### Restrictive Policy (must pass for all operations)
5. **exclude_soft_deleted_estimates** - Hides rows where `deleted_at IS NOT NULL`

## Usage Examples

### Creating an Estimate
```sql
INSERT INTO cost_estimates (
  project_id,
  estimate_name,
  creator_user_id,
  markup_type,
  overall_markup_value_type,
  overall_markup_value
) VALUES (
  'project-uuid',
  'Kitchen Renovation',
  'user-uuid',
  'overall',
  'percentage',
  15.00
);
```

### Locking an Estimate
```sql
-- Requires lock_cost_estimation permission
UPDATE cost_estimates
SET is_locked = true
WHERE id = 'estimate-uuid';

-- locked_by_user_id and locked_at are auto-populated by trigger
```

### Soft Deleting an Estimate
```sql
-- Either approach works (both result in soft delete)

-- Approach 1: UPDATE
UPDATE cost_estimates
SET deleted_at = now()
WHERE id = 'estimate-uuid';

-- Approach 2: DELETE (converted to soft delete by trigger)
DELETE FROM cost_estimates
WHERE id = 'estimate-uuid';
```

## Related Tables

- `projects` - Parent table (via project_id)
- `users` - Creator and lock owner (via creator_user_id, locked_by_user_id)
- `cost_items` - Child table (cascade deleted)
- `cost_estimate_logs` - Activity logs (cascade deleted)
- `user_favorites` - User favorites (cascade deleted)
- `attachments` - File attachments (soft deleted)
- `notifications` - Related notifications (cascade deleted)

## Testing

See test files:
- `supabase/tests/database/cost_estimates_test.sql`
- `supabase/tests/database/cost_estimates_update_guard_test.sql`
- `supabase/tests/database/cascade_delete_test.sql`
