-- Karibu Academy V2: owner/trainer restaurant overview analytics.
-- Run after 12_owner_staff_progress.sql.

create or replace function public.owner_overview(
  p_restaurant_id uuid,
  p_since timestamptz default null,
  p_auth_token text default null
)
returns jsonb
language sql security definer
set search_path=public,private,pg_temp as $$
with authorized as (
  select 1
  from private.auth(p_auth_token) a
  join public.owner_restaurants o on o.owner_id=a.principal_id and o.restaurant_id=p_restaurant_id
  where a.principal_type='owner'
), staff_scope as (
  select s.id,s.full_name,s.role
  from public.staff s
  where s.restaurant_id=p_restaurant_id and exists(select 1 from authorized)
), progress_scope as (
  select p.*
  from public.module_progress p
  join staff_scope s on s.id=p.staff_id
  where p.module_id between 1 and 10
    and (p_since is null or coalesce(p.updated_at,p.completed_at,p.started_at) >= p_since)
), attempts_scope as (
  select a.*
  from public.assessment_attempts a
  join staff_scope s on s.id=a.staff_id
  where a.module_id between 1 and 10
    and (p_since is null or coalesce(a.updated_at,a.completed_at,a.started_at) >= p_since)
), scored_attempts as (
  select * from attempts_scope where overall_percent is not null and status in ('passed','failed')
), latest_attempts as (
  select distinct on (staff_id,module_id) *
  from scored_attempts
  order by staff_id,module_id,attempt_number desc
), module_rows as (
  select m.module_id,
    count(distinct s.id)::integer as staff_count,
    count(distinct case when p.status='complete' then p.staff_id end)::integer as completed_staff,
    count(a.id)::integer as attempts,
    count(case when a.status='passed' then 1 end)::integer as passed,
    count(case when a.status='failed' then 1 end)::integer as failed,
    count(case when a.status in ('in_progress','marking') then 1 end)::integer as awaiting_marking,
    round(avg(a.overall_percent)::numeric,1) as average_score,
    round(avg(case when a.mcq_total>0 then a.mcq_score::numeric/a.mcq_total*100 end),1) as average_mcq
  from generate_series(1,10) m(module_id)
  cross join staff_scope s
  left join progress_scope p on p.module_id=m.module_id and p.staff_id=s.id
  left join attempts_scope a on a.module_id=m.module_id and a.staff_id=s.id
  group by m.module_id
), mcq_question_rows as (
  select a.module_id,ma.question_index,
    count(*)::integer as answered,
    count(*) filter (where ma.selected_option_index=k.correct_option_index)::integer as correct
  from attempts_scope a
  join public.assessment_mcq_answers ma on ma.attempt_id=a.id
  join public.assessment_mcq_keys k on k.module_id=a.module_id and k.question_index=ma.question_index and k.content_version='v1'
  group by a.module_id,ma.question_index
), recent_rows as (
  select a.updated_at as happened_at,'assessment'::text as kind,
    s.full_name,a.module_id,a.status,a.overall_percent
  from attempts_scope a join staff_scope s on s.id=a.staff_id
  order by a.updated_at desc nulls last limit 8
), attention_rows as (
  select 'awaiting_marking'::text as kind,'Attempts awaiting marking'::text as label,count(*)::integer as value
  from attempts_scope where status in ('in_progress','marking')
  union all
  select 'failed_attempts','Failed attempts',count(*)::integer from attempts_scope where status='failed'
  union all
  select 'not_started_staff','Staff with no activity',count(*)::integer
  from staff_scope s where not exists(select 1 from progress_scope p where p.staff_id=s.id)
  union all
  select 'weak_module',format('Module %s below 60%% pass rate',module_id),count(*)::integer
  from module_rows where (passed+failed)>0 and passed::numeric/nullif(passed+failed,0)<0.6
  group by module_id
), metrics as (
  select
    (select count(*) from staff_scope)::integer as staff_total,
    (select count(distinct staff_id) from progress_scope)::integer as staff_started,
    (select count(*) from progress_scope where status='complete')::integer as modules_completed,
    ((select count(*) from staff_scope)*10)::integer as modules_possible,
    (select count(*) from attempts_scope)::integer as attempts_total,
    (select count(*) from attempts_scope where status='passed')::integer as passed_attempts,
    (select count(*) from attempts_scope where status='failed')::integer as failed_attempts,
    (select count(*) from attempts_scope where status in ('in_progress','marking'))::integer as awaiting_marking,
    round((select avg(overall_percent) from latest_attempts)::numeric,1) as average_score,
    round((select avg(case when mcq_total>0 then mcq_score::numeric/mcq_total*100 end) from scored_attempts)::numeric,1) as average_mcq,
    (select count(*) from scored_attempts)::integer as scored_attempts,
    (select count(*) from scored_attempts where attempt_number=1 and passed)::integer as first_passed,
    (select count(*) from scored_attempts where attempt_number=1)::integer as first_scored
)
select case when exists(select 1 from authorized) then jsonb_build_object(
  'metrics',(select to_jsonb(metrics) from metrics),
  'modules',coalesce((select jsonb_agg(to_jsonb(module_rows) order by module_id) from module_rows),'[]'::jsonb),
  'mcq_questions',coalesce((select jsonb_agg(jsonb_build_object('module_id',module_id,'question_index',question_index,'answered',answered,'correct',correct,'correct_rate',round(correct::numeric/nullif(answered,0)*100,1)) order by module_id,question_index) from mcq_question_rows),'[]'::jsonb),
  'attention',coalesce((select jsonb_agg(to_jsonb(attention_rows) order by value desc) from attention_rows where value>0),'[]'::jsonb),
  'recent',coalesce((select jsonb_agg(to_jsonb(recent_rows) order by happened_at desc) from recent_rows),'[]'::jsonb)
) else jsonb_build_object('error','unauthorized') end;
$$;

revoke all on function public.owner_overview(uuid,timestamptz,text) from public;
grant execute on function public.owner_overview(uuid,timestamptz,text) to anon, authenticated;
