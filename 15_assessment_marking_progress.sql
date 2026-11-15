-- Durable learner-visible status and resumable AI marking for assessment attempts.
-- Apply after 14_fix_owner_restaurant_pgcrypto.sql and before deploying the matching
-- Netlify/frontend changes. Additive only: existing attempts and scores are preserved.

alter table public.assessment_attempts
  add column if not exists marking_lease_token uuid,
  add column if not exists marking_lease_expires_at timestamptz,
  add column if not exists marking_last_error text;

create or replace function public.begin_assessment_marking(
  p_attempt_id uuid,
  p_auth_token text
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_attempt public.assessment_attempts;
  v_lease_token uuid;
  v_scored_count integer;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id for update;
  if v_auth.principal_type is distinct from 'staff'
     or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;

  if v_attempt.status in ('passed','failed','revoked') then
    return jsonb_build_object(
      'success',true,'finalized',true,'status',v_attempt.status,'attempt_id',v_attempt.id,
      'mcq_score',v_attempt.mcq_score,'mcq_total',v_attempt.mcq_total,
      'written_score',v_attempt.written_score,'written_total',v_attempt.written_total,
      'overall_percent',v_attempt.overall_percent,'passed',v_attempt.passed
    );
  end if;

  select count(*) into v_scored_count
  from public.assessment_written_answers w
  where w.attempt_id=p_attempt_id and w.ai_score is not null and w.ai_feedback is not null;

  if v_attempt.status='marking' and v_attempt.marking_lease_expires_at > now() then
    return jsonb_build_object('success',true,'processing',true,'status','marking','scored_count',v_scored_count,'total',5,'lease_expires_at',v_attempt.marking_lease_expires_at);
  end if;
  if v_attempt.status not in ('in_progress','marking') then
    return jsonb_build_object('success',false,'error','invalid_attempt_status');
  end if;
  if (select count(*) from public.assessment_mcq_answers where attempt_id=p_attempt_id)<>5
     or (select count(*) from public.assessment_written_answers where attempt_id=p_attempt_id)<>5
     or (select count(*) from public.assessment_mcq_keys where module_id=v_attempt.module_id and content_version='v1')<>5 then
    return jsonb_build_object('success',false,'error','incomplete_assessment');
  end if;

  v_lease_token:=gen_random_uuid();
  update public.assessment_attempts
  set status='marking',marking_lease_token=v_lease_token,
      marking_lease_expires_at=now()+interval '90 seconds',marking_last_error=null,updated_at=now()
  where id=p_attempt_id;

  return jsonb_build_object(
    'success',true,'status','marking','attempt_id',p_attempt_id,'module_id',v_attempt.module_id,'lease_token',v_lease_token,
    'scored_count',v_scored_count,'total',5,
    'written_answers',coalesce((select jsonb_agg(to_jsonb(w) order by w.question_index)
      from public.assessment_written_answers w where w.attempt_id=p_attempt_id),'[]'::jsonb)
  );
end; $$;

create or replace function public.renew_assessment_marking_lease(
  p_attempt_id uuid,
  p_lease_token uuid,
  p_auth_token text
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_attempt public.assessment_attempts;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id for update;
  if v_auth.principal_type is distinct from 'staff'
     or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if v_attempt.status<>'marking' or v_attempt.marking_lease_token is distinct from p_lease_token
     or v_attempt.marking_lease_expires_at is null or v_attempt.marking_lease_expires_at<=now() then
    return jsonb_build_object('success',false,'error','marking_lease_lost');
  end if;
  update public.assessment_attempts
  set marking_lease_expires_at=now()+interval '90 seconds',updated_at=now()
  where id=p_attempt_id;
  return jsonb_build_object('success',true,'lease_expires_at',now()+interval '90 seconds');
end; $$;

create or replace function public.save_assessment_marking_score(
  p_attempt_id uuid,
  p_question_index integer,
  p_ai_score integer,
  p_ai_feedback text,
  p_lease_token uuid,
  p_auth_token text
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_attempt public.assessment_attempts;
  v_answer public.assessment_written_answers;
  v_scored_count integer;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id for update;
  if v_auth.principal_type is distinct from 'staff'
     or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if v_attempt.status<>'marking' or v_attempt.marking_lease_token is distinct from p_lease_token
     or v_attempt.marking_lease_expires_at is null or v_attempt.marking_lease_expires_at<=now() then
    return jsonb_build_object('success',false,'error','marking_lease_lost');
  end if;
  if p_question_index is null or p_ai_score is null or p_question_index not between 0 and 4
     or p_ai_score not between 0 and 2 or p_ai_feedback is null or length(p_ai_feedback)>2000 then
    return jsonb_build_object('success',false,'error','invalid_marking_result');
  end if;

  select * into v_answer from public.assessment_written_answers
  where attempt_id=p_attempt_id and question_index=p_question_index for update;
  if v_answer.attempt_id is null then
    return jsonb_build_object('success',false,'error','written_answer_not_found');
  end if;
  if v_answer.ai_score is null or v_answer.ai_feedback is null then
    update public.assessment_written_answers
    set ai_score=p_ai_score,ai_feedback=p_ai_feedback,updated_at=now()
    where attempt_id=p_attempt_id and question_index=p_question_index;
  end if;
  update public.assessment_attempts
  set marking_lease_expires_at=now()+interval '90 seconds',updated_at=now()
  where id=p_attempt_id;
  select count(*) into v_scored_count
  from public.assessment_written_answers w
  where w.attempt_id=p_attempt_id and w.ai_score is not null and w.ai_feedback is not null;
  select * into v_answer from public.assessment_written_answers
  where attempt_id=p_attempt_id and question_index=p_question_index;
  return jsonb_build_object('success',true,'question_index',p_question_index,
    'score',v_answer.ai_score,'feedback',v_answer.ai_feedback,'scored_count',v_scored_count,'total',5);
end; $$;

create or replace function public.pause_assessment_marking(
  p_attempt_id uuid,
  p_lease_token uuid,
  p_error_code text,
  p_auth_token text
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_attempt public.assessment_attempts;
  v_error text;
  v_scored_count integer;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id for update;
  if v_auth.principal_type is distinct from 'staff'
     or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if v_attempt.status='marking' and v_attempt.marking_lease_token=p_lease_token then
    v_error:=case when coalesce(p_error_code,'') ~ '^[a-z0-9_]{1,80}$' then p_error_code else 'marking_failed' end;
    update public.assessment_attempts
    set status='in_progress',marking_lease_token=null,marking_lease_expires_at=null,
        marking_last_error=v_error,updated_at=now()
    where id=p_attempt_id;
  end if;
  select count(*) into v_scored_count from public.assessment_written_answers w
  where w.attempt_id=p_attempt_id and w.ai_score is not null and w.ai_feedback is not null;
  return jsonb_build_object('success',true,'status','in_progress','scored_count',v_scored_count,'total',5);
end; $$;

create or replace function public.finalize_assessment_marking(
  p_attempt_id uuid,
  p_auth_token text,
  p_lease_token uuid
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
  v_prior_complete boolean;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id for update;
  if v_auth.principal_type is distinct from 'staff'
     or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if v_attempt.status in ('passed','failed','revoked') then
    return jsonb_build_object('success',true,'status',v_attempt.status,'attempt_id',v_attempt.id,
      'mcq_score',v_attempt.mcq_score,'mcq_total',v_attempt.mcq_total,
      'written_score',v_attempt.written_score,'written_total',v_attempt.written_total,
      'overall_percent',v_attempt.overall_percent,'passed',v_attempt.passed,'already_finalized',true);
  end if;
  if v_attempt.status<>'marking' or v_attempt.marking_lease_token is distinct from p_lease_token
     or v_attempt.marking_lease_expires_at is null or v_attempt.marking_lease_expires_at<=now() then
    return jsonb_build_object('success',false,'error','marking_lease_lost');
  end if;
  if (select count(*) from public.assessment_mcq_answers where attempt_id=p_attempt_id)<>5
     or (select count(*) from public.assessment_mcq_keys where module_id=v_attempt.module_id and content_version='v1')<>5
     or (select count(*) from public.assessment_written_answers where attempt_id=p_attempt_id)<>5
     or (select count(*) from public.assessment_written_answers where attempt_id=p_attempt_id and ai_score is not null and ai_feedback is not null)<>5 then
    return jsonb_build_object('success',false,'error','incomplete_assessment');
  end if;

  select count(*) into v_mcq_total from public.assessment_mcq_keys
  where module_id=v_attempt.module_id and content_version='v1';
  select count(*) into v_mcq_score
  from public.assessment_mcq_answers a
  join public.assessment_mcq_keys k on k.module_id=v_attempt.module_id
    and k.question_index=a.question_index and k.content_version='v1'
    and k.correct_option_index=a.selected_option_index
  where a.attempt_id=p_attempt_id;
  select coalesce(sum(coalesce(trainer_score,ai_score)),0),count(*)*2
    into v_written_score,v_written_total
  from public.assessment_written_answers where attempt_id=p_attempt_id;
  v_overall:=round(((v_mcq_score::numeric/nullif(v_mcq_total,0))*50)+((v_written_score::numeric/nullif(v_written_total,0))*50),2);
  v_passed:=v_overall>=80;
  select status='complete' into v_prior_complete
  from public.module_progress where staff_id=v_attempt.staff_id and module_id=v_attempt.module_id;

  update public.assessment_attempts
  set status=case when v_passed then 'passed' else 'failed' end,
      mcq_score=v_mcq_score,mcq_total=v_mcq_total,written_score=v_written_score,
      written_total=v_written_total,overall_percent=v_overall,passed=v_passed,
      completed_at=now(),marking_lease_token=null,marking_lease_expires_at=null,
      marking_last_error=null,updated_at=now()
  where id=p_attempt_id;
  insert into public.module_progress(staff_id,module_id,status,quiz_score,quiz_total,started_at,completed_at)
  values(v_attempt.staff_id,v_attempt.module_id,
    case when v_passed or coalesce(v_prior_complete,false) then 'complete' else 'in_progress' end,
    v_mcq_score,v_mcq_total,now(),case when v_passed or coalesce(v_prior_complete,false) then now() end)
  on conflict(staff_id,module_id) do update set
    status=case when public.module_progress.status='complete' or excluded.status='complete' then 'complete' else excluded.status end,
    quiz_score=excluded.quiz_score,quiz_total=excluded.quiz_total,
    completed_at=case when public.module_progress.status='complete' then public.module_progress.completed_at
      when excluded.status='complete' then coalesce(public.module_progress.completed_at,now())
      else public.module_progress.completed_at end,
    updated_at=now();
  insert into public.assessment_audit_events(attempt_id,actor_id,actor_role,event_type,details)
  values(p_attempt_id,v_attempt.staff_id,'staff','assessment_completed',jsonb_build_object('passed',v_passed,'overall_percent',v_overall));
  return jsonb_build_object('success',true,'status',case when v_passed then 'passed' else 'failed' end,
    'attempt_id',p_attempt_id,'mcq_score',v_mcq_score,'mcq_total',v_mcq_total,
    'written_score',v_written_score,'written_total',v_written_total,
    'overall_percent',v_overall,'passed',v_passed);
end; $$;

revoke all on function public.begin_assessment_marking(uuid,text) from public,anon,authenticated;
revoke all on function public.renew_assessment_marking_lease(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.save_assessment_marking_score(uuid,integer,integer,text,uuid,text) from public,anon,authenticated;
revoke all on function public.pause_assessment_marking(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.finalize_assessment_marking(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.begin_assessment_marking(uuid,text) to service_role;
grant execute on function public.renew_assessment_marking_lease(uuid,uuid,text) to service_role;
grant execute on function public.save_assessment_marking_score(uuid,integer,integer,text,uuid,text) to service_role;
grant execute on function public.pause_assessment_marking(uuid,uuid,text,text) to service_role;
grant execute on function public.finalize_assessment_marking(uuid,text,uuid) to service_role;
