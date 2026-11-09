-- Add AI-assist result storage without recreating the written-answer table.
-- Run once after 05_written_answers.sql.

create or replace function public.save_ai_written_answer(
  p_staff_id uuid,
  p_module_id integer,
  p_question_index integer,
  p_ai_score integer,
  p_ai_feedback text default null,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare a public.auth_sessions; r public.staff;
begin
  select * into a from private.auth(p_auth_token);
  select s.* into r from public.staff s where s.id=p_staff_id;
  if a.principal_type is distinct from 'staff'
     or not exists(select 1 from public.staff m where m.id=a.principal_id and m.restaurant_id=r.restaurant_id and m.role='manager') then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_ai_score is not null and p_ai_score not between 0 and 2 then
    return jsonb_build_object('success',false,'error','invalid_score');
  end if;
  update public.written_answers
  set ai_score=p_ai_score,ai_feedback=p_ai_feedback,updated_at=now()
  where staff_id=p_staff_id and module_id=p_module_id and question_index=p_question_index;
  return jsonb_build_object('success',true);
end; $$;

revoke all on function public.save_ai_written_answer(uuid,integer,integer,integer,text,text) from public;
grant execute on function public.save_ai_written_answer(uuid,integer,integer,integer,text,text) to anon, authenticated;

-- Correct the trainer-review RPC as well so the manager relationship is
-- resolved from the target staff row before saving an override.
create or replace function public.review_written_answer(
  p_staff_id uuid,
  p_module_id integer,
  p_question_index integer,
  p_trainer_score integer,
  p_trainer_feedback text default null,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
declare a public.auth_sessions; r public.staff;
begin
  select * into a from private.auth(p_auth_token);
  select s.* into r from public.staff s where s.id=p_staff_id;
  if a.principal_type is distinct from 'staff'
     or not exists(select 1 from public.staff m where m.id=a.principal_id and m.restaurant_id=r.restaurant_id and m.role='manager') then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_trainer_score is not null and p_trainer_score not between 0 and 2 then
    return jsonb_build_object('success',false,'error','invalid_score');
  end if;
  update public.written_answers
  set trainer_score=p_trainer_score,trainer_feedback=p_trainer_feedback,updated_at=now()
  where staff_id=p_staff_id and module_id=p_module_id and question_index=p_question_index;
  return jsonb_build_object('success',true);
end; $$;

revoke all on function public.review_written_answer(uuid,integer,integer,integer,text,text) from public;
grant execute on function public.review_written_answer(uuid,integer,integer,integer,text,text) to anon, authenticated;
