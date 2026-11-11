-- Karibu Academy V2: owner/trainer read-only staff progress access.
-- Run after 11_disable_manual_trainer_scoring.sql.

create or replace function public.owner_staff_progress(
  p_restaurant_id uuid,
  p_auth_token text default null
)
returns table(staff_id uuid,full_name text,role text,module_id integer,status text,quiz_score integer,quiz_total integer,updated_at timestamptz)
language sql security definer set search_path=public,private,pg_temp as $$
  select s.id,s.full_name,s.role,p.module_id,coalesce(p.status,'not_started'),p.quiz_score,p.quiz_total,p.updated_at
  from public.staff s
  left join public.module_progress p on p.staff_id=s.id
  where s.restaurant_id=p_restaurant_id
    and exists(
      select 1 from private.auth(a)
      join public.owner_restaurants x on x.owner_id=a.principal_id and x.restaurant_id=p_restaurant_id
      where a.principal_type='owner'
    )
  order by s.full_name,p.module_id;
$$;

create or replace function public.owner_assessment_attempts(
  p_restaurant_id uuid,
  p_staff_id uuid,
  p_module_id integer,
  p_auth_token text default null
)
returns setof public.assessment_attempts
language sql security definer set search_path=public,private,pg_temp as $$
  select a.*
  from public.assessment_attempts a
  join public.staff target on target.id=a.staff_id and target.restaurant_id=p_restaurant_id
  where a.staff_id=p_staff_id
    and a.module_id=p_module_id
    and exists(
      select 1 from private.auth(x)
      join public.owner_restaurants o on o.owner_id=x.principal_id and o.restaurant_id=p_restaurant_id
      where x.principal_type='owner'
    )
  order by a.attempt_number desc;
$$;

create or replace function public.owner_assessment_written_answers(
  p_restaurant_id uuid,
  p_staff_id uuid,
  p_module_id integer,
  p_attempt_id uuid,
  p_auth_token text default null
)
returns setof public.assessment_written_answers
language sql security definer set search_path=public,private,pg_temp as $$
  select w.*
  from public.assessment_written_answers w
  join public.assessment_attempts a on a.id=w.attempt_id
  join public.staff target on target.id=a.staff_id and target.restaurant_id=p_restaurant_id
  where a.id=p_attempt_id and a.staff_id=p_staff_id and a.module_id=p_module_id
    and exists(
      select 1 from private.auth(x)
      join public.owner_restaurants o on o.owner_id=x.principal_id and o.restaurant_id=p_restaurant_id
      where x.principal_type='owner'
    )
  order by w.question_index;
$$;

create or replace function public.owner_assessment_audit_events(
  p_restaurant_id uuid,
  p_attempt_id uuid,
  p_auth_token text default null
)
returns setof jsonb
language sql security definer set search_path=public,private,pg_temp as $$
  select jsonb_build_object('id',e.id,'attempt_id',e.attempt_id,'actor_id',e.actor_id,'actor_role',e.actor_role,'event_type',e.event_type,'reason',e.reason,'details',e.details,'created_at',e.created_at)
  from public.assessment_audit_events e
  join public.assessment_attempts a on a.id=e.attempt_id
  join public.staff target on target.id=a.staff_id and target.restaurant_id=p_restaurant_id
  where e.attempt_id=p_attempt_id
    and exists(
      select 1 from private.auth(x)
      join public.owner_restaurants o on o.owner_id=x.principal_id and o.restaurant_id=p_restaurant_id
      where x.principal_type='owner'
    )
  order by e.created_at desc;
$$;

do $$ declare f text; begin
  foreach f in array array[
    'owner_staff_progress(uuid,text)',
    'owner_assessment_attempts(uuid,uuid,integer,text)',
    'owner_assessment_written_answers(uuid,uuid,integer,uuid,text)',
    'owner_assessment_audit_events(uuid,uuid,text)'
  ] loop
    execute 'revoke all on function public.'||f||' from public';
    execute 'grant execute on function public.'||f||' to anon, authenticated';
  end loop;
end $$;
