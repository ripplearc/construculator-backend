-- Permissions define atomic operations that can be performed on a resource.
-- Details can be found in the database design documentation: https://docs.google.com/document/d/144-j6mZluSGtFXZdF23cVf9hbVWt4vb-wA3eq02Au4M/edit?tab=t.86935laa5ftt#heading=h.kz665gmft5kd

INSERT INTO "permissions" (
  "permission_key",
  "description",
  "context_type"
) VALUES
  -- Insert permissions for cost estimation operations
  (
    'get_cost_estimations',
    'Permission to retrieve and view cost estimations',
    'project'
  ),
  (
    'add_cost_estimation',
    'Permission to create and add new cost estimations',
    'project'
  ),
  (
    'delete_cost_estimation',
    'Permission to delete cost estimations',
    'project'
  ),
  (
    'edit_cost_estimation',
    'Permission to edit cost estimation details',
    'project'
  ),
  (
    'lock_cost_estimation',
    'Permission to lock and unlock cost estimations',
    'project'
  ),
  -- Insert permissions for project operations
  (
    'view_project',
    'Permission to view project details',
    'project'
  ),
  (
    'edit_project',
    'Permission to edit project details',
    'project'
  ),
  (
    'delete_project',
    'Permission to delete project',
    'project'
  ),
  -- Insert permissions for member-management operations (CA-806)
  (
    'get_members',
    'Permission to view the members of a project',
    'project'
  ),
  (
    'invite_member',
    'Permission to invite new members to a project',
    'project'
  ),
  (
    'update_member_role',
    'Permission to change the role of a project member',
    'project'
  ),
  (
    'remove_member',
    'Permission to remove a member from a project',
    'project'
  ),
  (
    'get_task_assignments',
    'Permission to view task assignments within a project',
    'project'
  )
ON CONFLICT ("permission_key") DO NOTHING;
