-- Preserve the learner's exact draft text (including a trailing space between words).
-- Submitted answers are still trimmed by the client before explicit submission.
create or replace function public.save_assessment_written_draft(
  p_attempt_id uuid,
  p_question_index integer,
  p_answer text,
  p_auth_token text default null
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
  if v_attempt.status<>'in_progress' or p_question_index is null
     or p_question_index not between 0 and 4
     or length(coalesce(p_answer,''))>10000 then
    return jsonb_build_object('success',false,'error','invalid_answer');
  end if;
  if exists(select 1 from public.assessment_written_answers w
      where w.attempt_id=p_attempt_id and w.question_index=p_question_index) then
    return jsonb_build_object('success',false,'error','answer_already_saved');
  end if;
  if length(btrim(coalesce(p_answer,'')))=0 then
    delete from public.assessment_written_drafts
    where attempt_id=p_attempt_id and question_index=p_question_index;
    update public.assessment_attempts set updated_at=now() where id=p_attempt_id;
    return jsonb_build_object('success',true,'question_index',p_question_index,'cleared',true,'saved_at',now());
  end if;
  insert into public.assessment_written_drafts(attempt_id,question_index,draft_answer,updated_at)
  values(p_attempt_id,p_question_index,p_answer,now())
  on conflict(attempt_id,question_index) do update
    set draft_answer=excluded.draft_answer,updated_at=now();
  update public.assessment_attempts set updated_at=now() where id=p_attempt_id;
  return jsonb_build_object('success',true,'question_index',p_question_index,'saved_at',now());
end; $$;
