-- Persist required course-guide acknowledgements per staff account and guide version.
-- Access is exclusively through custom-authenticated security-definer RPCs.

create table if not exists public.staff_course_guide_acknowledgements (
  staff_id uuid not null references public.staff(id) on delete cascade,
  guide_version text not null check (guide_version ~ '^[a-z0-9][a-z0-9._-]{0,79}$'),
  acknowledged_at timestamptz not null default now(),
  primary key (staff_id, guide_version)
);

alter table public.staff_course_guide_acknowledgements enable row level security;
revoke all on public.staff_course_guide_acknowledgements from public, anon, authenticated;

create or replace function public.get_course_guide_acknowledgement(
  p_guide_version text,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
begin
  select * into v_auth from private.auth(p_auth_token);
  if v_auth.principal_type is distinct from 'staff' then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_guide_version is null or p_guide_version !~ '^[a-z0-9][a-z0-9._-]{0,79}$' then
    return jsonb_build_object('success',false,'error','invalid_guide_version');
  end if;
  return jsonb_build_object(
    'success',true,
    'acknowledged',exists(
      select 1
      from public.staff_course_guide_acknowledgements a
      where a.staff_id=v_auth.principal_id and a.guide_version=p_guide_version
    )
  );
end; $$;

create or replace function public.acknowledge_course_guide(
  p_guide_version text,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_acknowledged_at timestamptz;
begin
  select * into v_auth from private.auth(p_auth_token);
  if v_auth.principal_type is distinct from 'staff' then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_guide_version is null or p_guide_version !~ '^[a-z0-9][a-z0-9._-]{0,79}$' then
    return jsonb_build_object('success',false,'error','invalid_guide_version');
  end if;
  insert into public.staff_course_guide_acknowledgements(staff_id,guide_version)
  values(v_auth.principal_id,p_guide_version)
  on conflict(staff_id,guide_version) do nothing;
  select a.acknowledged_at into v_acknowledged_at
  from public.staff_course_guide_acknowledgements a
  where a.staff_id=v_auth.principal_id and a.guide_version=p_guide_version;
  return jsonb_build_object(
    'success',true,
    'acknowledged',true,
    'acknowledged_at',v_acknowledged_at
  );
end; $$;

revoke all on function public.get_course_guide_acknowledgement(text,text) from public,anon,authenticated;
revoke all on function public.acknowledge_course_guide(text,text) from public,anon,authenticated;
grant execute on function public.get_course_guide_acknowledgement(text,text) to anon,authenticated,service_role;
grant execute on function public.acknowledge_course_guide(text,text) to anon,authenticated,service_role;
