-- RLS and grants. Run after 02_functions.sql.

alter table public.restaurants enable row level security;
alter table public.owners enable row level security;
alter table public.staff enable row level security;
alter table public.module_progress enable row level security;
alter table public.sessions enable row level security;
alter table public.auth_sessions enable row level security;

-- Direct table access is denied. The narrowly scoped SECURITY DEFINER RPCs are the API.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;

do $$ declare f text; begin
  foreach f in array array['get_restaurant_by_slug(text)','get_restaurant_info(uuid,text)','owner_login(text,text,text)','revoke_token(text)','owner_change_pin(text,text,text)','staff_login(uuid,text,text,text)','owner_list_restaurants(text)','owner_create_restaurant(text,text,text,text,text)','owner_update_branding(uuid,text,text,text)','owner_update_restaurant_status(uuid,text,text,text)','owner_delete_restaurant(uuid,text)','create_staff(uuid,text,text,text,text)','reset_staff_pin(uuid,text,text)','get_my_progress(uuid,text)','upsert_progress(uuid,integer,text,integer,integer,text)','start_session(uuid,text)','heartbeat_session(uuid,text)','end_session(uuid,text)','manager_dashboard(uuid,text)','owner_monthly_report(uuid,integer,integer,text)'] loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
end $$;

revoke all on function public.touch_updated_at() from public, anon, authenticated;
revoke all on function public.make_restaurant_slug() from public, anon, authenticated;
revoke all on function private.token_hash(text) from public, anon, authenticated;
revoke all on function private.auth(text) from public, anon, authenticated;
revoke all on function private.issue(text,uuid,uuid) from public, anon, authenticated;
