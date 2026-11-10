-- Karibu Academy V2: additive assessment attempts and authoritative scoring.
-- Do not run until the database backup and migration checklist are complete.

create table if not exists public.assessment_attempts (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  module_id integer not null check (module_id > 0),
  attempt_number integer not null check (attempt_number > 0),
  status text not null default 'in_progress' check (status in ('in_progress','marking','passed','failed','revoked')),
  mcq_score integer,
  mcq_total integer,
  written_score integer,
  written_total integer,
  overall_percent numeric(5,2),
  passed boolean,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(staff_id, module_id, attempt_number)
);

create unique index if not exists assessment_attempts_one_active_idx
  on public.assessment_attempts(staff_id, module_id)
  where status in ('in_progress','marking');

create table if not exists public.assessment_mcq_answers (
  attempt_id uuid not null references public.assessment_attempts(id) on delete cascade,
  question_index integer not null check (question_index between 0 and 4),
  selected_option_index integer not null check (selected_option_index >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (attempt_id, question_index)
);

create table if not exists public.assessment_written_answers (
  attempt_id uuid not null references public.assessment_attempts(id) on delete cascade,
  question_index integer not null check (question_index between 0 and 4),
  answer text not null check (length(btrim(answer)) between 1 and 10000),
  ai_score integer check (ai_score is null or ai_score between 0 and 2),
  ai_feedback text,
  trainer_score integer check (trainer_score is null or trainer_score between 0 and 2),
  trainer_feedback text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (attempt_id, question_index)
);

create table if not exists public.assessment_mcq_keys (
  module_id integer not null check (module_id > 0),
  question_index integer not null check (question_index between 0 and 4),
  correct_option_index integer not null check (correct_option_index >= 0),
  content_version text not null default 'v1',
  primary key (module_id, question_index, content_version)
);

create table if not exists public.assessment_audit_events (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.assessment_attempts(id) on delete cascade,
  actor_id uuid,
  actor_role text,
  event_type text not null,
  reason text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

insert into public.assessment_mcq_keys(module_id,question_index,correct_option_index,content_version)
values
  (1,0,1,'v1'),(1,1,1,'v1'),(1,2,0,'v1'),(1,3,2,'v1'),(1,4,0,'v1'),
  (2,0,1,'v1'),(2,1,1,'v1'),(2,2,2,'v1'),(2,3,0,'v1'),(2,4,0,'v1'),
  (3,0,1,'v1'),(3,1,1,'v1'),(3,2,0,'v1'),(3,3,0,'v1'),(3,4,1,'v1'),
  (4,0,1,'v1'),(4,1,1,'v1'),(4,2,0,'v1'),(4,3,0,'v1'),(4,4,1,'v1'),
  (5,0,1,'v1'),(5,1,1,'v1'),(5,2,0,'v1'),(5,3,0,'v1'),(5,4,1,'v1'),
  (6,0,1,'v1'),(6,1,1,'v1'),(6,2,0,'v1'),(6,3,1,'v1'),(6,4,1,'v1'),
  (7,0,0,'v1'),(7,1,1,'v1'),(7,2,0,'v1'),(7,3,0,'v1'),(7,4,0,'v1'),
  (8,0,0,'v1'),(8,1,0,'v1'),(8,2,1,'v1'),(8,3,1,'v1'),(8,4,1,'v1'),
  (9,0,0,'v1'),(9,1,0,'v1'),(9,2,0,'v1'),(9,3,1,'v1'),(9,4,0,'v1'),
  (10,0,0,'v1'),(10,1,0,'v1'),(10,2,0,'v1'),(10,3,0,'v1'),(10,4,0,'v1')
on conflict(module_id,question_index,content_version) do update set correct_option_index=excluded.correct_option_index;

alter table public.assessment_attempts enable row level security;
alter table public.assessment_mcq_answers enable row level security;
alter table public.assessment_written_answers enable row level security;
alter table public.assessment_mcq_keys enable row level security;
alter table public.assessment_audit_events enable row level security;

revoke all on public.assessment_attempts, public.assessment_mcq_answers,
  public.assessment_written_answers, public.assessment_mcq_keys,
  public.assessment_audit_events from anon, authenticated;

create or replace function public.start_assessment_attempt(
  p_staff_id uuid,
  p_module_id integer,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  a public.auth_sessions;
  existing public.assessment_attempts;
  next_number integer;
  new_id uuid;
begin
  select * into a from private.auth(p_auth_token);
  if a.principal_type is distinct from 'staff' or a.principal_id is distinct from p_staff_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;

  select * into existing
  from public.assessment_attempts
  where staff_id=p_staff_id and module_id=p_module_id and status in ('in_progress','marking')
  order by attempt_number desc
  limit 1
  for update;
  if found then
    return jsonb_build_object('success',true,'attempt_id',existing.id,'attempt_number',existing.attempt_number,'resumed',true);
  end if;

  select coalesce(max(attempt_number),0)+1 into next_number
  from public.assessment_attempts
  where staff_id=p_staff_id and module_id=p_module_id;
  insert into public.assessment_attempts(staff_id,module_id,attempt_number)
  values(p_staff_id,p_module_id,next_number)
  returning id into new_id;
  return jsonb_build_object('success',true,'attempt_id',new_id,'attempt_number',next_number,'resumed',false);
exception when unique_violation then
  select * into existing from public.assessment_attempts
  where staff_id=p_staff_id and module_id=p_module_id and status in ('in_progress','marking')
  order by attempt_number desc limit 1;
  return jsonb_build_object('success',true,'attempt_id',existing.id,'attempt_number',existing.attempt_number,'resumed',true);
end; $$;

create or replace function public.save_mcq_answer(
  p_attempt_id uuid,
  p_question_index integer,
  p_selected_option_index integer,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare a public.auth_sessions; t public.assessment_attempts;
begin
  select * into a from private.auth(p_auth_token);
  select * into t from public.assessment_attempts where id=p_attempt_id;
  if a.principal_type is distinct from 'staff' or t.staff_id is distinct from a.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if t.status <> 'in_progress' or p_question_index not between 0 and 4 or p_selected_option_index < 0 then
    return jsonb_build_object('success',false,'error','invalid_answer');
  end if;
  insert into public.assessment_mcq_answers(attempt_id,question_index,selected_option_index)
  values(p_attempt_id,p_question_index,p_selected_option_index)
  on conflict(attempt_id,question_index) do update set selected_option_index=excluded.selected_option_index,updated_at=now();
  return jsonb_build_object('success',true);
end; $$;

create or replace function public.save_assessment_written_answer(
  p_attempt_id uuid,
  p_question_index integer,
  p_answer text,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare a public.auth_sessions; t public.assessment_attempts;
begin
  select * into a from private.auth(p_auth_token);
  select * into t from public.assessment_attempts where id=p_attempt_id;
  if a.principal_type is distinct from 'staff' or t.staff_id is distinct from a.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if t.status <> 'in_progress' or p_question_index not between 0 and 4 or length(btrim(coalesce(p_answer,''))) < 1 or length(p_answer) > 10000 then
    return jsonb_build_object('success',false,'error','invalid_answer');
  end if;
  insert into public.assessment_written_answers(attempt_id,question_index,answer)
  values(p_attempt_id,p_question_index,btrim(p_answer))
  on conflict(attempt_id,question_index) do update set answer=excluded.answer,ai_score=null,ai_feedback=null,updated_at=now();
  return jsonb_build_object('success',true);
end; $$;

create or replace function public.complete_assessment_internal(
  p_attempt_id uuid,
  p_auth_token text,
  p_ai_scores jsonb
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_attempt public.assessment_attempts;
  v_mcq_score integer;
  v_mcq_total integer;
  v_written_score integer;
  v_written_total integer;
  v_overall numeric(5,2);
  v_passed boolean;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id for update;
  if v_auth.principal_type is distinct from 'staff' or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if v_attempt.status in ('passed','failed','revoked') then
    return jsonb_build_object('success',true,'status',v_attempt.status,'attempt_id',v_attempt.id,'mcq_score',v_attempt.mcq_score,'mcq_total',v_attempt.mcq_total,'written_score',v_attempt.written_score,'written_total',v_attempt.written_total,'overall_percent',v_attempt.overall_percent,'passed',v_attempt.passed,'already_finalized',true);
  end if;
  if v_attempt.status = 'marking' then
    return jsonb_build_object('success',false,'error','already_processing');
  end if;
  if jsonb_typeof(p_ai_scores) <> 'array' or jsonb_array_length(p_ai_scores) <> 5 then
    return jsonb_build_object('success',false,'error','invalid_marking_batch');
  end if;
  if (select count(*) from public.assessment_mcq_answers x where x.attempt_id=v_attempt.id) <> 5
     or (select count(*) from public.assessment_written_answers x where x.attempt_id=v_attempt.id) <> 5
     or (select count(*) from public.assessment_mcq_keys k where k.module_id=v_attempt.module_id and k.content_version='v1') <> 5 then
    return jsonb_build_object('success',false,'error','incomplete_assessment');
  end if;
  if exists(
    select 1 from jsonb_to_recordset(p_ai_scores) as x(question_index integer, score integer, feedback text)
    where x.question_index not between 0 and 4 or x.score not between 0 and 2
  ) then
    return jsonb_build_object('success',false,'error','invalid_marking_result');
  end if;
  if (select count(distinct x.question_index) from jsonb_to_recordset(p_ai_scores) as x(question_index integer, score integer, feedback text)) <> 5 then
    return jsonb_build_object('success',false,'error','invalid_marking_indexes');
  end if;

  update public.assessment_attempts set status='marking',updated_at=now() where id=v_attempt.id;
  update public.assessment_written_answers w
  set ai_score=x.score,ai_feedback=x.feedback,updated_at=now()
  from jsonb_to_recordset(p_ai_scores) as x(question_index integer, score integer, feedback text)
  where w.attempt_id=v_attempt.id and w.question_index=x.question_index;

  select count(*) into v_mcq_total
  from public.assessment_mcq_keys k
  where k.module_id=v_attempt.module_id and k.content_version='v1';
  select count(*) into v_mcq_score
  from public.assessment_mcq_answers a1
  join public.assessment_mcq_keys k
    on k.module_id=v_attempt.module_id and k.question_index=a1.question_index and k.content_version='v1'
   and k.correct_option_index=a1.selected_option_index
  where a1.attempt_id=v_attempt.id;
  select coalesce(sum(coalesce(trainer_score,ai_score)),0), count(*)*2
    into v_written_score,v_written_total
  from public.assessment_written_answers
  where attempt_id=v_attempt.id;
  v_overall := round(((v_mcq_score::numeric / nullif(v_mcq_total,0)) * 50) + ((v_written_score::numeric / nullif(v_written_total,0)) * 50), 2);
  v_passed := v_overall >= 80;

  update public.assessment_attempts a
  set status=case when v_passed then 'passed' else 'failed' end,
      mcq_score=v_mcq_score,mcq_total=v_mcq_total,written_score=v_written_score,
      written_total=v_written_total,overall_percent=v_overall,passed=v_passed,
      completed_at=now(),updated_at=now()
  where a.id=v_attempt.id;
  insert into public.module_progress(staff_id,module_id,status,quiz_score,quiz_total,started_at,completed_at)
  values(v_attempt.staff_id,v_attempt.module_id,case when v_passed then 'complete' else 'in_progress' end,v_mcq_score,v_mcq_total,now(),case when v_passed then now() end)
  on conflict(staff_id,module_id) do update set
    status=excluded.status,quiz_score=excluded.quiz_score,quiz_total=excluded.quiz_total,
    completed_at=case when excluded.status='complete' then now() else public.module_progress.completed_at end,
    updated_at=now();
  insert into public.assessment_audit_events(attempt_id,actor_id,actor_role,event_type,details)
  values(v_attempt.id,v_attempt.staff_id,'staff','assessment_completed',jsonb_build_object('passed',v_passed,'overall_percent',v_overall));
  return jsonb_build_object('success',true,'status',case when v_passed then 'passed' else 'failed' end,'attempt_id',v_attempt.id,'mcq_score',v_mcq_score,'mcq_total',v_mcq_total,'written_score',v_written_score,'written_total',v_written_total,'overall_percent',v_overall,'passed',v_passed);
end; $$;

create or replace function public.get_assessment_attempt_for_staff(
  p_attempt_id uuid,
  p_auth_token text
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_attempt public.assessment_attempts;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id;
  if v_auth.principal_type is distinct from 'staff' or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  return jsonb_build_object(
    'success',true,
    'attempt',to_jsonb(v_attempt),
    'written_answers',coalesce((select jsonb_agg(to_jsonb(w) order by w.question_index) from public.assessment_written_answers w where w.attempt_id=v_attempt.id),'[]'::jsonb),
    'mcq_answers',coalesce((select jsonb_agg(to_jsonb(m) order by m.question_index) from public.assessment_mcq_answers m where m.attempt_id=v_attempt.id),'[]'::jsonb)
  );
end; $$;

create or replace function public.manager_assessment_attempts(
  p_restaurant_id uuid,
  p_staff_id uuid,
  p_module_id integer,
  p_auth_token text default null
)
returns setof public.assessment_attempts language sql security definer
set search_path=public,private,pg_temp as $$
  select a.*
  from public.assessment_attempts a
  join public.staff target on target.id=a.staff_id and target.restaurant_id=p_restaurant_id
  where a.staff_id=p_staff_id
    and a.module_id=p_module_id
    and exists(
      select 1 from private.auth(p_auth_token) s
      join public.staff manager on manager.id=s.principal_id
      where s.principal_type='staff'
        and s.restaurant_id=p_restaurant_id
        and manager.role='manager'
    )
  order by a.attempt_number desc;
$$;

create or replace function public.manager_assessment_written_answers(
  p_restaurant_id uuid,
  p_staff_id uuid,
  p_module_id integer,
  p_attempt_id uuid,
  p_auth_token text default null
)
returns setof public.assessment_written_answers language sql security definer
set search_path=public,private,pg_temp as $$
  select w.*
  from public.assessment_written_answers w
  join public.assessment_attempts a on a.id=w.attempt_id
  join public.staff target on target.id=a.staff_id and target.restaurant_id=p_restaurant_id
  where a.id=p_attempt_id and a.staff_id=p_staff_id and a.module_id=p_module_id
    and exists(
      select 1 from private.auth(p_auth_token) s
      join public.staff manager on manager.id=s.principal_id
      where s.principal_type='staff'
        and s.restaurant_id=p_restaurant_id
        and manager.role='manager'
    )
  order by w.question_index;
$$;

revoke all on function public.start_assessment_attempt(uuid,integer,text) from public;
revoke all on function public.save_mcq_answer(uuid,integer,integer,text) from public;
revoke all on function public.save_assessment_written_answer(uuid,integer,text,text) from public;
revoke all on function public.complete_assessment_internal(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.get_assessment_attempt_for_staff(uuid,text) from public,anon,authenticated;
revoke all on function public.manager_assessment_attempts(uuid,uuid,integer,text) from public;
revoke all on function public.manager_assessment_written_answers(uuid,uuid,integer,uuid,text) from public;
grant execute on function public.start_assessment_attempt(uuid,integer,text) to anon,authenticated;
grant execute on function public.save_mcq_answer(uuid,integer,integer,text) to anon,authenticated;
grant execute on function public.save_assessment_written_answer(uuid,integer,text,text) to anon,authenticated;
grant execute on function public.complete_assessment_internal(uuid,text,jsonb) to service_role;
grant execute on function public.get_assessment_attempt_for_staff(uuid,text) to service_role;
grant execute on function public.manager_assessment_attempts(uuid,uuid,integer,text) to anon,authenticated;
grant execute on function public.manager_assessment_written_answers(uuid,uuid,integer,uuid,text) to anon,authenticated;
