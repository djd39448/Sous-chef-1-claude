# Supabase — database

The PostgreSQL schema for Sous Chef AI, as SQL migrations. This is the
executable form of [`../contract/data-model.md`](../contract/data-model.md).

## Migrations

Applied in filename order:

| File | Contents |
|---|---|
| `migrations/20260522000000_initial_schema.sql` | All 11 tables, indexes, constraints, the `updated_at` triggers, and the sign-up → `profiles` trigger. |
| `migrations/20260522000100_rls_policies.sql` | Row-level security: each user sees only their own data. |

## Applying them

You need a Supabase project first — create one at <https://supabase.com> (free
tier is fine). Then either:

**A. Supabase CLI (preferred)**
```sh
brew install supabase/tap/supabase
cd supabase
supabase link --project-ref <your-project-ref>
supabase db push
```

**B. SQL editor**
Open the project's SQL editor and run the two migration files in order.

## What the project gives you

After creating the project, collect these — the Go backend (Phase 3) needs them:

| Value | Where | Used for |
|---|---|---|
| Project URL | Settings → API | iOS Supabase Auth client |
| `anon` public key | Settings → API | iOS Supabase Auth client |
| `service_role` key | Settings → API | (optional) admin access |
| DB connection string | Settings → Database | Backend's direct Postgres connection |
| JWT secret | Settings → API → JWT | Backend validates Supabase access tokens |

Keep `service_role` and the JWT secret out of the iOS app and out of git.

## Auth setup

The iOS app signs in with **Sign in with Apple**. In the Supabase dashboard:
Authentication → Providers → Apple → enable, and add the app's bundle ID and
Apple credentials. (Configured in Phase 4 alongside the Xcode project.)

The `handle_new_user()` trigger creates a `profiles` row on first sign-in. Apple
returns a user's name only once, on first authorization; the trigger stores
`email` and any avatar URL — names can be set later via the profile.

## Notes

- The Go backend connects directly to Postgres and enforces per-user ownership
  in code (as the original Express server did). RLS is enabled as
  defense-in-depth for the auto-generated PostgREST API.
- `auth.users` is managed by Supabase. Every `user_id` references it; deleting a
  user cascades to all their rows.
