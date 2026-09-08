# AFP-VLUNA — Health Surveillance & Records (OB-GYN Department)

Single-page HTML/JS web app, medical-military themed, built demo-ready
against **localStorage** and migration-ready toward **Supabase** (and later
Oracle, for AFP's government security requirements). Timezone: Philippine
Standard Time (Asia/Manila, UTC+8) throughout.

## Run it
Just open `index.html` in a browser (or serve the folder with any static
file server — e.g. `npx serve .`). No build step, no dependencies to install.

Demo logins:
- Admin: `admin@afp-vluna.mil.ph` / `Admin@2026`
- Chief Resident: `chief.resident@afp-vluna.mil.ph` / `Chief@2026`
- A pending (not-yet-approved) account is also seeded so you can see that flow: `resident.new@afp-vluna.mil.ph` / `Newres@2026`

## Why it's structured this way
Per the brief, code is split by module/tab so any one part can be
troubleshot, updated, or scaled independently without touching the rest:

```
index.html
css/theme.css              Medical-military palette & shared styles
js/config.js                DB_MODE switch + Philippine timezone helpers
js/legends-data.js          Seed data for every dropdown (editable after seeding via Legends module)
js/db.js                    THE ONLY file that talks to storage — swap this to move to Supabase/Oracle
js/app.js                   Shell, sidebar nav, router, shared UI helpers (toast/modal/tables)
js/modules/login.js          Login / Sign-up / pending-approval gate
js/modules/users.js          Users module (approve/decline, access control, activity, PDF)
js/modules/patientRecord.js  Patient archive (CRUD, CSV import/export, filters)
js/modules/cases.js          Cases module — full 8-tab OB-GYN case form + data-summary dashboard
js/modules/opd.js            Outpatient Department — 5-tab OP form + data-summary dashboard
js/modules/wards.js          Placeholder ("to follow" per spec)
js/modules/tasks.js          Basic task board backing the per-module task widgets
js/modules/directory.js      Staff/contact directory
js/modules/activityLogs.js   System-wide audit trail
js/modules/legends.js        Add/edit/delete every dropdown definition, CSV import/export, PDF
js/modules/overview.js       Hospital-wide compiled dashboard with quick-jump
supabase/schema.sql          Portable Postgres schema for the Supabase backend
```

## Moving from demo (localStorage) to Supabase
1. Create a Supabase project, run `supabase/schema.sql` in the SQL editor.
2. In `js/config.js`, set `DB_MODE: "supabase"` and fill in `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
3. Replace the local-storage branch inside `js/db.js` with the Supabase calls
   sketched in the comment block at the bottom of that file. No other file
   needs to change — every module only calls `DB.all/get/query/insert/update/remove`.

## Moving from Supabase to Oracle later (AFP security requirement)
`supabase/schema.sql` intentionally sticks to portable types (uuid, text,
numeric, boolean, timestamptz, jsonb) so it maps directly onto Oracle types.
Stand up Oracle REST Data Services (ORDS) or a thin custom API in front of
Oracle, then swap the `"supabase"` branch in `js/db.js` for calls to that API.
Again: zero changes needed in any `js/modules/*.js` file.

## What's implemented vs. roadmap
- Fully built: Login/Signup + approval gate, Users, Patient Record, Cases
  (OB-GYN 8-tab form + dashboard with all charts from the spec), OPD (5-tab
  form + dashboard), Directory, Activity Logs, Legends (all dropdown
  definitions editable, CSV import/export, PDF export), Overview.
- Placeholder per spec ("to follow upon next update"): Wards, full Tasks board.
- Other departments (Internal Medicine, Surgery, etc.): the Cases module
  shell (search/filter/list/CSV) already supports any department; only the
  OB-GYN tabbed form is built out, since that's what the spec detailed. Adding
  another department's form is a new `panelHtml()`-style function alongside
  the existing OB-GYN one in `js/modules/cases.js` — the list, filters, and
  dashboard shell are already department-aware.
