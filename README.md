# Karibu Academy V2

Static training app and owner console backed by Supabase.

## Netlify deployment

Create a Netlify site from the GitHub repository and set these environment variables:

- `KARIBU_SUPABASE_URL` — defaults to the deployed project URL when omitted.
- `KARIBU_SUPABASE_ANON_KEY` — the Supabase publishable/anon key.

Netlify runs `npm run build`, which generates the ignored `runtime-config.js` file. The public anon/publishable key must be present in the Netlify build environment. No Supabase secret or service-role key belongs in this repository.

## Database migrations

Run the SQL files in order: `01_schema.sql` through `08_security_and_review_fixes.sql`. Run `04_verification.sql` after the first three migrations, then run the extended checks in `09_security_verification.sql` after all migrations. Always back up the database before applying migrations 05–08.

The final migration adds tenant ownership, server-authoritative progression, sequential module locking, preservation of earned completions, attempt-specific manager review functions, and the `trial` payment status.

Routes:

- `/training` — staff training app
- `/console` — owner console
- `/<restaurant-slug>` — restaurant-specific training route

## Local checks

`npm test` performs static security and syntax checks. It does not replace live Supabase/RLS integration tests, which must be run against a disposable staging project before production deployment.
