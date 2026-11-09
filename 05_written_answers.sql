-- Karibu Academy V2: written-answer storage and manager review
-- Run after 03_security.sql, then rerun the grants section below.

create table if not exists public.written_answers (
  staff_id uuid not null references public.staff(id) on delete cascade,
  module_id integer not null check (module_id > 0),
  question_index integer not null check (question_index between 0 and 4),
  answer text not null check (length(btrim(answer)) between 1 and 10000),
  trainer_score integer check (trainer_score is null or trainer_score between 0 and 2),
  trainer_feedback text,
  ai_score integer check (ai_score is null or ai_score between 0 and 2),
  ai_feedback text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (staff_id, module_id, question_index)
);

create index if not exists written_answers_staff_module_idx
  on public.written_answers (staff_id, module_id);

alter table public.written_answers enable row level security;
revoke all on public.written_answers from anon, authenticated;

create or replace function public.save_written_answer(
  p_staff_id uuid,
  p_module_id integer,
  p_question_index integer,
  p_answer text,
  p_auth_token text default null
)
returns jsonb language plpgsql security definer
set search_path=public,private,pg_temp as $$
begin
  if not exists (
    select 1 from private.auth(p_auth_token) a
    where a.principal_type='staff' and a.principal_id=p_staff_id
  ) then
    return jsonb_build_object('success',false,'error','unauthorized');
  end if;
  if p_module_id <= 0 or p_question_index not between 0 and 4 then
    return jsonb_build_object('success',false,'error','invalid_question');
  end if;
  if length(btrim(coalesce(p_answer,''))) < 1 or length(p_answer) > 10000 then
    return jsonb_build_object('success',false,'error','invalid_answer');
  end if;
  insert into public.written_answers(staff_id,module_id,question_index,answer)
  values(p_staff_id,p_module_id,p_question_index,btrim(p_answer))
  on conflict(staff_id,module_id,question_index) do update set
    answer=excluded.answer,
    updated_at=now();
  return jsonb_build_object('success',true);
end; $$;

create or replace function public.manager_written_answers(
  p_restaurant_id uuid,
  p_staff_id uuid,
  p_module_id integer,
  p_auth_token text default null
)
returns table(
  staff_id uuid,
  module_id integer,
  question_index integer,
  answer text,
  trainer_score integer,
  trainer_feedback text,
  ai_score integer,
  ai_feedback text,
  updated_at timestamptz
) language sql security definer
set search_path=public,private,pg_temp as $$
  select w.staff_id,w.module_id,w.question_index,w.answer,w.trainer_score,
         w.trainer_feedback,w.ai_score,w.ai_feedback,w.updated_at
  from public.written_answers w
  where w.staff_id=p_staff_id
    and w.module_id=p_module_id
    and exists(
      select 1
      from private.auth(p_auth_token) a
      join public.staff m on m.id=a.principal_id
      where a.principal_type='staff'
        and a.restaurant_id=p_restaurant_id
        and m.role='manager'
        and exists(select 1 from public.staff s where s.id=p_staff_id and s.restaurant_id=p_restaurant_id)
    )
  order by w.question_index;
$$;

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
  select * into r from public.staff where r.id=p_staff_id;
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

do $$ declare f text; begin
  foreach f in array array[
    'save_written_answer(uuid,integer,integer,text,text)',
    'manager_written_answers(uuid,uuid,integer,text)',
    'review_written_answer(uuid,integer,integer,integer,text,text)'
  ] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;
