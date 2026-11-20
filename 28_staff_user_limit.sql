-- Add an owner-controlled active staff-user limit per restaurant.
-- The default is 20, with supported values from 2 through 100 in increments of 2.
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS max_staff_users integer;

UPDATE public.restaurants
SET max_staff_users = 20
WHERE max_staff_users IS NULL;

ALTER TABLE public.restaurants
  ALTER COLUMN max_staff_users SET DEFAULT 20,
  ALTER COLUMN max_staff_users SET NOT NULL;

ALTER TABLE public.restaurants
  DROP CONSTRAINT IF EXISTS restaurants_max_staff_users_valid;

ALTER TABLE public.restaurants
  ADD CONSTRAINT restaurants_max_staff_users_valid
  CHECK (max_staff_users BETWEEN 2 AND 100 AND mod(max_staff_users, 2) = 0);

CREATE OR REPLACE FUNCTION public.owner_list_restaurants(p_auth_token text default null)
RETURNS SETOF jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, private, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.auth(p_auth_token) a WHERE a.principal_type='owner') THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', r.id,
    'name', r.name,
    'app_name', r.app_name,
    'slug', r.slug,
    'payment_status', r.payment_status,
    'payment_note', r.payment_note,
    'max_staff_users', r.max_staff_users,
    'active_staff_count', (SELECT count(*) FROM public.staff s WHERE s.restaurant_id=r.id AND s.role='staff' AND s.active)
  )
  FROM public.restaurants r
  ORDER BY r.name;
END;
$$;

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
  IF p_max_staff_users IS NULL OR p_max_staff_users < 2 OR p_max_staff_users > 100 OR mod(p_max_staff_users,2) <> 0 THEN
    RETURN jsonb_build_object('success',false,'error','invalid_staff_limit');
  END IF;
  UPDATE public.restaurants SET max_staff_users=p_max_staff_users WHERE id=p_restaurant_id;
  RETURN jsonb_build_object('success',true,'max_staff_users',p_max_staff_users);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_staff(
  p_restaurant_id uuid,
  p_full_name text,
  p_pin text,
  p_role text default 'staff',
  p_auth_token text default null,
  p_department text default 'Unassigned',
  p_age_range text default null,
  p_sex text default null
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,private,pg_temp
AS $$
DECLARE
  a public.auth_sessions;
  sid uuid;
  v_department text;
  v_max_staff_users integer;
BEGIN
  SELECT * INTO a FROM private.auth(p_auth_token);
  IF a.principal_type IS DISTINCT FROM 'staff'
     OR a.restaurant_id IS DISTINCT FROM p_restaurant_id
     OR NOT EXISTS (SELECT 1 FROM public.staff WHERE id=a.principal_id AND role='manager') THEN
    RETURN jsonb_build_object('success',false,'error','unauthorized');
  END IF;
  IF p_pin IS NULL OR p_pin !~ '^[0-9]{4}$' THEN RETURN jsonb_build_object('success',false,'error','pin_must_be_4_digits'); END IF;
  IF p_full_name IS NULL OR length(btrim(p_full_name)) NOT BETWEEN 1 AND 160 THEN RETURN jsonb_build_object('success',false,'error','invalid_full_name'); END IF;
  v_department := btrim(p_department);
  IF p_department IS NULL OR length(v_department) NOT BETWEEN 1 AND 80 THEN RETURN jsonb_build_object('success',false,'error','invalid_department'); END IF;
  IF p_age_range IS NOT NULL AND p_age_range NOT IN ('18_25','26_30','31_35','over_35') THEN RETURN jsonb_build_object('success',false,'error','invalid_age_range'); END IF;
  IF p_sex IS NOT NULL AND p_sex NOT IN ('female','male') THEN RETURN jsonb_build_object('success',false,'error','invalid_sex'); END IF;
  IF EXISTS (SELECT 1 FROM public.staff WHERE restaurant_id=p_restaurant_id AND lower(btrim(full_name))=lower(btrim(p_full_name))) THEN RETURN jsonb_build_object('success',false,'error','name_taken'); END IF;
  SELECT max_staff_users INTO v_max_staff_users FROM public.restaurants WHERE id=p_restaurant_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_restaurant_id::text, 0));
  IF p_role <> 'manager' AND (SELECT count(*) FROM public.staff WHERE restaurant_id=p_restaurant_id AND role='staff' AND active) >= v_max_staff_users THEN
    RETURN jsonb_build_object('success',false,'error','staff_limit_reached','max_staff_users',v_max_staff_users);
  END IF;
  BEGIN
    INSERT INTO public.staff(restaurant_id,full_name,pin_hash,role,department,age_range,sex)
    VALUES(p_restaurant_id,btrim(p_full_name),extensions.crypt(p_pin,extensions.gen_salt('bf')),case when p_role='manager' then 'manager' else 'staff' end,v_department,p_age_range,p_sex)
    RETURNING id INTO sid;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success',false,'error','name_taken');
  END;
  RETURN jsonb_build_object('success',true,'staff_id',sid);
END;
$$;

GRANT EXECUTE ON FUNCTION public.owner_update_staff_limit(uuid,integer,text) TO anon, authenticated, service_role;
