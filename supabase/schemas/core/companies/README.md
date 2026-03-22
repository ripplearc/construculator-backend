# Companies Module

## Overview

The `companies` table stores organization information. Companies can own projects, have teams, and employ users through the `company_users` relationship.

## Table Structure

### Core Fields
- `id` - UUID primary key
- `name` - Company name
- `email` - Company contact email (unique)
- `phone` - Company contact phone (unique)
- `logo_url` - URL to company logo image

### Metadata
- `created_at` - Company creation timestamp
- `updated_at` - Last update timestamp

## Business Rules

### 1. Contact Information Uniqueness
- Email must be unique across all companies
- Phone must be unique across all companies
- Both are required (not nullable)

This ensures:
- No duplicate company registrations
- Clear contact points per organization
- Easy lookup by email or phone

### 2. Company Hierarchy
Companies are the top-level organizational unit:
```
Company
├── Teams (via teams table)
│   └── Team Members (users)
├── Company Users (via company_users)
│   └── Users with roles
└── Projects (via projects.owning_company_id)
```

### 3. Logo Management
- `logo_url` is optional
- Should point to image storage (e.g., S3)
- Logo should be displayed in company branding
- Consider size/format restrictions in application

## Indexes

No additional indexes beyond:
- Primary key on `id`
- Unique constraint on `email`
- Unique constraint on `phone`

These are sufficient for typical queries (lookup by ID, email, or phone).

## RLS Policies

RLS is enabled but no specific policies are defined in this extraction.

Typical policies to consider:
- **SELECT**: Users can view companies they belong to
- **INSERT**: Admins/system can create companies
- **UPDATE**: Company admins can update their company
- **DELETE**: System admins can delete companies

Example policy (not currently implemented):
```sql
-- Users can view companies they're members of
CREATE POLICY "view_own_company" ON companies
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM company_users
      WHERE company_users.company_id = companies.id
        AND company_users.user_id = (
          SELECT id FROM users WHERE credential_id = auth.uid()
        )
    )
  );
```

## Usage Examples

### Creating a Company
```sql
INSERT INTO companies (
  name,
  email,
  phone,
  logo_url
) VALUES (
  'Acme Construction',
  'info@acmeconstruction.com',
  '+1-555-0123',
  'https://storage.example.com/logos/acme.png'
);
```

### Updating Company Info
```sql
UPDATE companies
SET
  name = 'Acme Construction Inc.',
  logo_url = 'https://storage.example.com/logos/acme_new.png',
  updated_at = now()
WHERE id = 'company-uuid';
```

### Finding Company by Email
```sql
SELECT *
FROM companies
WHERE email = 'info@acmeconstruction.com';
```

### Getting All Users in a Company
```sql
SELECT
  u.id,
  u.first_name,
  u.last_name,
  u.email,
  r.role_name
FROM companies c
JOIN company_users cu ON c.id = cu.company_id
JOIN users u ON cu.user_id = u.id
JOIN roles r ON cu.role_id = r.id
WHERE c.id = 'company-uuid';
```

### Getting All Teams in a Company
```sql
SELECT *
FROM teams
WHERE company_id = 'company-uuid'
ORDER BY team_name;
```

### Getting Company Projects
```sql
SELECT *
FROM projects
WHERE owning_company_id = 'company-uuid'
  AND project_status = 'active'
ORDER BY created_at DESC;
```

## Related Tables

### Direct References to Companies
- `company_users` - Links users to companies with roles
- `teams` - Teams within a company
- `projects` - Projects owned by company (via owning_company_id)

### Indirect Relationships
- Through teams: `team_members`, `project_teams`
- Through projects: All project-related data

## Best Practices

### Company Creation
- Validate email format before insertion
- Verify phone format (consider international formats)
- Ensure name is not empty or just whitespace
- Logo URL should be validated as valid URL

### Email & Phone Management
- Use lowercase for emails for consistency
- Store phone in international format (+country-code)
- Handle unique constraint violations gracefully

### Logo Management
- Store actual images in object storage (S3, etc.)
- Only store URL in database
- Consider image size limits (recommend 500x500px or similar)
- Support common formats (PNG, JPG, SVG)

### Data Integrity
- Before deleting company, consider:
  - Existing projects
  - Current team members
  - Active company users
- Consider "soft delete" approach instead
- Or cascade delete carefully

## Common Queries

### Active Companies with User Count
```sql
SELECT
  c.id,
  c.name,
  c.email,
  COUNT(cu.user_id) as user_count
FROM companies c
LEFT JOIN company_users cu ON c.id = cu.company_id
GROUP BY c.id, c.name, c.email
ORDER BY user_count DESC;
```

### Companies with Project Count
```sql
SELECT
  c.id,
  c.name,
  COUNT(p.id) as project_count
FROM companies c
LEFT JOIN projects p ON c.id = p.owning_company_id
GROUP BY c.id, c.name
ORDER BY project_count DESC;
```

### Company Admin Users
```sql
-- Assuming there's a 'Company Admin' role
SELECT
  c.name as company_name,
  u.first_name,
  u.last_name,
  u.email
FROM companies c
JOIN company_users cu ON c.id = cu.company_id
JOIN users u ON cu.user_id = u.id
JOIN roles r ON cu.role_id = r.id
WHERE r.role_name = 'Company Admin'
  AND c.id = 'company-uuid';
```

## Testing

No specific test files exist yet for companies table.

Consider testing:
- Unique constraint on email
- Unique constraint on phone
- Company creation workflow
- Company-user relationships
- Company-project relationships
