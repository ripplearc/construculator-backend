# Cost Items Module

## Overview

The `cost_items` table stores individual line items within cost estimates. Each item represents a material, labor, or equipment cost with detailed pricing and calculation information.

## Table Structure

### Core Fields
- `id` - UUID primary key
- `estimate_id` - Foreign key to cost_estimates table (CASCADE DELETE)
- `item_type` - Enum: 'material', 'labor', or 'equipment'
- `item_name` - Display name for the item
- `item_total_cost` - Calculated total cost (decimal 18,2)
- `currency` - Currency code (e.g., 'USD')

### Pricing Fields
- `unit_price` - Price per unit (decimal 18,4)
- `quantity` - Quantity of units (decimal 18,4)
- `unit_measurement` - Unit of measurement (e.g., 'sqft', 'hours', 'each')
- `calculation` - JSONB field storing calculation details

### Material-Specific Fields
- `brand` - Product brand name
- `product_link` - URL to product page
- `description` - Additional details

### Labor-Specific Fields
- `labor_calc_method` - Enum: 'per_day', 'per_hour', or 'per_unit'
- `labor_days` - Number of days (decimal 10,2)
- `labor_hours` - Number of hours (decimal 10,2)
- `labor_unit_type` - Custom unit type for labor
- `labor_unit_value` - Value per custom unit (decimal 18,4)
- `crew_size` - Number of workers

### Metadata
- `created_at` - Creation timestamp
- `updated_at` - Last update timestamp
- `deleted_at` - Soft delete timestamp (NULL = active)

## Business Rules

### 1. Item Types
Three types of cost items are supported:

**Material**:
- Physical products/supplies
- Uses: `unit_price`, `quantity`, `unit_measurement`
- Optional: `brand`, `product_link`

**Labor**:
- Worker costs
- Uses: `labor_calc_method`, `labor_days`, `labor_hours`, etc.
- May have `crew_size` for multiple workers

**Equipment**:
- Machinery/tool costs
- Uses: `unit_price`, `quantity`, `unit_measurement`

### 2. Soft Delete
- Cost items are **never hard deleted**
- DELETE operations are converted to soft deletes (sets `deleted_at = now()`)
- Soft-deleted items are automatically hidden by RLS policy

### 3. Cascade Delete
When a `cost_estimate` is hard deleted (may be for cleanup purpose), all its `cost_items` are **hard deleted** automatically (ON DELETE CASCADE foreign key constraint).

This happens because:
1. Items are tightly coupled to estimates
2. No need to keep orphaned items
3. Cleanup is handled at the estimate level

### 4. Calculation Field
The `calculation` JSONB field stores detailed calculation data, which may include:
- Formula used
- Breakdown of costs
- Intermediate values
- Custom fields per item type

Format is flexible and can be extended as needed.

## Permissions

Cost items inherit permissions from their parent estimate. Access control is enforced at the **cost_estimates level**, not at the item level.

Users with access to a cost estimate can:
- View all items in that estimate
- Create new items in that estimate
- Update items in that estimate
- Delete items from that estimate

## Functions

### `handle_soft_delete_cost_items()`
**Trigger function** that runs before DELETE operations.

**Behavior**:
- Intercepts DELETE
- Converts to UPDATE setting `deleted_at = now()`
- Returns NULL (prevents actual DELETE)

### `log_cost_item_added()`
**Trigger function** that runs after INSERT operations.

**Behavior**:
- Automatically logs item addition to `cost_estimate_logs`
- Records item name, type, and description
- Determines user from auth.uid() or estimate creator

### `log_cost_item_edited()`
**Trigger function** that runs after UPDATE when item fields change.

**Behavior**:
- Logs all field changes with old and new values
- Uses single-pass jsonb aggregation for performance
- Only logs when actual changes detected
- Excludes metadata fields (id, created_at, etc.)
- Stores changes in `editedFields` object with oldValue/newValue pairs

### `log_cost_item_removed()`
**Trigger function** that runs after soft delete (UPDATE with deleted_at).

**Behavior**:
- Logs item removal to `cost_estimate_logs`
- Records item name and type
- Determines user from auth.uid() or estimate creator

## Triggers

1. `trigger_soft_delete_cost_items` - BEFORE DELETE
   - Converts hard deletes to soft deletes

2. `trigger_log_cost_item_added` - AFTER INSERT
   - Automatically logs item addition activity

3. `trigger_log_cost_item_edited` - AFTER UPDATE
   - Logs field changes when any tracked field is modified
   - Tracks 17 fields: item_type, item_name, unit_price, quantity, unit_measurement, calculation, item_total_cost, currency, brand, product_link, description, and all labor fields

4. `trigger_log_cost_item_removed` - AFTER UPDATE
   - Logs removal activity when item is soft deleted
   - Only fires when deleted_at is set

## Indexes

Performance indexes for common queries:
- `cost_items_estimate_id_idx` - Filter by estimate (most common)
- `cost_items_item_type_idx` - Filter by type (material/labor/equipment)
- `cost_items_deleted_at_idx` - Filter soft-deleted
- `cost_items_created_at_idx` - Sort by creation date
- `cost_items_updated_at_idx` - Sort by update date

## RLS Policies

### Restrictive Policy (must pass for all operations)
1. **exclude_soft_deleted_items** - Hides rows where `deleted_at IS NOT NULL`

**Note**: There are no permissive policies at the item level. Access control happens at the parent `cost_estimates` table level through RLS policies there.

## Usage Examples

### Creating a Material Item
```sql
INSERT INTO cost_items (
  estimate_id,
  item_type,
  item_name,
  unit_price,
  quantity,
  unit_measurement,
  calculation,
  item_total_cost,
  currency,
  brand,
  product_link
) VALUES (
  'estimate-uuid',
  'material',
  '2x4 Lumber',
  8.50,
  100,
  'board',
  '{"formula": "unit_price * quantity", "breakdown": {"unit_price": 8.50, "quantity": 100}}'::jsonb,
  850.00,
  'USD',
  'Home Depot',
  'https://example.com/product'
);
```

### Creating a Labor Item
```sql
INSERT INTO cost_items (
  estimate_id,
  item_type,
  item_name,
  labor_calc_method,
  labor_hours,
  unit_price,
  crew_size,
  calculation,
  item_total_cost,
  currency
) VALUES (
  'estimate-uuid',
  'labor',
  'Framing Labor',
  'per_hour',
  40.0,
  45.00,
  2,
  '{"formula": "labor_hours * unit_price * crew_size", "breakdown": {"hours": 40, "rate": 45, "crew": 2}}'::jsonb,
  3600.00,
  'USD'
);
```

### Soft Deleting an Item
```sql
-- Either approach works (both result in soft delete)

-- Approach 1: UPDATE
UPDATE cost_items
SET deleted_at = now()
WHERE id = 'item-uuid';

-- Approach 2: DELETE (converted to soft delete by trigger)
DELETE FROM cost_items
WHERE id = 'item-uuid';
```

### Querying Items by Type
```sql
-- Get all material items for an estimate
SELECT *
FROM cost_items
WHERE estimate_id = 'estimate-uuid'
  AND item_type = 'material'
ORDER BY created_at;

-- Calculate total by type
SELECT
  item_type,
  SUM(item_total_cost) as type_total
FROM cost_items
WHERE estimate_id = 'estimate-uuid'
GROUP BY item_type;
```

## Related Tables

- `cost_estimates` - Parent table (CASCADE DELETE)
- `task_assignments` - Tasks assigned to cost items
- `threads` - Discussion threads about items
- `notifications` - Related notifications

## Testing

See test files:
- `supabase/tests/database/cost_items_test.sql`
- `supabase/tests/database/cascade_delete_test.sql`
