-- Permissions define atomic operations that can be performed on a resource.
-- Details can be found in the database design documentation: https://docs.google.com/document/d/144-j6mZluSGtFXZdF23cVf9hbVWt4vb-wA3eq02Au4M/edit?tab=t.86935laa5ftt#heading=h.kz665gmft5kd

-- Insert permissions for cost estimation operations
INSERT INTO "permissions" ("permission_key", "description", "context_type") VALUES
  ('get_cost_estimations', 'Permission to retrieve and view cost estimations', 'project'),
  ('add_cost_estimation', 'Permission to create and add new cost estimations', 'project')
ON CONFLICT ("permission_key") DO NOTHING;
