-- Karibu Academy V2: empty schema
-- Run first in the new Supabase project's SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.restaurants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 1 and 160),
  app_name text not null default 'Karibu Academy' check (length(btrim(app_name)) between 1 and 160),
  slug text not null unique check (slug = lower(slug) and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  payment_status text not null default 'active' check (payment_status in ('active','overdue','blocked')),
  active boolean not null default true,
  payment_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.owners (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(btrim(full_name)) between 1 and 160),
  pin_hash text not null,
  active boolean not null default true,
  failed_login_attempts integer not null default 0 check (failed_login_attempts >= 0),
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop index if exists public.owners_full_name_ci_idx;
create unique index owners_full_name_ci_idx on public.owners (lower(btrim(full_name)));

create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  full_name text not null check (length(btrim(full_name)) between 1 and 160),
  pin_hash text not null,
  role text not null default 'staff' check (role in ('staff','manager')),
  active boolean not null default true,
  failed_login_attempts integer not null default 0 check (failed_login_attempts >= 0),
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists staff_restaurant_idx on public.staff (restaurant_id);
drop index if exists public.staff_name_ci_idx;
create unique index staff_restaurant_name_ci_unique_idx
  on public.staff (restaurant_id, lower(btrim(full_name)));

create table if not exists public.module_progress (
  staff_id uuid not null references public.staff(id) on delete cascade,
  module_id integer not null check (module_id > 0),
  status text not null default 'not_started' check (status in ('not_started','in_progress','complete')),
  quiz_score integer check (quiz_score is null or quiz_score >= 0),
  quiz_total integer check (quiz_total is null or quiz_total > 0),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (staff_id, module_id),
  check (quiz_score is null or quiz_total is not null and quiz_score <= quiz_total)
);

create index if not exists module_progress_staff_status_idx on public.module_progress (staff_id, status);

create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  started_at timestamptz not null default now(),
  last_heartbeat timestamptz not null default now(),
  ended_at timestamptz,
  check (ended_at is null or ended_at >= started_at)
);

create index if not exists sessions_staff_started_idx on public.sessions (staff_id, started_at desc);

create table if not exists public.auth_sessions (
  id uuid primary key default gen_random_uuid(),
  principal_type text not null check (principal_type in ('owner','staff')),
  principal_id uuid not null,
  restaurant_id uuid references public.restaurants(id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '12 hours'),
  revoked_at timestamptz,
  check ((principal_type = 'owner' and restaurant_id is null) or (principal_type = 'staff' and restaurant_id is not null))
);

create index if not exists auth_sessions_principal_idx on public.auth_sessions (principal_type, principal_id);
create index if not exists auth_sessions_expiry_idx on public.auth_sessions (expires_at) where revoked_at is null;

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = pg_catalog, public, pg_temp as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists restaurants_touch_updated_at on public.restaurants;
create trigger restaurants_touch_updated_at before update on public.restaurants for each row execute function public.touch_updated_at();
drop trigger if exists owners_touch_updated_at on public.owners;
create trigger owners_touch_updated_at before update on public.owners for each row execute function public.touch_updated_at();
drop trigger if exists staff_touch_updated_at on public.staff;
create trigger staff_touch_updated_at before update on public.staff for each row execute function public.touch_updated_at();

create or replace function public.make_restaurant_slug()
returns trigger language plpgsql set search_path = pg_catalog, public, pg_temp as $$
declare base_slug text; candidate text; begin
  base_slug := trim(both '-' from lower(regexp_replace(btrim(new.name), '[^a-zA-Z0-9]+', '-', 'g')));
  if base_slug = '' then base_slug := 'restaurant'; end if;
  candidate := base_slug;
  if exists (select 1 from public.restaurants r where r.slug = candidate and r.id <> new.id) then
    candidate := base_slug || '-' || left(replace(new.id::text, '-', ''), 6);
  end if;
  new.slug := candidate; return new;
end; $$;

drop trigger if exists restaurants_set_slug on public.restaurants;
create trigger restaurants_set_slug before insert or update of name on public.restaurants for each row execute function public.make_restaurant_slug();
