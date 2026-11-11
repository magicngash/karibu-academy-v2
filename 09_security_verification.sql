-- Read-only checks for migrations 05–08.

select table_name from information_schema.tables where table_schema='public' and table_name in ('owner_restaurants','assessment_attempts','assessment_mcq_answers','assessment_written_answers','assessment_mcq_keys','assessment_audit_events') order by table_name;
select indexname,indexdef from pg_indexes where schemaname='public' and indexname in ('assessment_attempts_one_active_idx');
select conname,pg_get_constraintdef(oid) from pg_constraint where conrelid='public.restaurants'::regclass and conname='restaurants_payment_status_check';

select routine_name,has_function_privilege('anon',routine_schema||'.'||routine_name||'('||pg_get_function_identity_arguments(p.oid)||')','EXECUTE') as anon_execute
from information_schema.routines r join pg_proc p on p.proname=r.routine_name join pg_namespace n on n.oid=p.pronamespace and n.nspname=r.routine_schema
where r.routine_schema='public' and r.routine_name in ('start_assessment_attempt','complete_assessment_internal','manager_assessment_answer_context','save_attempt_ai_mark','review_assessment_written_answer') order by routine_name;

select has_table_privilege('anon','public.assessment_mcq_keys','SELECT') as anon_can_read_answer_keys,
       has_table_privilege('authenticated','public.assessment_mcq_keys','SELECT') as authenticated_can_read_answer_keys;

select pg_get_functiondef(p.oid) like '%module_locked%' as start_checks_unlock,
       pg_get_functiondef(p.oid) like '%server_authoritative_completion%' as progress_rejects_client_completion
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='start_assessment_attempt';
