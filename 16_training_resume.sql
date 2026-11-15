-- Cross-browser training resume position and written-answer draft persistence.
-- Apply after 15_assessment_marking_progress.sql and before deploying the matching app code.
-- The custom staff auth token is checked in every security-definer RPC.

alter table public.assessment_attempts
  add column if not exists current_step integer not null default 0;

create table if not exists public.assessment_written_drafts (
  attempt_id uuid not null references public.assessment_attempts(id) on delete cascade,
  question_index integer not null check (question_index between 0 and 4),
  draft_answer text not null check (length(btrim(draft_answer)) between 1 and 10000),
  updated_at timestamptz not null default now(),
  primary key (attempt_id, question_index)
);

alter table public.assessment_written_drafts enable row level security;
revoke all on public.assessment_written_drafts from public, anon, authenticated;

create or replace function public.save_assessment_resume_step(
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
  select * into v_attempt from public.assessment_attempts where id=p_attempt_id for update;
  if v_auth.principal_type is distinct from 'staff'
     or v_attempt.staff_id is distinct from v_auth.principal_id then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_step_index is null or p_step_index not between 0 and 200 then
    return jsonb_build_object('success',false,'error','invalid_resume_step');
  end if;
  if v_attempt.status not in ('in_progress','marking') then
    return jsonb_build_object('success',false,'error','attempt_not_resumable');
  end if;
  update public.assessment_attempts
  set current_step=p_step_index,updated_at=now()
  where id=p_attempt_id;
  return jsonb_build_object('success',true,'attempt_id',p_attempt_id,'current_step',p_step_index);
end; $$;

create or replace function public.get_latest_training_resume(
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare
  v_auth public.auth_sessions;
  v_resume jsonb;
begin
  select * into v_auth from private.auth(p_auth_token);
  if v_auth.principal_type is distinct from 'staff' then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  select jsonb_build_object(
    'attempt',to_jsonb(a),
    'written_answers',coalesce((select jsonb_agg(to_jsonb(w) order by w.question_index)
      from public.assessment_written_answers w where w.attempt_id=a.id),'[]'::jsonb),
    'mcq_answers',coalesce((select jsonb_agg(to_jsonb(m) order by m.question_index)
      from public.assessment_mcq_answers m where m.attempt_id=a.id),'[]'::jsonb),
    'written_drafts',coalesce((select jsonb_agg(to_jsonb(d) order by d.question_index)
      from public.assessment_written_drafts d where d.attempt_id=a.id),'[]'::jsonb)
  ) into v_resume
  from public.assessment_attempts a
  where a.staff_id=v_auth.principal_id and a.status in ('in_progress','marking')
  order by a.updated_at desc,a.created_at desc
  limit 1;
  return jsonb_build_object('success',true,'resume',v_resume);
end; $$;

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
  values(p_attempt_id,p_question_index,btrim(p_answer),now())
  on conflict(attempt_id,question_index) do update
    set draft_answer=excluded.draft_answer,updated_at=now();
  update public.assessment_attempts set updated_at=now() where id=p_attempt_id;
  return jsonb_build_object('success',true,'question_index',p_question_index,'saved_at',now());
end; $$;

-- Explicitly submitted answers replace any draft and remain compatible with old clients.
create or replace function public.save_assessment_written_answer(
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
     or length(btrim(coalesce(p_answer,'')))<1 or length(p_answer)>10000 then
    return jsonb_build_object('success',false,'error','invalid_answer');
  end if;
  insert into public.assessment_written_answers(attempt_id,question_index,answer)
  values(p_attempt_id,p_question_index,btrim(p_answer))
  on conflict(attempt_id,question_index) do update
    set answer=excluded.answer,ai_score=null,ai_feedback=null,updated_at=now();
  delete from public.assessment_written_drafts
  where attempt_id=p_attempt_id and question_index=p_question_index;
  update public.assessment_attempts set updated_at=now() where id=p_attempt_id;
  return jsonb_build_object('success',true);
end; $$;

revoke all on function public.save_assessment_resume_step(uuid,integer,text) from public,anon,authenticated;
revoke all on function public.get_latest_training_resume(text) from public,anon,authenticated;
revoke all on function public.save_assessment_written_draft(uuid,integer,text,text) from public,anon,authenticated;
revoke all on function public.save_assessment_written_answer(uuid,integer,text,text) from public,anon,authenticated;
grant execute on function public.save_assessment_resume_step(uuid,integer,text) to anon,authenticated,service_role;
grant execute on function public.get_latest_training_resume(text) to anon,authenticated,service_role;
grant execute on function public.save_assessment_written_draft(uuid,integer,text,text) to anon,authenticated,service_role;
grant execute on function public.save_assessment_written_answer(uuid,integer,text,text) to anon,authenticated,service_role;
