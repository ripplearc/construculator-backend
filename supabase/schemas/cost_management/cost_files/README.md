# Cost Files Module

## Overview

The `cost_files` table stores uploaded cost estimate template files (e.g., Excel spreadsheets) for projects. Each file has a version, can be marked as active, and tracks who uploaded it.

## Table Structure

### Core Fields
- `id` - UUID primary key
- `project_id` - Foreign key to projects table
- `version` - Version string (e.g., "1.0", "2.1", "v3")
- `filename` - Original filename
- `file_url` - URL/path to the stored file
- `file_size_bytes` - Size of file in bytes
- `content_type` - MIME type (e.g., "application/vnd.ms-excel")
- `uploaded_by_user_id` - User who uploaded the file
- `is_active_file` - Boolean flag indicating current active version
- `is_sample_file` - Boolean flag indicating if this is a sample/template
- `uploaded_at` - Upload timestamp

## Business Rules

### 1. Active File
- Each project can have **one active file** at a time
- When a new file is marked as active, previous active files should be unmarked
- The active file is the "current working version" for the project
- Query pattern: `WHERE project_id = ? AND is_active_file = true`

### 2. Sample Files
- Sample files (`is_sample_file = true`) are templates/examples
- They can be copied to create new project cost files
- Sample files typically don't belong to a specific project (or have a special project)
- **Note:** The actual sample files will be introduced in a follow-up PR.

### 3. Versioning
- Files use semantic versioning or custom version strings
- Versions are stored as strings for flexibility
- Users can maintain multiple versions for a project
- Only one version should be active at a time

### 4. File Storage
- `file_url` points to actual file location (e.g., S3, storage bucket)
- File content is NOT stored in the database
- Database stores metadata only

## Permissions

Access to cost files typically follows project permissions. Users with access to a project can:
- View cost files for that project
- Upload new cost files (if they have upload permission)
- Download cost files
- Mark files as active (if they have edit permission)

## Indexes

Performance indexes for common queries:
- `cost_files_project_id_idx` - Filter by project
- `cost_files_active_idx` - Composite index for finding active file per project
- `cost_files_uploaded_by_user_id_idx` - Filter by uploader
- `cost_files_version_idx` - Filter/sort by version

## RLS Policies

RLS is enabled but no specific policies are defined in this extraction. Policies should be added based on project access control requirements (similar to cost_estimates).

Typical policies would include:
- SELECT: Users can view files for projects they have access to
- INSERT: Users with upload permission can add files
- UPDATE: Users with edit permission can update file metadata
- DELETE: Users with delete permission can remove files

## Usage Examples

### Uploading a New File
```sql
INSERT INTO cost_files (
  project_id,
  version,
  filename,
  file_url,
  file_size_bytes,
  content_type,
  uploaded_by_user_id,
  is_active_file
) VALUES (
  'project-uuid',
  '1.0',
  'project_costs.xlsx',
  's3://bucket/files/project-uuid/costs_v1.xlsx',
  1024000,
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'user-uuid',
  true
);
```

### Getting Active File
```sql
SELECT *
FROM cost_files
WHERE project_id = 'project-uuid'
  AND is_active_file = true
LIMIT 1;
```

### Marking a File as Active
```sql
-- First, unmark current active file
UPDATE cost_files
SET is_active_file = false
WHERE project_id = 'project-uuid'
  AND is_active_file = true;

-- Then, mark new file as active
UPDATE cost_files
SET is_active_file = true
WHERE id = 'new-file-uuid';
```

### Listing All Versions
```sql
SELECT
  version,
  filename,
  uploaded_at,
  is_active_file,
  file_size_bytes
FROM cost_files
WHERE project_id = 'project-uuid'
ORDER BY uploaded_at DESC;
```

### Getting Sample Files
```sql
SELECT *
FROM cost_files
WHERE is_sample_file = true
ORDER BY version;
```

## Related Tables

- `projects` - Parent table
- `users` - Uploader reference
- `sample_cost_files` - Separate table for sample/template files

## Best Practices

### File Versioning
- Use consistent version scheme (e.g., semantic versioning)
- Increment version on significant changes
- Keep version in sync with filename if possible

### Active File Management
- Only one active file per project
- Use transactions when switching active files
- Consider keeping version history

### File Storage
- Store actual files in object storage (S3, etc.)
- Use signed URLs for secure access
- Clean up old file versions when appropriate

### Sample Files
- Keep sample files in separate system project
- Make them easily discoverable
- Version them separately from project files

## Testing

Cost files testing would typically verify:
- Upload and download workflows
- Active file switching
- Version management
- Access control
- File size limits
