begin;

create or replace function public.create_staff(
  p_restaurant_id uuid,
  p_full_name text,
  p_pin text,
  p_role text default 'staff',
  p_auth_token text default null,
  p_department text default 'Unassigned',
  p_age_range text default null,
  p_sex text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  a public.auth_sessions;
  sid uuid;
  v_department text;
  v_max_staff_users integer;
begin
  select * into a from private.auth(p_auth_token);
  if a.principal_type is distinct from 'staff'
     or a.restaurant_id is distinct from p_restaurant_id
     or not exists (select 1 from public.staff where id=a.principal_id and role='manager') then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;

  if p_pin is null or p_pin !~ '^[0-9]{4}$' then
    return jsonb_build_object('success',false,'error','pin_must_be_4_digits');
  end if;
  if p_full_name is null or length(btrim(p_full_name)) not between 1 and 160 then
    return jsonb_build_object('success',false,'error','invalid_full_name');
  end if;

  v_department := btrim(p_department);
  if p_department is null or length(v_department) not between 1 and 80 then
    return jsonb_build_object('success',false,'error','invalid_department');
  end if;
  if p_age_range is not null and p_age_range not in ('18_25','26_30','31_35','over_35') then
    return jsonb_build_object('success',false,'error','invalid_age_range');
  end if;
  if p_sex is not null and p_sex not in ('female','male') then
    return jsonb_build_object('success',false,'error','invalid_sex');
  end if;

  if exists (
    select 1 from public.staff
    where restaurant_id=p_restaurant_id
      and lower(btrim(full_name))=lower(btrim(p_full_name))
  ) then
    return jsonb_build_object('success',false,'error','name_taken');
  end if;

  select max_staff_users into v_max_staff_users from public.restaurants where id=p_restaurant_id;
  perform pg_advisory_xact_lock(hashtextextended(p_restaurant_id::text, 0));
  if p_role <> 'manager' and (select count(*) from public.staff where restaurant_id=p_restaurant_id and role='staff' and active) >= v_max_staff_users then
    return jsonb_build_object('success',false,'error','staff_limit_reached','max_staff_users',v_max_staff_users);
  end if;

  begin
    insert into public.staff(restaurant_id,full_name,pin_hash,role,department,age_range,sex)
    values(
      p_restaurant_id,
      btrim(p_full_name),
      extensions.crypt(p_pin,extensions.gen_salt('bf')),
      case when p_role='manager' then 'manager' else 'staff' end,
      v_department,
      p_age_range,
      p_sex
    )
    returning id into sid;
  exception when unique_violation then
    return jsonb_build_object('success',false,'error','name_taken');
  end;

  return jsonb_build_object('success',true,'staff_id',sid);
end;
$$;

commit;
