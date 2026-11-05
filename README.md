# Karibu Academy V2

Static training app and owner console backed by Supabase.

## Netlify deployment

Create a Netlify site from the GitHub repository and set these environment variables:

- `KARIBU_SUPABASE_URL` — defaults to the deployed project URL when omitted.
- `KARIBU_SUPABASE_ANON_KEY` — the Supabase publishable/anon key.

Netlify runs `npm run build`, which generates the ignored `runtime-config.js` file. No Supabase secret or service-role key belongs in this repository.

Routes:

- `/training` — staff training app
- `/console` — owner console
- `/<restaurant-slug>` — restaurant-specific training route
