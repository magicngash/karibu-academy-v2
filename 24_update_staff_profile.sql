begin;

create or replace function public.update_staff_profile(
  p_staff_id uuid,
  p_full_name text,
  p_department text,
  p_age_range text default null,
  p_sex text default null,
  p_auth_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  a public.auth_sessions;
  target_restaurant_id uuid;
begin
  select * into a from private.auth(p_auth_token);
  if a.principal_type is distinct from 'staff'
     or not exists (
       select 1 from public.staff m
       where m.id=a.principal_id
         and m.restaurant_id=a.restaurant_id
         and m.role='manager'
     ) then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;

  if p_full_name is null or length(btrim(p_full_name)) not between 1 and 160 then
    return jsonb_build_object('success',false,'error','invalid_full_name');
  end if;
  if p_department is null or length(btrim(p_department)) not between 1 and 80 then
    return jsonb_build_object('success',false,'error','invalid_department');
  end if;
  if p_age_range is not null and p_age_range not in ('under_18','18_24','25_34','35_44','45_54','55_plus','prefer_not_to_say') then
    return jsonb_build_object('success',false,'error','invalid_age_range');
  end if;
  if p_sex is not null and p_sex not in ('female','male','intersex','prefer_not_to_say') then
    return jsonb_build_object('success',false,'error','invalid_sex');
  end if;

  select restaurant_id into target_restaurant_id
  from public.staff
  where id=p_staff_id;
  if target_restaurant_id is null or target_restaurant_id is distinct from a.restaurant_id then
    return jsonb_build_object('success',false,'error','staff_not_found');
  end if;

  begin
    update public.staff
    set full_name=btrim(p_full_name),
        department=btrim(p_department),
        age_range=p_age_range,
        sex=p_sex,
        updated_at=now()
    where id=p_staff_id and restaurant_id=a.restaurant_id;
  exception when unique_violation then
    return jsonb_build_object('success',false,'error','name_taken');
  end;

  return jsonb_build_object('success',true,'staff_id',p_staff_id);
end;
$$;

revoke all on function public.update_staff_profile(uuid,text,text,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.update_staff_profile(uuid,text,text,text,text,text) to anon,authenticated,service_role;

commit;
