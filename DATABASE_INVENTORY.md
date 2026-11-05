# Karibu Academy V2 database inventory

## Scope

This is a clean, empty schema for a new Supabase project. No V1 rows, hashes, UUIDs, or historical sessions are included.

The repository contains only `supabase-restaurant-slugs.sql`; it does not contain the original table definitions or the original 17-function SQL. The inventory below is therefore the contract recoverable from the two V1 HTML clients and the slug SQL. Any behavior not visible in those clients is intentionally kept narrow and is called out here.

## Tables

| Table | Purpose | Important fields |
|---|---|---|
| `restaurants` | Tenant, branding, public route, billing state | `id`, `name`, `app_name`, `slug`, `payment_status`, `active`, `payment_note` |
| `owners` | Owner-console identity and login lockout state | `id`, `full_name`, `pin_hash`, `active`, `failed_login_attempts`, `locked_until` |
| `staff` | Restaurant staff, managers, and login lockout state | `restaurant_id`, `full_name`, `pin_hash`, `role`, `active`, `failed_login_attempts`, `locked_until` |
| `module_progress` | One progress row per staff/module | `staff_id`, `module_id`, `status`, quiz score/total |
| `sessions` | Training usage sessions and heartbeat timestamps | `staff_id`, `started_at`, `last_heartbeat`, `ended_at` |
| `auth_sessions` | Opaque authorization tokens returned after PIN login | principal, restaurant, token hash, expiry/revocation |

`auth_sessions` is additional and required. The application calls PostgREST with the public key and does not use Supabase Auth. Without a server-side token table, any browser could submit another staff ID or restaurant ID to a `SECURITY DEFINER` function.

## RPC count

The V2 system now exposes **20** RPCs: the original 18 client/database operations plus two security operations:

`create_staff`, `end_session`, `get_my_progress`, `get_restaurant_by_slug`, `get_restaurant_info`, `heartbeat_session`, `manager_dashboard`, `owner_change_pin`, `owner_create_restaurant`, `owner_delete_restaurant`, `owner_list_restaurants`, `owner_login`, `owner_monthly_report`, `owner_update_branding`, `owner_update_restaurant_status`, `reset_staff_pin`, `revoke_token`, `staff_login`, `start_session`, `upsert_progress`.

## Return contracts recovered from source

- Login/create/update/delete RPCs return JSON with `success`; login returns identity fields and `auth_token`.
- `get_restaurant_by_slug` returns `{id,name,app_name}` or JSON null.
- `get_restaurant_info` returns `{name,app_name}`.
- `get_my_progress` returns rows containing at least `module_id`, `status`, `quiz_score`, `quiz_total`.
- `manager_dashboard` returns flat rows containing `staff_id`, `full_name`, `role`, `module_id`, `status`, `quiz_score`, `quiz_total`, `updated_at`.
- `owner_monthly_report` returns `{restaurant_name, month, year, staff[]}` where each staff item contains `staff_id`, `full_name`, `role`, `login_count`, `total_seconds`, `modules_complete`, and `last_login`.

The original database may have had additional columns or policies not referenced by the application. They cannot be verified from this repository.
