-- Create a fresh assessment attempt and set its first exam step atomically.
-- This prevents a retake from opening with an unsaved cross-browser position.
create or replace function public.start_assessment_retake_attempt(
  p_staff_id uuid,
  p_module_id integer,
  p_step_index integer,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_start jsonb;
  v_attempt_id uuid;
begin
  if p_step_index is null or p_step_index not between 0 and 200 then
    return jsonb_build_object('success',false,'error','invalid_resume_step');
  end if;

  -- Reuse the existing auth, module-lock, uniqueness and attempt-number rules.
  v_start := public.start_assessment_attempt(p_staff_id,p_module_id,p_auth_token);
  if coalesce((v_start->>'success')::boolean,false) is not true then
    return v_start;
  end if;
  if coalesce((v_start->>'resumed')::boolean,false) then
    return v_start;
  end if;

  v_attempt_id := nullif(v_start->>'attempt_id','')::uuid;
  if v_attempt_id is null then
    raise exception 'retake_attempt_id_missing';
  end if;

  update public.assessment_attempts
  set current_step=p_step_index,updated_at=now()
  where id=v_attempt_id
    and staff_id=p_staff_id
    and module_id=p_module_id
    and status='in_progress';
  if not found then
    raise exception 'retake_attempt_step_save_failed';
  end if;

  return v_start || jsonb_build_object('current_step',p_step_index);
end; $$;

revoke all on function public.start_assessment_retake_attempt(uuid,integer,integer,text)
  from public,anon,authenticated;
grant execute on function public.start_assessment_retake_attempt(uuid,integer,integer,text)
  to anon,authenticated,service_role;
