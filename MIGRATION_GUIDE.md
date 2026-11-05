# Karibu Academy V2 setup

1. Create a new Supabase project named `karibu academ`.
2. In SQL Editor, run `01_schema.sql`, then `02_functions.sql`, then `03_security.sql`.
3. Run `04_verification.sql` and confirm the schema/RLS/privilege checks pass and all data counts are zero.
4. Create the first owner manually using a temporary SQL Editor statement. Generate the hash in SQL; never paste a plaintext PIN into a table. Choose a unique, non-sequential four-digit PIN and do not reuse it elsewhere:

```sql
insert into public.owners(full_name, pin_hash)
values ('Your Owner Name', crypt('<CHOOSE-A-UNIQUE-4-DIGIT-PIN>', gen_salt('bf')));
```

Run this only in the new project's SQL Editor, then clear the editor history/session according to your organization's procedures. The PIN is hashed before storage and is never placed in frontend code or browser storage. Change it later through the authenticated `owner_change_pin` RPC using the current owner token and current PIN.

5. Configure `v2/index.html` and `v2/owner-console.html` with the new project's URL and publishable/anon key. Do not put a service-role key in either file. The files currently use placeholders and therefore cannot connect until configured.
6. Deploy the contents of `v2` as a separate site/working copy. Do not point V1 at the new project.
7. Run the 12 verification scenarios listed in the request, including a cross-restaurant attempt using a separate test account. Confirm that unauthorized calls return an error and that no direct table read is possible.

## Important source limitation

The V1 repository does not include the original schema/function SQL. This V2 schema preserves every client-visible table dependency, RPC name, parameter, and return shape that could be established from source, but it cannot prove compatibility with undocumented V1 columns or policies. Review `DATABASE_INVENTORY.md` before production use.

The V2 SQL uses opaque `auth_token` values returned by login RPCs. The frontend must pass the token as `p_auth_token` on subsequent RPC calls; this is required for the requested tenant isolation and owner/manager protection. Logout calls `revoke_token`, and expired or revoked tokens are rejected by `private.auth`.

RLS is intentionally deny-all for direct table access: no table policies grant `anon` or `authenticated` direct reads/writes. All application database access goes through the narrowly scoped protected RPCs. This is deliberate, not an omission.

Login protection is database-enforced per account: five failed PIN attempts cause a 15-minute temporary lockout, and successful login or an authorized PIN reset clears the counter. Login failures return the generic `invalid_credentials` result. Because anonymous PostgREST calls do not provide a sufficiently trusted client-IP boundary for global throttling, production deployment also requires a rate-limited edge/API layer in front of the RPC endpoint to limit distributed attempts and identifier rotation. The database lockout remains the final account-level enforcement.

`private.auth` re-checks owner/staff active status and restaurant active/blocked status on every protected RPC, so deactivation takes effect immediately for existing tokens. Owner PIN rotation revokes all sessions for that owner.
