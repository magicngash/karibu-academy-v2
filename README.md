# Karibu Academy V2

Static training app and owner console backed by Supabase.

## Netlify deployment

Create a Netlify site from the GitHub repository and set these environment variables:

- `KARIBU_SUPABASE_URL` — defaults to the deployed project URL when omitted.
- `KARIBU_SUPABASE_ANON_KEY` — the Supabase publishable/anon key.
- `SUPABASE_SERVICE_ROLE_KEY` — server-only Supabase service-role key, required by the Netlify assessment functions. Never expose it in browser code or commit it.
- `DEEPSEEK_API_KEY` — server-only DeepSeek API key, required for AI written-answer marking. Never expose it in browser code or commit it.

Netlify runs `npm run build`, which generates the ignored `runtime-config.js` file. The public anon/publishable key must be present in the Netlify build environment. No Supabase secret or service-role key belongs in this repository. Add the two server-only variables in Netlify Site configuration → Environment variables, then redeploy.

## Database migrations

Run the SQL files in order: `01_schema.sql` through `08_security_and_review_fixes.sql`, then `10_manager_review_fixes.sql`, then `11_disable_manual_trainer_scoring.sql`, then `12_owner_staff_progress.sql`. Run `04_verification.sql` after the first three migrations, then run the extended checks in `09_security_verification.sql` after all migrations. Always back up the database before applying migrations 05–08.

The security migration adds tenant ownership, server-authoritative progression, sequential module locking, preservation of earned completions, attempt-specific manager review functions, and the `trial` payment status. Migration `10_manager_review_fixes.sql` adds selected-attempt recalculation and manager audit-history access. Migration `11_disable_manual_trainer_scoring.sql` removes the current manager permission to write manual trainer scores; restore that grant only when manual review is intentionally reintroduced. Migration `12_owner_staff_progress.sql` adds read-only owner/trainer access to staff progress and assessment review. If migration 08 is already installed, run migrations 10, 11, and 12 only; do not rerun 08.

Routes:

- `/training` — staff training app
- `/console` — owner console
- `/<restaurant-slug>` — restaurant-specific training route

## Local checks

`npm test` performs static security and syntax checks. It does not replace live Supabase/RLS integration tests, which must be run against a disposable staging project before production deployment.
