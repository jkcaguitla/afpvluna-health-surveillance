# AFP-VLUNA — single-file build

`index.html` is the entire app — CSS, all JS modules, and the AFP-VLUNA
seal (embedded as base64) are inlined into one file. Open it directly in a
browser, or deploy it as-is to Vercel/Cloudflare Pages/any static host.

The only external dependencies are three CDN `<script>` tags (Chart.js,
jsPDF, the Supabase client library) — everything else is in this one file.

Demo login (works immediately, no setup): `admin@afp-vluna.mil.ph` / `Admin@2026`

## What changed in this update

- Removed "OB-GYN Department" from the login page's title — it now just
  reads "AFP Health Surveillance & Records System". (The browser tab title
  still says "...— OB-GYN Department" since that wasn't part of the ask —
  say the word if you want that changed too.)
- **Real, tested Supabase integration** — this is the big one, see below.

## Setting up your Supabase backend

**1. Create the project and run the schema.**
Create a Supabase project, open the SQL Editor, paste the entire contents
of `supabase-schema.sql`, and run it once.

This file has been **verified against a real PostgreSQL instance** (not
just eyeballed) — every `CREATE TABLE`/`CREATE POLICY`/trigger statement
ran clean, and I behavior-tested the actual RLS policies end-to-end using
Supabase's real role/auth model (a mocked `auth.uid()` + non-superuser
`authenticated` role, exactly how Supabase's own API access works):
confirmed pending users can read their own profile but nothing else,
confirmed a regular user cannot self-promote to Admin by calling the API
directly (a privilege-escalation trigger blocks it), confirmed Staff-level
users can create records but not delete them, and confirmed the bootstrap
step below actually works.

**2. Turn off email confirmation** (recommended for this app).
In your Supabase project: Authentication → Providers → Email → turn off
"Confirm email." The app already has its own Admin-approval gate for new
signups, so a second confirm-your-email gate is redundant friction — and
without it, your first signup can finish setting up immediately instead of
waiting on a confirmation link.

**3. Point the app at your project.**
Open `index.html` in a text editor, find `APP_CONFIG` near the top of the
inlined script, and set:
```js
DB_MODE: "supabase",
SUPABASE_URL: "https://YOUR-PROJECT.supabase.co",
SUPABASE_ANON_KEY: "YOUR-ANON-KEY",
```
Both values are in your Supabase project under Settings → API. Save, and
open (or redeploy) `index.html`.

## Making yourself an Admin account

There's no Admin yet to approve the first signup, so it's a one-time manual
step:

1. Open the app (now pointed at your Supabase project) and click **Sign
   up**. Fill in your real details and submit. You'll land on a "pending
   approval" screen — expected, ignore it for now.
2. Go back to the Supabase SQL Editor and run (with your own email):
   ```sql
   update public.users
      set status = 'approved', user_level = 'Admin'
    where email = 'you@example.com';
   ```
   This exact statement is also sitting at the bottom of
   `supabase-schema.sql`, commented out, ready to uncomment and edit.
3. Go back to the app and sign in (or just click Sign In if you're still on
   that screen) — you're now an approved Admin. From here on, approve
   everyone else's accounts normally from the Users module — no more manual
   SQL needed after this one bootstrap step.

## How the security actually works (read this once)

- Every table has Row Level Security enabled. Nobody gets data back from
  the API unless a policy explicitly allows it — there's no default-open
  table.
- **Approved users** can read/write clinical records (patients, cases,
  OPD). **Admin or Chief Resident** are required to delete records, approve
  accounts, or manage Legends. **Only Admin** can delete a user account
  outright.
- A **pending user can always read their own profile row** (needed so the
  app can show them the "waiting for approval" screen) but nothing else
  until approved.
- A regular signed-in user **cannot** grant themselves Admin, approve
  themselves, or flip their own `access_opd` flag by calling the Supabase
  API directly, even bypassing the app's UI entirely — a database trigger
  blocks any change to `status`/`user_level`/`access_opd` unless the caller
  is already Admin/Chief Resident, or the request has no end-user session
  attached at all (i.e. it's coming from you, in the SQL Editor — which is
  exactly what makes the one-time bootstrap step above work).

## Multi-user behavior

Reads are served from an in-memory cache hydrated from Supabase on login
and on manual refresh (the ⟳ Refresh button in the top bar), not a live
subscription — so if two people are using it at the same time, each sees
the other's changes after they hit Refresh, not instantly. Writes are
optimistic (your own screen updates immediately) and sync to Supabase in
the background; if a sync fails (e.g. you're offline), you'll get a toast
telling you so rather than the change silently vanishing.
