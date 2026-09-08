# AFP-VLUNA — single-file build

`index.html` is the entire app — CSS, all JS modules, and the AFP-VLUNA
seal (embedded as base64) are all inlined into one file. Nothing else to
upload or host alongside it; just open it in a browser, or deploy it as-is
to Vercel/Cloudflare Pages/any static host/a USB stick.

The only external dependencies are three CDN `<script>` tags for Chart.js,
jsPDF, and the Supabase client library — same as before, just no longer
split across local `css/` and `js/` files.

Demo login: `admin@afp-vluna.mil.ph` / `Admin@2026`
(Chief Resident: `chief.resident@afp-vluna.mil.ph` / `Chief@2026`)

## What changed in this update

- **AFP-VLUNA seal** now used throughout (sidebar, login page, browser tab
  favicon) in place of the placeholder text crest.
- **Mobile-friendly**: sidebar becomes a slide-out drawer with a hamburger
  toggle and dimmed backdrop below ~860px width; topbar, grids, forms,
  modals, and tables all reflow to single-column / full-width / horizontally
  scrollable as needed. Same color palette and layout on desktop — nothing
  about the look was changed, only how it adapts to a small screen.
- **Login/Signup** — Designation is now a proper department-wide dropdown
  (Consultant, Department Head, Physician, Surgeon, Nurse, etc., not just
  the two OB-GYN-specific options), so people signing up for other
  departments have something correct to pick.
- **Users → Directory auto-sync** — every registered user (on signup, and
  whenever their profile is edited from the Users module) is automatically
  mirrored into the Directory. Directory now always contains "all the Users
  in the Users tab," tagged **🔒 System User** and kept in sync; manually
  added contacts (outside referrals, emergency contacts) stay independent
  and fully editable/deletable.
- **OPD module** — Consultant in-charge, Resident in-charge, and OB/GYNE
  Reason are now all "+ Add" pickers you can use repeatedly to build a list
  (consultants/residents pulled from Directory), instead of a single select
  each.
- **Cases module** —
  - Fixed the OB-GYN Procedures dropdown overflow that pushed the add-buttons
    off-screen (the picker row now wraps and the select is width-constrained
    instead of stretching past the modal).
  - Indication for Primary CS and Surgeon are now "+ Add" pickers supporting
    multiple entries each (Surgeon pulled from Directory), instead of a
    single select each.
- **Tasks module** — full rebuild: assign a task to a specific user (not
  just a role), with Module / Task / Due Date. Tasks are clickable to open
  a detail view with a running **Actions / Progress Notes** log (your
  "completion form"), plus an **Acknowledge** button (open → in-process) and
  a **Mark Complete** button.

## Supabase

`supabase-schema.sql` is updated to match all of the above (directory sync
column, multi-value jsonb columns for OPD/Cases/Tasks, task status +
actions log) and includes role-based Row Level Security policies for every
table.

**Read the "AUTH" note at the bottom of that file before relying on the
RLS policies** — they're keyed to Supabase Auth (`auth.uid()`), but the
app's Login module currently does its own custom email/password check
against the `users` table rather than calling Supabase Auth. The policies
are correct and ready, but won't actually take effect until the two small
changes described there are made to the Login module's signup/login calls.
Until then, treat the SQL file as "the schema and policies to have ready,"
not yet enforced — same security posture the demo already has with
`DB_MODE: "local"`.

To use it: create a Supabase project, paste `supabase-schema.sql` into the
SQL Editor and run it, then in `index.html` find the `APP_CONFIG` block near
the top of the inlined script and set `DB_MODE: "supabase"` with your
project URL/anon key. The `DB` object's `local` branch is the only thing
that then needs to be swapped for the Supabase calls sketched in the
comment block right after it — every module already calls
`DB.insert/update/get/query/remove` exclusively, so that's the only edit
needed anywhere in the file.
