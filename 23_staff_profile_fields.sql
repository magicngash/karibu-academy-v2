begin;

alter table public.staff
  add column if not exists department text,
  add column if not exists age_range text,
  add column if not exists sex text;

alter table public.staff
  drop constraint if exists staff_department_valid,
  drop constraint if exists staff_age_range_valid,
  drop constraint if exists staff_sex_valid;

alter table public.staff
  add constraint staff_department_valid
    check (department is null or length(btrim(department)) between 1 and 80),
  add constraint staff_age_range_valid
    check (age_range is null or age_range in ('under_18','18_24','25_34','35_44','45_54','55_plus','prefer_not_to_say')),
  add constraint staff_sex_valid
    check (sex is null or sex in ('female','male','intersex','prefer_not_to_say'));

drop function if exists public.create_staff(uuid,text,text,text,text);
drop function if exists public.create_staff(uuid,text,text,text,text,text,text,text);

create function public.create_staff(
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

  -- The default preserves compatibility with an already-open older app; the current
  -- manager form requires a department before it submits a new profile.
  v_department := btrim(p_department);
  if p_department is null or length(v_department) not between 1 and 80 then
    return jsonb_build_object('success',false,'error','invalid_department');
  end if;
  if p_age_range is not null and p_age_range not in ('under_18','18_24','25_34','35_44','45_54','55_plus','prefer_not_to_say') then
    return jsonb_build_object('success',false,'error','invalid_age_range');
  end if;
  if p_sex is not null and p_sex not in ('female','male','intersex','prefer_not_to_say') then
    return jsonb_build_object('success',false,'error','invalid_sex');
  end if;

  if exists (
    select 1 from public.staff
    where restaurant_id=p_restaurant_id
      and lower(btrim(full_name))=lower(btrim(p_full_name))
  ) then
    return jsonb_build_object('success',false,'error','name_taken');
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

revoke all on function public.create_staff(uuid,text,text,text,text,text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.create_staff(uuid,text,text,text,text,text,text,text) to anon, authenticated, service_role;

drop function if exists public.manager_dashboard(uuid,text);

create function public.manager_dashboard(p_restaurant_id uuid,p_auth_token text default null)
returns table(
  staff_id uuid,
  full_name text,
  role text,
  department text,
  age_range text,
  sex text,
  module_id integer,
  status text,
  quiz_score integer,
  quiz_total integer,
  updated_at timestamptz
)
language sql
security definer
set search_path=public,private,pg_temp
as $$
  select
    s.id,
    s.full_name,
    s.role,
    s.department,
    s.age_range,
    s.sex,
    p.module_id,
    coalesce(p.status,'not_started'),
    p.quiz_score,
    p.quiz_total,
    p.updated_at
  from public.staff s
  left join public.module_progress p on p.staff_id=s.id
  where s.restaurant_id=p_restaurant_id
    and exists (
      select 1
      from private.auth(p_auth_token) a
      where a.principal_type='staff'
        and a.restaurant_id=p_restaurant_id
        and exists (select 1 from public.staff m where m.id=a.principal_id and m.role='manager')
    )
  order by s.full_name,p.module_id
$$;

revoke all on function public.manager_dashboard(uuid,text) from public, anon, authenticated, service_role;
grant execute on function public.manager_dashboard(uuid,text) to anon, authenticated, service_role;

commit;
