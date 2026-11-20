-- Enforce the product limit: every restaurant may have 2 to 20 active staff users.
UPDATE public.restaurants
SET max_staff_users = 20
WHERE max_staff_users IS NULL OR max_staff_users > 20;

ALTER TABLE public.restaurants
  DROP CONSTRAINT IF EXISTS restaurants_max_staff_users_valid;

ALTER TABLE public.restaurants
  ADD CONSTRAINT restaurants_max_staff_users_valid
  CHECK (max_staff_users BETWEEN 2 AND 20 AND mod(max_staff_users, 2) = 0);

CREATE OR REPLACE FUNCTION public.owner_update_staff_limit(
  p_restaurant_id uuid,
  p_max_staff_users integer,
  p_auth_token text default null
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, private, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.auth(p_auth_token) WHERE principal_type='owner') THEN
    RETURN jsonb_build_object('success',false,'error','unauthorized');
  END IF;
  IF p_max_staff_users IS NULL OR p_max_staff_users < 2 OR p_max_staff_users > 20 OR mod(p_max_staff_users,2) <> 0 THEN
    RETURN jsonb_build_object('success',false,'error','invalid_staff_limit');
  END IF;
  UPDATE public.restaurants SET max_staff_users=p_max_staff_users WHERE id=p_restaurant_id;
  RETURN jsonb_build_object('success',true,'max_staff_users',p_max_staff_users);
END;
$$;
