-- Karibu Academy V2 RPCs. Run after 01_schema.sql.
-- Every PIN is checked with pgcrypto crypt(); plaintext PINs are never stored.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.token_hash(p_token text) returns text
language sql immutable strict set search_path = pg_catalog, public, extensions, pg_temp as $$ select encode(digest(p_token, 'sha256'), 'hex') $$;

create or replace function private.auth(p_token text)
returns public.auth_sessions language sql stable security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$
  select a from public.auth_sessions a
  where p_token is not null and a.token_hash = private.token_hash(p_token)
    and a.revoked_at is null and a.expires_at > pg_catalog.now()
    and ((a.principal_type = 'owner' and exists (
      select 1 from public.owners o where o.id = a.principal_id and o.active
    )) or (a.principal_type = 'staff' and exists (
      select 1 from public.staff s join public.restaurants r on r.id = s.restaurant_id
      where s.id = a.principal_id and s.active and r.active and r.payment_status <> 'blocked'
    )))
  limit 1
$$;

create or replace function private.issue(p_type text, p_id uuid, p_restaurant uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$
declare raw text := encode(gen_random_bytes(32), 'hex'); aid uuid;
begin
  insert into public.auth_sessions(principal_type,principal_id,restaurant_id,token_hash) values (p_type,p_id,p_restaurant,private.token_hash(raw)) returning id into aid;
  return jsonb_build_object('auth_token', raw, 'auth_expires_at', now() + interval '12 hours');
end; $$;

create or replace function public.get_restaurant_by_slug(p_slug text)
returns jsonb language sql security definer set search_path = pg_catalog, public, extensions, pg_temp as $$
  select pg_catalog.jsonb_build_object('id',r.id,'name',r.name,'app_name',r.app_name)
  from public.restaurants r where r.slug=pg_catalog.lower(pg_catalog.btrim(p_slug)) limit 1
$$;

create or replace function public.get_restaurant_info(p_restaurant_id uuid, p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$
declare r public.restaurants; begin select * into r from public.restaurants where id=p_restaurant_id; if not found then return null; end if;
return pg_catalog.jsonb_build_object('name',r.name,'app_name',r.app_name); end; $$;

create or replace function public.owner_login(p_full_name text,p_pin text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$
declare o public.owners; out jsonb; begin select * into o from public.owners where active and lower(full_name)=lower(btrim(p_full_name)) limit 1;
if not found then return jsonb_build_object('success',false,'error','invalid_credentials'); end if;
if o.locked_until is not null and o.locked_until > now() then return jsonb_build_object('success',false,'error','invalid_credentials'); end if;
if o.pin_hash <> crypt(p_pin,o.pin_hash) then
  update public.owners set failed_login_attempts=failed_login_attempts+1, locked_until=case when failed_login_attempts+1 >= 5 then now()+interval '15 minutes' else locked_until end where id=o.id;
  return jsonb_build_object('success',false,'error','invalid_credentials');
end if;
update public.owners set failed_login_attempts=0, locked_until=null where id=o.id;
out := private.issue('owner',o.id,null); return out || jsonb_build_object('success',true,'owner_id',o.id,'full_name',o.full_name); end; $$;

create or replace function public.revoke_token(p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$
begin
  update public.auth_sessions set revoked_at = now()
  where token_hash = private.token_hash(p_auth_token) and revoked_at is null;
  return jsonb_build_object('success', true);
end; $$;

create or replace function public.owner_change_pin(p_current_pin text,p_new_pin text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$
declare a public.auth_sessions; o public.owners;
begin
  select * into a from private.auth(p_auth_token);
  if not found or a.principal_type <> 'owner' then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  select * into o from public.owners where id=a.principal_id and active;
  if not found or o.pin_hash <> crypt(p_current_pin,o.pin_hash) then return jsonb_build_object('success',false,'error','wrong_current_pin'); end if;
  if p_new_pin !~ '^[0-9]{4}$' then return jsonb_build_object('success',false,'error','pin_must_be_4_digits'); end if;
  update public.owners set pin_hash=crypt(p_new_pin,gen_salt('bf')),failed_login_attempts=0,locked_until=null where id=o.id;
  update public.auth_sessions set revoked_at=now() where principal_type='owner' and principal_id=o.id and revoked_at is null;
  return jsonb_build_object('success',true);
end; $$;

create or replace function public.staff_login(p_restaurant_id uuid,p_full_name text,p_pin text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$
declare s public.staff; r public.restaurants; out jsonb; begin select * into r from public.restaurants where id=p_restaurant_id;
if not found then return jsonb_build_object('success',false,'error','invalid_credentials'); end if;
select * into s from public.staff where restaurant_id=p_restaurant_id and lower(full_name)=lower(btrim(p_full_name)) limit 1;
if not found then return jsonb_build_object('success',false,'error','invalid_credentials'); end if;
if not r.active or r.payment_status='blocked' or not s.active then return jsonb_build_object('success',false,'error','invalid_credentials'); end if;
if s.locked_until is not null and s.locked_until > now() then return jsonb_build_object('success',false,'error','invalid_credentials'); end if;
if s.pin_hash <> crypt(p_pin,s.pin_hash) then
  update public.staff set failed_login_attempts=failed_login_attempts+1, locked_until=case when failed_login_attempts+1 >= 5 then now()+interval '15 minutes' else locked_until end where id=s.id;
  return jsonb_build_object('success',false,'error','invalid_credentials');
end if;
update public.staff set failed_login_attempts=0, locked_until=null where id=s.id;
out:=private.issue('staff',s.id,s.restaurant_id); return out || jsonb_build_object('success',true,'staff_id',s.id,'full_name',s.full_name,'role',s.role,'payment_status',r.payment_status); end; $$;

create or replace function public.owner_list_restaurants(p_auth_token text default null)
returns setof jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$ begin
if not exists(select 1 from private.auth(p_auth_token) a where a.principal_type='owner') then return; end if;
return query select jsonb_build_object('id',r.id,'name',r.name,'app_name',r.app_name,'slug',r.slug,'payment_status',r.payment_status,'payment_note',r.payment_note,'max_staff_users',r.max_staff_users,'active_staff_count',(select count(*) from public.staff s where s.restaurant_id=r.id and s.role='staff' and s.active)) from public.restaurants r order by r.name;
end; $$;

create or replace function public.owner_create_restaurant(p_name text,p_app_name text,p_manager_name text,p_manager_pin text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions, private, pg_temp as $$
declare r public.restaurants; begin if not exists(select 1 from private.auth(p_auth_token) where principal_type='owner') then return jsonb_build_object('success',false,'error','unauthorized'); end if;
if p_manager_pin !~ '^[0-9]{4}$' then return jsonb_build_object('success',false,'error','pin_must_be_4_digits'); end if;
insert into public.restaurants(name,app_name,slug) values (btrim(p_name),coalesce(nullif(btrim(p_app_name),''),'Karibu Academy'),'pending') returning * into r;
insert into public.staff(restaurant_id,full_name,pin_hash,role) values(r.id,btrim(p_manager_name),crypt(p_manager_pin,gen_salt('bf')),'manager');
return jsonb_build_object('success',true,'restaurant_id',r.id); end; $$;

create or replace function public.owner_update_branding(p_restaurant_id uuid,p_name text,p_app_name text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions,private,pg_temp as $$ begin if not exists(select 1 from private.auth(p_auth_token) where principal_type='owner') then return jsonb_build_object('success',false,'error','unauthorized'); end if; update public.restaurants set name=btrim(p_name),app_name=btrim(p_app_name) where id=p_restaurant_id; return jsonb_build_object('success',true); end; $$;

create or replace function public.owner_update_staff_limit(p_restaurant_id uuid,p_max_staff_users integer,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions,private,pg_temp as $$ begin
if not exists(select 1 from private.auth(p_auth_token) where principal_type='owner') then return jsonb_build_object('success',false,'error','unauthorized'); end if;
if p_max_staff_users is null or p_max_staff_users < 2 or p_max_staff_users > 20 or mod(p_max_staff_users,2) <> 0 then return jsonb_build_object('success',false,'error','invalid_staff_limit'); end if;
update public.restaurants set max_staff_users=p_max_staff_users where id=p_restaurant_id;
return jsonb_build_object('success',true,'max_staff_users',p_max_staff_users); end; $$;

create or replace function public.owner_update_restaurant_status(p_restaurant_id uuid,p_status text,p_note text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions,private,pg_temp as $$ begin if not exists(select 1 from private.auth(p_auth_token) where principal_type='owner') then return jsonb_build_object('success',false,'error','unauthorized'); end if; if p_status not in('active','overdue','blocked') then return jsonb_build_object('success',false,'error','invalid_status'); end if; update public.restaurants set payment_status=p_status,active=(p_status<>'blocked'),payment_note=p_note where id=p_restaurant_id; return jsonb_build_object('success',true); end; $$;

create or replace function public.owner_delete_restaurant(p_restaurant_id uuid,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if not exists(select 1 from private.auth(p_auth_token) where principal_type='owner') then return jsonb_build_object('success',false,'error','unauthorized'); end if; delete from public.restaurants where id=p_restaurant_id; return jsonb_build_object('success',true); end; $$;

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
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
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
  -- Preserve compatibility with an already-open older app; the current form requires a department.
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
end; $$;

create or replace function public.update_staff_profile(
  p_staff_id uuid,
  p_full_name text,
  p_department text,
  p_age_range text default null,
  p_sex text default null,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare
  a public.auth_sessions;
  target_restaurant_id uuid;
begin
  select * into a from private.auth(p_auth_token);
  if a.principal_type is distinct from 'staff'
     or not exists (select 1 from public.staff m where m.id=a.principal_id and m.restaurant_id=a.restaurant_id and m.role='manager') then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_full_name is null or length(btrim(p_full_name)) not between 1 and 160 then
    return jsonb_build_object('success',false,'error','invalid_full_name');
  end if;
  if p_department is null or length(btrim(p_department)) not between 1 and 80 then
    return jsonb_build_object('success',false,'error','invalid_department');
  end if;
  if p_age_range is not null and p_age_range not in ('18_25','26_30','31_35','over_35') then
    return jsonb_build_object('success',false,'error','invalid_age_range');
  end if;
  if p_sex is not null and p_sex not in ('female','male') then
    return jsonb_build_object('success',false,'error','invalid_sex');
  end if;
  select restaurant_id into target_restaurant_id from public.staff where id=p_staff_id;
  if target_restaurant_id is null or target_restaurant_id is distinct from a.restaurant_id then
    return jsonb_build_object('success',false,'error','staff_not_found');
  end if;
  begin
    update public.staff
    set full_name=btrim(p_full_name),department=btrim(p_department),age_range=p_age_range,sex=p_sex,updated_at=now()
    where id=p_staff_id and restaurant_id=a.restaurant_id;
  exception when unique_violation then
    return jsonb_build_object('success',false,'error','name_taken');
  end;
  return jsonb_build_object('success',true,'staff_id',p_staff_id);
end; $$;

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
  if p_age_range is not null and p_age_range not in ('18_25','26_30','31_35','over_35') then
    return jsonb_build_object('success',false,'error','invalid_age_range');
  end if;
  if p_sex is not null and p_sex not in ('female','male') then
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

create or replace function public.reset_staff_pin(p_staff_id uuid,p_new_pin text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions,private,pg_temp as $$ declare s public.staff; a public.auth_sessions; begin select * into s from public.staff where id=p_staff_id; if not found then return jsonb_build_object('success',false,'error','not_found'); end if; select * into a from private.auth(p_auth_token); if not found or a.principal_type is distinct from 'staff' or a.restaurant_id<>s.restaurant_id or not exists(select 1 from public.staff where id=a.principal_id and role='manager') then return jsonb_build_object('success',false,'error','unauthorized'); end if; if p_new_pin !~ '^[0-9]{4}$' then return jsonb_build_object('success',false,'error','pin_must_be_4_digits'); end if; update public.staff set pin_hash=crypt(p_new_pin,gen_salt('bf')),failed_login_attempts=0,locked_until=null where id=p_staff_id; return jsonb_build_object('success',true); end; $$;

create or replace function public.get_my_progress(p_staff_id uuid,p_auth_token text default null)
returns setof public.module_progress language sql security definer set search_path=public,private,pg_temp as $$ select p.* from public.module_progress p where p.staff_id=p_staff_id and exists(select 1 from private.auth(p_auth_token) a where a.principal_type='staff' and a.principal_id=p_staff_id) order by p.module_id $$;

create or replace function public.upsert_progress(p_staff_id uuid,p_module_id integer,p_status text,p_quiz_score integer,p_quiz_total integer,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if not exists(select 1 from private.auth(p_auth_token) where principal_type='staff' and principal_id=p_staff_id) then return jsonb_build_object('success',false,'error','unauthorized'); end if; insert into public.module_progress(staff_id,module_id,status,quiz_score,quiz_total,started_at,completed_at) values(p_staff_id,p_module_id,p_status,p_quiz_score,p_quiz_total,now(),case when p_status='complete' then now() end) on conflict(staff_id,module_id) do update set status=excluded.status,quiz_score=excluded.quiz_score,quiz_total=excluded.quiz_total,completed_at=case when excluded.status='complete' then now() else public.module_progress.completed_at end,updated_at=now(); return jsonb_build_object('success',true); end; $$;

create or replace function public.start_session(p_staff_id uuid,p_auth_token text default null) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare sid uuid; begin if not exists(select 1 from private.auth(p_auth_token) where principal_type='staff' and principal_id=p_staff_id) then return jsonb_build_object('success',false,'error','unauthorized'); end if; insert into public.sessions(staff_id) values(p_staff_id) returning id into sid; return jsonb_build_object('success',true,'session_id',sid); end; $$;
create or replace function public.heartbeat_session(p_session_id uuid,p_auth_token text default null) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if not exists(select 1 from public.sessions s join private.auth(p_auth_token) a on a.principal_id=s.staff_id where s.id=p_session_id and a.principal_type='staff') then return jsonb_build_object('success',false,'error','unauthorized'); end if; update public.sessions set last_heartbeat=now() where id=p_session_id and ended_at is null; return jsonb_build_object('success',true); end; $$;
create or replace function public.end_session(p_session_id uuid,p_auth_token text default null) returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ begin if not exists(select 1 from public.sessions s join private.auth(p_auth_token) a on a.principal_id=s.staff_id where s.id=p_session_id and a.principal_type='staff') then return jsonb_build_object('success',false,'error','unauthorized'); end if; update public.sessions set ended_at=coalesce(ended_at,now()),last_heartbeat=now() where id=p_session_id; return jsonb_build_object('success',true); end; $$;

create or replace function public.manager_dashboard(p_restaurant_id uuid,p_auth_token text default null)
returns table(staff_id uuid,full_name text,role text,department text,age_range text,sex text,module_id integer,status text,quiz_score integer,quiz_total integer,updated_at timestamptz) language sql security definer set search_path=public,private,pg_temp as $$
  select s.id,s.full_name,s.role,s.department,s.age_range,s.sex,p.module_id,coalesce(p.status,'not_started'),p.quiz_score,p.quiz_total,p.updated_at
  from public.staff s
  left join public.module_progress p on p.staff_id=s.id
  where s.restaurant_id=p_restaurant_id
    and exists (
      select 1 from private.auth(p_auth_token) a
      where a.principal_type='staff'
        and a.restaurant_id=p_restaurant_id
        and exists (select 1 from public.staff m where m.id=a.principal_id and m.role='manager')
    )
  order by s.full_name,p.module_id
$$;
returns table(staff_id uuid,full_name text,role text,module_id integer,status text,quiz_score integer,quiz_total integer,updated_at timestamptz) language sql security definer set search_path=public,private,pg_temp as $$ select s.id,s.full_name,s.role,p.module_id,coalesce(p.status,'not_started'),p.quiz_score,p.quiz_total,p.updated_at from public.staff s left join public.module_progress p on p.staff_id=s.id where s.restaurant_id=p_restaurant_id and exists(select 1 from private.auth(p_auth_token) a where a.principal_type='staff' and a.restaurant_id=p_restaurant_id and exists(select 1 from public.staff m where m.id=a.principal_id and m.role='manager')) order by s.full_name,p.module_id $$;

create or replace function public.owner_monthly_report(p_restaurant_id uuid,p_year integer,p_month integer,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$ declare r public.restaurants; out jsonb; begin if not exists(select 1 from private.auth(p_auth_token) where principal_type='owner') then return jsonb_build_object('error','unauthorized'); end if; select * into r from public.restaurants where id=p_restaurant_id; select jsonb_build_object('restaurant_name',r.name,'month',p_month,'year',p_year,'staff',coalesce(jsonb_agg(jsonb_build_object('staff_id',s.id,'full_name',s.full_name,'role',s.role,'login_count',(select count(*) from public.sessions x where x.staff_id=s.id and x.started_at>=make_date(p_year,p_month,1) and x.started_at<make_date(p_year,p_month,1)+interval '1 month'),'total_seconds',coalesce((select sum(extract(epoch from(coalesce(x.ended_at,x.last_heartbeat)-x.started_at))) from public.sessions x where x.staff_id=s.id and x.started_at>=make_date(p_year,p_month,1) and x.started_at<make_date(p_year,p_month,1)+interval '1 month'),0),'modules_complete',(select count(*) from public.module_progress q where q.staff_id=s.id and q.status='complete'),'last_login',(select max(x.started_at) from public.sessions x where x.staff_id=s.id))), '[]'::jsonb)) into out from public.staff s where s.restaurant_id=p_restaurant_id; return out; end; $$;
