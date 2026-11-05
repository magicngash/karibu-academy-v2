-- Read-only verification queries for the new empty Supabase project.
-- Run after 03_security.sql. These queries do not create data.

-- 1. All six expected tables.
select table_name from information_schema.tables where table_schema='public' and table_name in ('restaurants','owners','staff','module_progress','sessions','auth_sessions') order by table_name;

-- 2. RLS must be enabled on every expected table.
select c.relname as table_name,c.relrowsecurity as rls_enabled from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('restaurants','owners','staff','module_progress','sessions','auth_sessions') order by c.relname;

-- 3. No direct table privileges for anon/authenticated.
with expected_tables(table_name) as (values ('restaurants'),('owners'),('staff'),('module_progress'),('sessions'),('auth_sessions')), roles(role_name) as (values ('anon'),('authenticated')), privileges(privilege_type) as (values ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER'))
select t.table_name,r.role_name,p.privilege_type,has_table_privilege(r.role_name,'public.'||t.table_name,p.privilege_type) as granted from expected_tables t cross join roles r cross join privileges p order by t.table_name,r.role_name,p.privilege_type;

-- 4. Exact public RPC inventory and signature presence. Every row should have function_found=true.
with expected(name,signature,identity_args) as (values
('create_staff','uuid, text, text, text, text','uuid, text, text, text, text'),('end_session','uuid, text','uuid, text'),('get_my_progress','uuid, text','uuid, text'),('get_restaurant_by_slug','text','text'),('get_restaurant_info','uuid, text','uuid, text'),('heartbeat_session','uuid, text','uuid, text'),('manager_dashboard','uuid, text','uuid, text'),('owner_change_pin','text, text, text','text, text, text'),('owner_create_restaurant','text, text, text, text, text','text, text, text, text, text'),('owner_delete_restaurant','uuid, text','uuid, text'),('owner_list_restaurants','text','text'),('owner_login','text, text, text','text, text, text'),('owner_monthly_report','uuid, integer, integer, text','uuid, integer, integer, text'),('owner_update_branding','uuid, text, text, text','uuid, text, text, text'),('owner_update_restaurant_status','uuid, text, text, text','uuid, text, text, text'),('reset_staff_pin','uuid, text, text','uuid, text, text'),('revoke_token','text','text'),('staff_login','uuid, text, text, text','uuid, text, text, text'),('start_session','uuid, text','uuid, text'),('upsert_progress','uuid, integer, text, integer, integer, text','uuid, integer, text, integer, integer, text'))
select e.name,e.signature,exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=e.name and pg_get_function_identity_arguments(p.oid)=e.identity_args) as function_found from expected e order by e.name;

-- 5. Every expected RPC must be executable by anon/authenticated, but not PUBLIC.
with expected(name,signature) as (values
('create_staff','uuid, text, text, text, text'),('end_session','uuid, text'),('get_my_progress','uuid, text'),('get_restaurant_by_slug','text'),('get_restaurant_info','uuid, text'),('heartbeat_session','uuid, text'),('manager_dashboard','uuid, text'),('owner_change_pin','text, text, text'),('owner_create_restaurant','text, text, text, text, text'),('owner_delete_restaurant','uuid, text'),('owner_list_restaurants','text'),('owner_login','text, text, text'),('owner_monthly_report','uuid, integer, integer, text'),('owner_update_branding','uuid, text, text, text'),('owner_update_restaurant_status','uuid, text, text, text'),('reset_staff_pin','uuid, text, text'),('revoke_token','text'),('staff_login','uuid, text, text, text'),('start_session','uuid, text'),('upsert_progress','uuid, integer, text, integer, integer, text'))
select e.name,e.signature,has_function_privilege('anon','public.'||e.name||'('||e.signature||')','EXECUTE') as anon_execute,has_function_privilege('authenticated','public.'||e.name||'('||e.signature||')','EXECUTE') as authenticated_execute,exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl where n.nspname='public' and p.proname=e.name and pg_get_function_identity_arguments(p.oid)=e.signature and acl.grantee=0) as public_execute from expected e order by e.name;

-- 6. Private helper presence and absence of role execution privileges.
select routine_schema,routine_name from information_schema.routines where routine_schema='private' and routine_name in ('token_hash','auth','issue') order by routine_name;
select has_function_privilege('anon','private.token_hash(text)','EXECUTE') as anon_token_hash_execute,has_function_privilege('authenticated','private.auth(text)','EXECUTE') as authenticated_auth_execute,has_function_privilege('anon','private.issue(text, uuid, uuid)','EXECUTE') as anon_issue_execute;

-- 7. Empty-data check, including auth_sessions.
select (select count(*) from public.restaurants) as restaurants,(select count(*) from public.owners) as owners,(select count(*) from public.staff) as staff,(select count(*) from public.module_progress) as progress,(select count(*) from public.sessions) as sessions,(select count(*) from public.auth_sessions) as auth_sessions;

-- 8. Username uniqueness metadata. Each result should show the expected unique expression/index.
select indexname,indexdef
from pg_indexes
where schemaname='public' and indexname in ('staff_restaurant_name_ci_unique_idx','owners_full_name_ci_idx')
order by indexname;

select conname,pg_get_constraintdef(oid) as constraint_definition
from pg_constraint
where conrelid in ('public.staff'::regclass,'public.owners'::regclass)
  and contype in ('p','u','c')
order by conrelid::text,conname;

-- 9. The create_staff source must contain both the normalized pre-check and
--    a unique_violation handler. This confirms the race-safe RPC contract.
select position('lower(btrim(full_name))' in pg_get_functiondef(p.oid)) > 0 as has_normalized_precheck,
       position('unique_violation' in pg_get_functiondef(p.oid)) > 0 as handles_unique_violation
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='create_staff'
  and pg_get_function_identity_arguments(p.oid)='uuid, text, text, text, text';

-- 10. Manual integration/security scenarios requiring disposable test data.
-- Use two concurrent manager sessions against one restaurant:
-- a. First Grace registration succeeds.
-- b. Grace again with the same PIN returns success=false,error=name_taken.
-- c. Grace again with a different PIN returns success=false,error=name_taken.
-- d. Mary with Grace's PIN succeeds (PINs are not usernames and need not be unique).
-- e. Grace in a different restaurant succeeds.
-- f. Concurrent Grace/Grace and Grace/grace requests allow at most one row;
--    the losing create_staff call returns success=false,error=name_taken.
-- g. Owner names differing only by case or surrounding whitespace cannot coexist.
-- a. Five failed staff PINs cause temporary lockout; correct PIN is rejected until expiry,
--    then succeeds and clears the counter. Repeat for owner_login.
-- b. All login failures return invalid_credentials without account-existence details.
-- c. Deactivate staff/owner or block a restaurant; existing tokens are rejected immediately.
-- d. owner_change_pin revokes every owner auth_sessions row, including the current session.
-- e. Direct table SELECT/INSERT/UPDATE/DELETE through the Data API is denied.
-- f. Protected RPCs without a valid p_auth_token return unauthorized or an empty result.
