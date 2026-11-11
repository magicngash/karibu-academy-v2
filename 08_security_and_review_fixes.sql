-- Karibu Academy V2: security, progression, ownership and review fixes.
-- Run after 07_assessment_attempts.sql on a backed-up database.

-- The owner UI supports trial accounts; keep the database contract aligned.
alter table public.restaurants drop constraint if exists restaurants_payment_status_check;
alter table public.restaurants add constraint restaurants_payment_status_check
  check (payment_status in ('active','trial','overdue','blocked'));

-- Explicit tenant ownership. Existing single-owner installations are backfilled;
-- installations with multiple owners must review this mapping before production.
create table if not exists public.owner_restaurants (
  owner_id uuid not null references public.owners(id) on delete cascade,
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, restaurant_id)
);
alter table public.owner_restaurants enable row level security;
revoke all on public.owner_restaurants from anon, authenticated;
insert into public.owner_restaurants(owner_id, restaurant_id)
select o.id, r.id from public.owners o cross join public.restaurants r
where (select count(*) from public.owners)=1
on conflict do nothing;

-- Never accept a browser-supplied completed status. Completion is written only by
-- the authoritative assessment completion/recalculation functions.
create or replace function public.upsert_progress(
  p_staff_id uuid,p_module_id integer,p_status text,p_quiz_score integer,p_quiz_total integer,p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare existing public.module_progress;
begin
  if not exists(select 1 from private.auth(p_auth_token) where principal_type='staff' and principal_id=p_staff_id) then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_status not in ('not_started','in_progress') then
    return jsonb_build_object('success',false,'error','server_authoritative_completion');
  end if;
  if p_module_id <= 0 or p_quiz_score is not null and (p_quiz_total is null or p_quiz_score < 0 or p_quiz_score > p_quiz_total) then
    return jsonb_build_object('success',false,'error','invalid_progress');
  end if;
  select * into existing from public.module_progress where staff_id=p_staff_id and module_id=p_module_id;
  if existing.status='complete' then
    return jsonb_build_object('success',true,'preserved_complete',true);
  end if;
  insert into public.module_progress(staff_id,module_id,status,quiz_score,quiz_total,started_at)
  values(p_staff_id,p_module_id,p_status,p_quiz_score,p_quiz_total,coalesce(existing.started_at,now()))
  on conflict(staff_id,module_id) do update set
    status=excluded.status,quiz_score=excluded.quiz_score,quiz_total=excluded.quiz_total,updated_at=now();
  return jsonb_build_object('success',true);
end; $$;

-- Enforce sequential unlocking at the database boundary.
create or replace function public.start_assessment_attempt(
  p_staff_id uuid,p_module_id integer,p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare a public.auth_sessions; existing public.assessment_attempts; next_number integer; new_id uuid;
begin
  select * into a from private.auth(p_auth_token);
  if a.principal_type is distinct from 'staff' or a.principal_id is distinct from p_staff_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_module_id < 1 or p_module_id > 10 then
    return jsonb_build_object('success',false,'error','invalid_module');
  end if;
  if p_module_id > 1 and not exists(
    select 1 from public.module_progress where staff_id=p_staff_id and module_id=p_module_id-1 and status='complete'
  ) then
    return jsonb_build_object('success',false,'error','module_locked','required_module',p_module_id-1);
  end if;
  select * into existing from public.assessment_attempts
  where staff_id=p_staff_id and module_id=p_module_id and status in ('in_progress','marking')
  order by attempt_number desc limit 1 for update;
  if found then return jsonb_build_object('success',true,'attempt_id',existing.id,'attempt_number',existing.attempt_number,'resumed',true); end if;
  select coalesce(max(attempt_number),0)+1 into next_number from public.assessment_attempts where staff_id=p_staff_id and module_id=p_module_id;
  insert into public.assessment_attempts(staff_id,module_id,attempt_number) values(p_staff_id,p_module_id,next_number) returning id into new_id;
  return jsonb_build_object('success',true,'attempt_id',new_id,'attempt_number',next_number,'resumed',false);
exception when unique_violation then
  select * into existing from public.assessment_attempts where staff_id=p_staff_id and module_id=p_module_id and status in ('in_progress','marking') order by attempt_number desc limit 1;
  return jsonb_build_object('success',true,'attempt_id',existing.id,'attempt_number',existing.attempt_number,'resumed',true);
end; $$;

-- Preserve an earned completion when a later attempt fails.
create or replace function public.complete_assessment_internal(
  p_attempt_id uuid,p_auth_token text,p_ai_scores jsonb
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare v_auth public.auth_sessions; v_attempt public.assessment_attempts; v_mcq_score integer; v_mcq_total integer; v_written_score integer; v_written_total integer; v_overall numeric(5,2); v_passed boolean; prior_complete boolean;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id for update;
  if v_auth.principal_type is distinct from 'staff' or v_attempt.staff_id is distinct from v_auth.principal_id then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  if v_attempt.status in ('passed','failed','revoked') then return jsonb_build_object('success',true,'status',v_attempt.status,'attempt_id',v_attempt.id,'mcq_score',v_attempt.mcq_score,'mcq_total',v_attempt.mcq_total,'written_score',v_attempt.written_score,'written_total',v_attempt.written_total,'overall_percent',v_attempt.overall_percent,'passed',v_attempt.passed,'already_finalized',true); end if;
  if v_attempt.status='marking' then return jsonb_build_object('success',false,'error','already_processing'); end if;
  if jsonb_typeof(p_ai_scores)<>'array' or jsonb_array_length(p_ai_scores)<>5 then return jsonb_build_object('success',false,'error','invalid_marking_batch'); end if;
  if (select count(*) from public.assessment_mcq_answers where attempt_id=v_attempt.id)<>5 or (select count(*) from public.assessment_written_answers where attempt_id=v_attempt.id)<>5 or (select count(*) from public.assessment_mcq_keys where module_id=v_attempt.module_id and content_version='v1')<>5 then return jsonb_build_object('success',false,'error','incomplete_assessment'); end if;
  if exists(select 1 from jsonb_to_recordset(p_ai_scores) as x(question_index integer,score integer,feedback text) where x.question_index not between 0 and 4 or x.score not between 0 and 2 or x.feedback is null) or (select count(distinct question_index) from jsonb_to_recordset(p_ai_scores) as x(question_index integer,score integer,feedback text))<>5 then return jsonb_build_object('success',false,'error','invalid_marking_result'); end if;
  update public.assessment_attempts set status='marking',updated_at=now() where id=v_attempt.id;
  update public.assessment_written_answers w set ai_score=x.score,ai_feedback=x.feedback,updated_at=now() from jsonb_to_recordset(p_ai_scores) as x(question_index integer,score integer,feedback text) where w.attempt_id=v_attempt.id and w.question_index=x.question_index;
  select count(*) into v_mcq_total from public.assessment_mcq_keys where module_id=v_attempt.module_id and content_version='v1';
  select count(*) into v_mcq_score from public.assessment_mcq_answers a join public.assessment_mcq_keys k on k.module_id=v_attempt.module_id and k.question_index=a.question_index and k.content_version='v1' and k.correct_option_index=a.selected_option_index where a.attempt_id=v_attempt.id;
  select coalesce(sum(coalesce(trainer_score,ai_score)),0),count(*)*2 into v_written_score,v_written_total from public.assessment_written_answers where attempt_id=v_attempt.id;
  v_overall:=round(((v_mcq_score::numeric/nullif(v_mcq_total,0))*50)+((v_written_score::numeric/nullif(v_written_total,0))*50),2); v_passed:=v_overall>=80;
  select status='complete' into prior_complete from public.module_progress where staff_id=v_attempt.staff_id and module_id=v_attempt.module_id;
  update public.assessment_attempts set status=case when v_passed then 'passed' else 'failed' end,mcq_score=v_mcq_score,mcq_total=v_mcq_total,written_score=v_written_score,written_total=v_written_total,overall_percent=v_overall,passed=v_passed,completed_at=now(),updated_at=now() where id=v_attempt.id;
  insert into public.module_progress(staff_id,module_id,status,quiz_score,quiz_total,started_at,completed_at)
  values(v_attempt.staff_id,v_attempt.module_id,case when v_passed or coalesce(prior_complete,false) then 'complete' else 'in_progress' end,v_mcq_score,v_mcq_total,now(),case when v_passed or coalesce(prior_complete,false) then coalesce((select completed_at from public.module_progress where staff_id=v_attempt.staff_id and module_id=v_attempt.module_id),now()) end)
  on conflict(staff_id,module_id) do update set status=case when public.module_progress.status='complete' or excluded.status='complete' then 'complete' else excluded.status end,quiz_score=excluded.quiz_score,quiz_total=excluded.quiz_total,completed_at=case when public.module_progress.status='complete' then public.module_progress.completed_at when excluded.status='complete' then coalesce(public.module_progress.completed_at,now()) else public.module_progress.completed_at end,updated_at=now();
  insert into public.assessment_audit_events(attempt_id,actor_id,actor_role,event_type,details) values(v_attempt.id,v_attempt.staff_id,'staff','assessment_completed',jsonb_build_object('passed',v_passed,'overall_percent',v_overall));
  return jsonb_build_object('success',true,'status',case when v_passed then 'passed' else 'failed' end,'attempt_id',v_attempt.id,'mcq_score',v_mcq_score,'mcq_total',v_mcq_total,'written_score',v_written_score,'written_total',v_written_total,'overall_percent',v_overall,'passed',v_passed);
end; $$;

-- Attempt-specific manager marking context and trainer override.
create or replace function public.manager_assessment_answer_context(p_attempt_id uuid,p_question_index integer,p_auth_token text default null)
returns jsonb language sql security definer set search_path=public,private,pg_temp as $$
select jsonb_build_object('attempt',to_jsonb(a),'answer',to_jsonb(w)) from public.assessment_attempts a join public.staff target on target.id=a.staff_id join public.assessment_written_answers w on w.attempt_id=a.id and w.question_index=p_question_index where a.id=p_attempt_id and exists(select 1 from private.auth(p_auth_token) s join public.staff m on m.id=s.principal_id where s.principal_type='staff' and s.restaurant_id=target.restaurant_id and m.role='manager');
$$;

create or replace function public.review_assessment_written_answer(p_attempt_id uuid,p_question_index integer,p_trainer_score integer,p_trainer_feedback text default null,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare restaurant uuid; manager_id uuid;
begin
  select s.restaurant_id into restaurant from public.assessment_attempts aa join public.staff s on s.id=aa.staff_id where aa.id=p_attempt_id;
  select x.principal_id into manager_id from private.auth(p_auth_token) x join public.staff m on m.id=x.principal_id and m.role='manager' where x.principal_type='staff' and x.restaurant_id=restaurant;
  if manager_id is null or restaurant is null then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  if p_question_index not between 0 and 4 or p_trainer_score is not null and p_trainer_score not between 0 and 2 then return jsonb_build_object('success',false,'error','invalid_score'); end if;
  update public.assessment_written_answers set trainer_score=p_trainer_score,trainer_feedback=p_trainer_feedback,updated_at=now() where attempt_id=p_attempt_id and question_index=p_question_index;
  insert into public.assessment_audit_events(attempt_id,actor_id,actor_role,event_type,details) values(p_attempt_id,manager_id,'manager','trainer_override',jsonb_build_object('question_index',p_question_index,'score',p_trainer_score));
  return jsonb_build_object('success',true);
end; $$;

-- Correct the accidental cross-table reference in the AI mark function above by
-- replacing it with a compact, valid authorization implementation.
create or replace function public.save_attempt_ai_mark(p_attempt_id uuid,p_question_index integer,p_ai_score integer,p_ai_feedback text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare restaurant uuid;
begin
  select s.restaurant_id into restaurant from public.assessment_attempts a join public.staff s on s.id=a.staff_id where a.id=p_attempt_id;
  if not exists(select 1 from private.auth(p_auth_token) x join public.staff m on m.id=x.principal_id where x.principal_type='staff' and x.restaurant_id=restaurant and m.role='manager') then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  if p_question_index not between 0 and 4 or p_ai_score not between 0 and 2 then return jsonb_build_object('success',false,'error','invalid_mark'); end if;
  update public.assessment_written_answers set ai_score=p_ai_score,ai_feedback=p_ai_feedback,updated_at=now() where attempt_id=p_attempt_id and question_index=p_question_index;
  return jsonb_build_object('success',true);
end; $$;

-- Grant only the RPC surface; raw assessment tables remain deny-all.
do $$ declare f text; begin foreach f in array array[
  'upsert_progress(uuid,integer,text,integer,integer,text)',
  'start_assessment_attempt(uuid,integer,text)',
  'manager_assessment_answer_context(uuid,integer,text)',
  'save_attempt_ai_mark(uuid,integer,integer,text,text)',
  'review_assessment_written_answer(uuid,integer,integer,text,text)'
] loop execute 'revoke all on function public.'||f||' from public'; execute 'grant execute on function public.'||f||' to anon, authenticated, service_role'; end loop; end $$;

-- Tenant-scope every owner operation and assign newly created restaurants.
create or replace function public.owner_list_restaurants(p_auth_token text default null)
returns setof jsonb language sql security definer set search_path=public,private,pg_temp as $$
select jsonb_build_object('id',r.id,'name',r.name,'app_name',r.app_name,'slug',r.slug,'payment_status',r.payment_status,'payment_note',r.payment_note)
from public.restaurants r join public.owner_restaurants orx on orx.restaurant_id=r.id
where orx.owner_id=(select principal_id from private.auth(p_auth_token) where principal_type='owner') order by r.name;
$$;

create or replace function public.owner_create_restaurant(p_name text,p_app_name text,p_manager_name text,p_manager_pin text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r public.restaurants; owner_id uuid; base_slug text; candidate_slug text; suffix integer := 1;
begin
  select principal_id into owner_id from private.auth(p_auth_token) where principal_type='owner';
  if owner_id is null then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  if p_manager_pin !~ '^[0-9]{4}$' then return jsonb_build_object('success',false,'error','pin_must_be_4_digits'); end if;
  base_slug := lower(regexp_replace(regexp_replace(btrim(p_name),'[^a-zA-Z0-9]+','-','g'),'^-+|-+$','','g'));
  if base_slug is null or base_slug='' then base_slug := 'restaurant'; end if;
  candidate_slug := base_slug;
  while exists(select 1 from public.restaurants where slug=candidate_slug) loop
    candidate_slug := base_slug || '-' || suffix;
    suffix := suffix + 1;
  end loop;
  insert into public.restaurants(name,app_name,slug) values(btrim(p_name),coalesce(nullif(btrim(p_app_name),''),'Karibu Academy'),candidate_slug) returning * into r;
  insert into public.owner_restaurants(owner_id,restaurant_id) values(owner_id,r.id);
  insert into public.staff(restaurant_id,full_name,pin_hash,role) values(r.id,btrim(p_manager_name),crypt(p_manager_pin,gen_salt('bf')),'manager');
  return jsonb_build_object('success',true,'restaurant_id',r.id);
end; $$;

create or replace function public.owner_update_branding(p_restaurant_id uuid,p_name text,p_app_name text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not exists(select 1 from private.auth(p_auth_token) a join public.owner_restaurants x on x.owner_id=a.principal_id and x.restaurant_id=p_restaurant_id where a.principal_type='owner') then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  update public.restaurants set name=btrim(p_name),app_name=btrim(p_app_name) where id=p_restaurant_id;
  return jsonb_build_object('success',true);
end; $$;

create or replace function public.owner_update_restaurant_status(p_restaurant_id uuid,p_status text,p_note text,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not exists(select 1 from private.auth(p_auth_token) a join public.owner_restaurants x on x.owner_id=a.principal_id and x.restaurant_id=p_restaurant_id where a.principal_type='owner') then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  if p_status not in('active','trial','overdue','blocked') then return jsonb_build_object('success',false,'error','invalid_status'); end if;
  update public.restaurants set payment_status=p_status,active=(p_status<>'blocked'),payment_note=p_note where id=p_restaurant_id;
  return jsonb_build_object('success',true);
end; $$;

create or replace function public.owner_delete_restaurant(p_restaurant_id uuid,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
begin
  if not exists(select 1 from private.auth(p_auth_token) a join public.owner_restaurants x on x.owner_id=a.principal_id and x.restaurant_id=p_restaurant_id where a.principal_type='owner') then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  delete from public.restaurants where id=p_restaurant_id;
  return jsonb_build_object('success',true);
end; $$;

create or replace function public.owner_monthly_report(p_restaurant_id uuid,p_year integer,p_month integer,p_auth_token text default null)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp as $$
declare r public.restaurants; out jsonb;
begin
  if not exists(select 1 from private.auth(p_auth_token) a join public.owner_restaurants x on x.owner_id=a.principal_id and x.restaurant_id=p_restaurant_id where a.principal_type='owner') then return jsonb_build_object('error','unauthorized'); end if;
  select * into r from public.restaurants where id=p_restaurant_id;
  select jsonb_build_object('restaurant_name',r.name,'month',p_month,'year',p_year,'staff',coalesce(jsonb_agg(jsonb_build_object('staff_id',s.id,'full_name',s.full_name,'role',s.role,'login_count',(select count(*) from public.sessions x where x.staff_id=s.id and x.started_at>=make_date(p_year,p_month,1) and x.started_at<make_date(p_year,p_month,1)+interval '1 month'),'total_seconds',coalesce((select sum(extract(epoch from(coalesce(x.ended_at,x.last_heartbeat)-x.started_at))) from public.sessions x where x.staff_id=s.id and x.started_at>=make_date(p_year,p_month,1) and x.started_at<make_date(p_year,p_month,1)+interval '1 month'),0),'modules_complete',(select count(*) from public.module_progress q where q.staff_id=s.id and q.status='complete'),'last_login',(select max(x.started_at) from public.sessions x where x.staff_id=s.id))), '[]'::jsonb)) into out from public.staff s where s.restaurant_id=p_restaurant_id;
  return out;
end; $$;

do $$ declare f text; begin foreach f in array array['owner_list_restaurants(text)','owner_create_restaurant(text,text,text,text,text)','owner_update_branding(uuid,text,text,text)','owner_update_restaurant_status(uuid,text,text,text)','owner_delete_restaurant(uuid,text)','owner_monthly_report(uuid,integer,integer,text)'] loop execute 'revoke all on function public.'||f||' from public'; execute 'grant execute on function public.'||f||' to anon, authenticated'; end loop; end $$;
