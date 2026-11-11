-- Karibu Academy V2: manager attempt history and review recalculation.
-- Run after 08_security_and_review_fixes.sql. This migration is forward-only.
-- Recalculate a finalized attempt after a manager trainer override.
create or replace function public.recalculate_assessment_attempt(
  p_attempt_id uuid,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_attempt public.assessment_attempts;
  v_restaurant uuid;
  v_manager uuid;
  v_mcq_score integer;
  v_mcq_total integer;
  v_written_score integer;
  v_written_total integer;
  v_overall numeric(5,2);
  v_passed boolean;
  v_prior_complete boolean;
begin
  select a.* into v_attempt
  from public.assessment_attempts a
  where a.id=p_attempt_id for update;
  select s.restaurant_id into v_restaurant
  from public.assessment_attempts a join public.staff s on s.id=a.staff_id
  where a.id=p_attempt_id;
  select x.principal_id into v_manager
  from private.auth(p_auth_token) x join public.staff m on m.id=x.principal_id
  where x.principal_type='staff' and x.restaurant_id=v_restaurant and m.role='manager';
  if v_manager is null or v_attempt.id is null then return jsonb_build_object('success',false,'error','unauthorized'); end if;
  select count(*) into v_mcq_total from public.assessment_mcq_keys where module_id=v_attempt.module_id and content_version='v1';
  select count(*) into v_mcq_score
  from public.assessment_mcq_answers a join public.assessment_mcq_keys k
    on k.module_id=v_attempt.module_id and k.question_index=a.question_index
   and k.content_version='v1' and k.correct_option_index=a.selected_option_index
  where a.attempt_id=p_attempt_id;
  select coalesce(sum(coalesce(trainer_score,ai_score)),0),count(*)*2
    into v_written_score,v_written_total
  from public.assessment_written_answers where attempt_id=p_attempt_id;
  if v_mcq_total<>5 or v_written_total<>10 then return jsonb_build_object('success',false,'error','incomplete_assessment'); end if;
  v_overall:=round(((v_mcq_score::numeric/nullif(v_mcq_total,0))*50)+((v_written_score::numeric/nullif(v_written_total,0))*50),2);
  v_passed:=v_overall>=80;
  select status='complete' into v_prior_complete from public.module_progress where staff_id=v_attempt.staff_id and module_id=v_attempt.module_id;
  update public.assessment_attempts set status=case when v_passed then 'passed' else 'failed' end,mcq_score=v_mcq_score,mcq_total=v_mcq_total,written_score=v_written_score,written_total=v_written_total,overall_percent=v_overall,passed=v_passed,updated_at=now() where id=p_attempt_id;
  insert into public.module_progress(staff_id,module_id,status,quiz_score,quiz_total,completed_at)
  values(v_attempt.staff_id,v_attempt.module_id,case when v_passed or coalesce(v_prior_complete,false) then 'complete' else 'in_progress' end,v_mcq_score,v_mcq_total,case when v_passed or coalesce(v_prior_complete,false) then now() end)
  on conflict(staff_id,module_id) do update set status=case when public.module_progress.status='complete' or excluded.status='complete' then 'complete' else excluded.status end,quiz_score=excluded.quiz_score,quiz_total=excluded.quiz_total,completed_at=case when public.module_progress.status='complete' then public.module_progress.completed_at when excluded.status='complete' then now() else public.module_progress.completed_at end,updated_at=now();
  insert into public.assessment_audit_events(attempt_id,actor_id,actor_role,event_type,details) values(p_attempt_id,v_manager,'manager','assessment_recalculated',jsonb_build_object('passed',v_passed,'overall_percent',v_overall));
  return jsonb_build_object('success',true,'attempt_id',p_attempt_id,'mcq_score',v_mcq_score,'mcq_total',v_mcq_total,'written_score',v_written_score,'written_total',v_written_total,'overall_percent',v_overall,'passed',v_passed,'status',case when v_passed then 'passed' else 'failed' end);
end; $$;

create or replace function public.manager_assessment_audit_events(
  p_attempt_id uuid,
  p_auth_token text default null
)
returns setof jsonb language sql security definer
set search_path=public,private,pg_temp as $$
select jsonb_build_object('id',e.id,'attempt_id',e.attempt_id,'actor_id',e.actor_id,'actor_role',e.actor_role,'event_type',e.event_type,'reason',e.reason,'details',e.details,'created_at',e.created_at)
from public.assessment_audit_events e
join public.assessment_attempts a on a.id=e.attempt_id
join public.staff target on target.id=a.staff_id
where e.attempt_id=p_attempt_id and exists(
  select 1 from private.auth(p_auth_token) x join public.staff m on m.id=x.principal_id
  where x.principal_type='staff' and x.restaurant_id=target.restaurant_id and m.role='manager'
)
order by e.created_at desc;
$$;

revoke all on function public.recalculate_assessment_attempt(uuid,text) from public;
revoke all on function public.manager_assessment_audit_events(uuid,text) from public;
grant execute on function public.recalculate_assessment_attempt(uuid,text) to anon,authenticated;
grant execute on function public.manager_assessment_audit_events(uuid,text) to anon,authenticated;
