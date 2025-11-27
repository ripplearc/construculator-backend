-- RLS Performance Optimizations

-- Critical indexes for RLS policy performance
-- Note: Using regular CREATE INDEX instead of CONCURRENTLY to avoid pipeline issues
CREATE INDEX IF NOT EXISTS "idx_project_members_performance" 
ON "project_members" ("project_id", "user_id", "membership_status", "role_id");

CREATE INDEX IF NOT EXISTS "idx_permissions_key" 
ON "permissions" ("permission_key");

CREATE INDEX IF NOT EXISTS "idx_role_permissions_covering" 
ON "role_permissions" ("role_id", "permission_id") 
INCLUDE ("id");

CREATE INDEX IF NOT EXISTS "idx_users_credential_id" 
ON "users" ("credential_id");

CREATE INDEX IF NOT EXISTS "idx_cost_estimates_creator" 
ON "cost_estimates" ("creator_user_id");

CREATE INDEX IF NOT EXISTS "idx_users_id_credential" 
ON "users" ("id", "credential_id");

-- Update table statistics
ANALYZE "project_members", "users", "role_permissions", "permissions", "cost_estimates";
