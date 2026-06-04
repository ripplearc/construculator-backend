# Professional Roles Module

## Overview

The `professional_roles` table is a lookup/reference table that defines available professional roles or occupations for users. Examples include "General Contractor", "Architect", "Project Manager", etc.

## Table Structure

### Core Fields
- `id` - UUID primary key
- `name` - Role name (unique)

### Metadata
- `created_at` - Role creation timestamp
- `updated_at` - Last update timestamp

## Business Rules

### 1. Role Name Uniqueness
- Each role name must be unique
- Prevents duplicate role definitions
- Names should be in title case (e.g., "General Contractor", not "general contractor")

### 2. Reference Data
This is a **reference/lookup table**:
- Relatively static data (doesn't change frequently)
- Seeded during database initialization
- Used for dropdowns, filters, and categorization
- Should not be user-editable in most cases

### 3. Immutability Considerations
Once a role is assigned to users:
- Deleting it would orphan user records (FK constraint prevents this)
- Renaming should be done carefully
- Consider adding new roles instead of modifying existing ones

## Indexes

No additional indexes beyond:
- Primary key on `id`
- Unique constraint on `name`

Sufficient for:
- Lookup by ID (used in users.professional_role FK)
- Lookup by name (for display, dropdowns)
- Small table size makes full scans acceptable

## RLS Policies

### Public SELECT Policy
**Name**: `professional_roles_select_public`

**Rule**: `USING (true)`

**Behavior**:
- Anyone (including unauthenticated users) can view all roles
- Needed for signup flow (user selects their role)
- No sensitive data in this table

**Other Operations**:
- INSERT/UPDATE/DELETE not permitted via RLS
- Should only be done via migrations or admin functions
- Maintains data integrity

## Usage Examples

### Viewing All Available Roles
```sql
SELECT id, name
FROM professional_roles
ORDER BY name;
```

### Getting a Specific Role
```sql
SELECT *
FROM professional_roles
WHERE name = 'General Contractor';
```

### Using in User Signup
```sql
-- First, get available roles for dropdown
SELECT id, name
FROM professional_roles
ORDER BY name;

-- Then, create user with selected role
INSERT INTO users (
  credential_id,
  email,
  first_name,
  last_name,
  professional_role,
  user_preferences
) VALUES (
  auth.uid(),
  'user@example.com',
  'John',
  'Doe',
  'role-uuid-from-dropdown',
  '{}'::jsonb
);
```

### Counting Users per Role
```sql
SELECT
  pr.name as role_name,
  COUNT(u.id) as user_count
FROM professional_roles pr
LEFT JOIN users u ON pr.id = u.professional_role
GROUP BY pr.id, pr.name
ORDER BY user_count DESC;
```

### Finding Users by Role
```sql
SELECT
  u.id,
  u.first_name,
  u.last_name,
  u.email
FROM users u
JOIN professional_roles pr ON u.professional_role = pr.id
WHERE pr.name = 'Architect'
ORDER BY u.last_name, u.first_name;
```

## Common Professional Roles

Typical roles in construction/project management:

- **General Contractor**
- **Architect**
- **Project Manager**
- **Structural Engineer**
- **Electrical Engineer**
- **Plumber**
- **Carpenter**
- **Estimator**
- **Superintendent**
- **Safety Officer**
- **Quantity Surveyor**
- **Interior Designer**
- **Civil Engineer**
- **HVAC Technician**
- **Developer**
- **Owner/Client**

These should be seeded during initial setup.

## Related Tables

### Tables Referencing Professional Roles
- `users` - Each user has one professional_role

## Seeding Data

Professional roles should be seeded in migrations or seed files:

```sql
-- Example seed data
INSERT INTO professional_roles (name) VALUES
  ('General Contractor'),
  ('Architect'),
  ('Project Manager'),
  ('Structural Engineer'),
  ('Electrical Engineer'),
  ('Plumber'),
  ('Carpenter'),
  ('Estimator'),
  ('Superintendent'),
  ('Safety Officer')
ON CONFLICT (name) DO NOTHING;
```

See: `supabase/seeders/sample_data/101_professional_roles.sql`

## Best Practices

### Data Management
- Seed roles during database initialization
- Add new roles via migrations (not manual SQL)
- Don't delete roles that have users assigned
- Consider archiving unused roles instead of deleting

### Naming Conventions
- Use singular form ("Architect" not "Architects")
- Use title case ("Project Manager" not "project manager")
- Be specific but concise
- Avoid abbreviations unless industry-standard

### Application Integration
- Cache roles in application (they rarely change)
- Show roles alphabetically in dropdowns
- Consider role grouping for large lists (e.g., "Engineering", "Trades")
- Allow "Other" option if needed

### Extensibility
Consider adding fields in future:
- `description` - Detailed role description
- `category` - Group roles (e.g., "Engineering", "Management", "Trades")
- `is_active` - Enable/disable roles without deleting
- `display_order` - Custom ordering in dropdowns

## Testing

See: `supabase/seeders/sample_data/101_professional_roles.sql`

Consider testing:
- Unique constraint on name
- Public SELECT access (unauthenticated)
- No INSERT/UPDATE/DELETE via RLS
- Foreign key relationship with users

## Migration History

- Initial creation in migration `20250514010731_02_professional_roles.sql`
- RLS policy added in migration `20251203033508_RLS_05_public_tables_policies.sql`
