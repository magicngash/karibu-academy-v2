-- Recover a blank retake created by an older client at the module overview.
-- The row lock and child-row checks make the transition safe across browsers.
create or replace function public.recover_blank_assessment_retake(
  p_attempt_id uuid,
  p_step_index integer,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_attempt public.assessment_attempts;
begin
  select * into v_auth from private.auth(p_auth_token);
  select * into v_attempt
  from public.assessment_attempts
  where id=p_attempt_id
  for update;

  if v_auth.principal_type is distinct from 'staff'
     or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_step_index is null or p_step_index not between 1 and 200 then
    return jsonb_build_object('success',false,'error','invalid_resume_step');
  end if;
  if v_attempt.status<>'in_progress'
     or v_attempt.attempt_number<=1
     or v_attempt.current_step<>0 then
    return jsonb_build_object('success',false,'error','attempt_not_recoverable');
  end if;
  if not exists (
    select 1 from public.assessment_attempts previous_attempt
    where previous_attempt.staff_id=v_attempt.staff_id
      and previous_attempt.module_id=v_attempt.module_id
      and previous_attempt.attempt_number=v_attempt.attempt_number-1
      and previous_attempt.status='failed'
  ) then
    return jsonb_build_object('success',false,'error','previous_attempt_not_failed');
  end if;
  if exists (select 1 from public.assessment_mcq_answers where attempt_id=p_attempt_id)
     or exists (select 1 from public.assessment_written_answers where attempt_id=p_attempt_id)
     or exists (select 1 from public.assessment_written_drafts where attempt_id=p_attempt_id) then
    return jsonb_build_object('success',false,'error','attempt_has_saved_work');
  end if;

  update public.assessment_attempts
  set current_step=p_step_index,updated_at=now()
  where id=p_attempt_id and status='in_progress' and current_step=0;
  if not found then
    return jsonb_build_object('success',false,'error','attempt_not_recoverable');
  end if;
  return jsonb_build_object('success',true,'attempt_id',p_attempt_id,'current_step',p_step_index);
end; $$;

revoke all on function public.recover_blank_assessment_retake(uuid,integer,text)
  from public,anon,authenticated;
grant execute on function public.recover_blank_assessment_retake(uuid,integer,text)
  to anon,authenticated,service_role;
