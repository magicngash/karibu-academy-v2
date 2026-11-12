-- Migration 14: fix owner restaurant creation on Supabase.
-- The owner RPC uses pgcrypto's crypt()/gen_salt(). Supabase commonly
-- installs extensions into the extensions schema, so it must be included
-- in the SECURITY DEFINER search_path.

create or replace function public.owner_create_restaurant(
  p_name text,
  p_app_name text,
  p_manager_name text,
  p_manager_pin text,
  p_auth_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, private, pg_temp
as $$
declare
  r public.restaurants;
  v_owner_id uuid;
  base_slug text;
  candidate_slug text;
  suffix integer := 1;
begin
  select principal_id
    into v_owner_id
  from private.auth(p_auth_token)
  where principal_type = 'owner';

  if v_owner_id is null then
    return jsonb_build_object('success', false, 'error', 'unauthorized');
  end if;

  if p_manager_pin !~ '^[0-9]{4}$' then
    return jsonb_build_object('success', false, 'error', 'pin_must_be_4_digits');
  end if;

  base_slug := lower(regexp_replace(regexp_replace(btrim(p_name), '[^a-zA-Z0-9]+', '-', 'g'), '^-+|-+$', '', 'g'));
  if base_slug is null or base_slug = '' then
    base_slug := 'restaurant';
  end if;

  candidate_slug := base_slug;
  while exists (select 1 from public.restaurants where slug = candidate_slug) loop
    candidate_slug := base_slug || '-' || suffix;
    suffix := suffix + 1;
  end loop;

  insert into public.restaurants(name, app_name, slug)
  values (btrim(p_name), coalesce(nullif(btrim(p_app_name), ''), 'Karibu Academy'), candidate_slug)
  returning * into r;

  insert into public.owner_restaurants(owner_id, restaurant_id)
  values (v_owner_id, r.id);

  insert into public.staff(restaurant_id, full_name, pin_hash, role)
  values (r.id, btrim(p_manager_name), crypt(p_manager_pin, gen_salt('bf')), 'manager');

  return jsonb_build_object('success', true, 'restaurant_id', r.id);
end;
$$;

do $$
begin
  execute 'revoke all on function public.owner_create_restaurant(text,text,text,text,text) from public';
  execute 'grant execute on function public.owner_create_restaurant(text,text,text,text,text) to anon, authenticated';
end;
$$;

notify pgrst, 'reload schema';
