-- Update trigger function to use JWT claims instead of database lookups
-- This improves performance by reading permissions from JWT tokens

CREATE OR REPLACE FUNCTION check_cost_estimate_update_permissions()
RETURNS TRIGGER
SET search_path = public
AS $$
DECLARE
  delete_changed boolean;
  lock_changed boolean;
  immutable_changed boolean;
BEGIN
  IF current_user IS DISTINCT FROM 'authenticated' THEN
    RETURN NEW;
  END IF;

  delete_changed := (OLD.deleted_at IS DISTINCT FROM NEW.deleted_at)
    OR (NEW.deleted_at IS NOT NULL);
  lock_changed := (OLD.is_locked IS DISTINCT FROM NEW.is_locked);

  immutable_changed := ROW(
    OLD.id,
    OLD.project_id,
    OLD.creator_user_id,
    OLD.locked_by_user_id,
    OLD.locked_at,
    OLD.markup_type,
    OLD.overall_markup_value_type,
    OLD.overall_markup_value,
    OLD.material_markup_value_type,
    OLD.material_markup_value,
    OLD.labor_markup_value_type,
    OLD.labor_markup_value,
    OLD.equipment_markup_value_type,
    OLD.equipment_markup_value,
    OLD.total_cost,
    OLD.created_at
  ) IS DISTINCT FROM ROW(
    NEW.id,
    NEW.project_id,
    NEW.creator_user_id,
    NEW.locked_by_user_id,
    NEW.locked_at,
    NEW.markup_type,
    NEW.overall_markup_value_type,
    NEW.overall_markup_value,
    NEW.material_markup_value_type,
    NEW.material_markup_value,
    NEW.labor_markup_value_type,
    NEW.labor_markup_value,
    NEW.equipment_markup_value_type,
    NEW.equipment_markup_value,
    NEW.total_cost,
    NEW.created_at
  );

  IF immutable_changed THEN
    RAISE EXCEPTION 'Immutable columns on cost_estimates cannot be updated'
      USING ERRCODE = '42501';
  END IF;

  -- Use JWT claims instead of database lookup
  IF delete_changed THEN
    IF NOT jwt_has_project_permission(
      NEW.project_id,
      'delete_cost_estimation'
    ) THEN
      RAISE EXCEPTION 'Insufficient permissions: delete_cost_estimation required to mark as deleted'
      USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Use JWT claims instead of database lookup
  IF lock_changed THEN
    IF NOT jwt_has_project_permission(
      NEW.project_id,
      'lock_cost_estimation'
    ) THEN
      RAISE EXCEPTION 'Insufficient permissions: lock_cost_estimation required to modify lock columns'
        USING ERRCODE = '42501';
    END IF;


    IF NEW.is_locked THEN
      NEW.locked_by_user_id := (SELECT id FROM users WHERE credential_id = (auth.jwt()->>'sub')::uuid);
      NEW.locked_at := now();
    ELSE
      NEW.locked_by_user_id := NULL;
      NEW.locked_at := NULL;
    END IF;
  END IF;

  NEW.updated_at = now();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
