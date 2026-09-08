# AFP VLUNA — OB-GYN Health Surveillance & Record System (Demo Build)

A single-file web app (`index.html`) for the Armed Forces of the Philippines
OB-GYN Department, backed by Supabase for the demo. Built mobile-first.

> **⚠️ This is a working demo scaffold, not a finished production system.**
> It implements the full navigation, auth, database schema, and the core
> workflows for every module in the spec. A few things are intentionally
> left as **`TASK: TO BE UPDATED`** — search the code for that exact phrase
> to find them all. See "What's Left" below.

---

## 1. Deploy in ~10 minutes

### A. Supabase (backend)
1. Go to [supabase.com](https://supabase.com) → New Project (pick a region close to the Philippines, e.g. Singapore).
2. Open **SQL Editor → New query**, paste the entire contents of `supabase_schema.sql`, click **Run**.
3. Go to **Project Settings → API** and copy:
   - `Project URL`
   - `anon public` key
4. Open `index.html`, find this block near the top of the `<script>` section (search `JS:CONFIG`):
   ```js
   const SUPABASE_URL = "https://YOUR-PROJECT-REF.supabase.co";   // TASK: TO BE UPDATED
   const SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY";               // TASK: TO BE UPDATED
   ```
   Replace both with your real values and save.
5. In **Authentication → Providers → Email**, turn **Confirm email OFF** for the demo (so new sign-ups can log in immediately, still gated by your Admin approval). Turn it back ON for production.

### B. GitHub
1. Create a new repository, e.g. `afp-vluna-obgyn`.
2. Upload `index.html` (and this `README.md`, `supabase_schema.sql` for reference) to the repo root.

### C. Vercel or Cloudflare Pages (frontend hosting)
- **Vercel:** New Project → Import your GitHub repo → Framework preset "Other" → Build command *empty* → Output directory `/` → Deploy.
- **Cloudflare Pages:** Create a project → Connect to Git → your repo → Build command *empty* → Build output directory `/` → Deploy.

Either way, since this is a static single HTML file, no build step is required.

### D. Create your first Admin
1. Open your deployed URL and **Sign Up** with your own details.
2. Back in Supabase **SQL Editor**, run:
   ```sql
   update public.profiles set user_level = 'Admin', approved = true
   where email = 'your-admin-email@example.com';
   ```
3. Log back in — you now see **Users** and **Legends** in the sidebar, and can approve everyone else from the **Users** module.

---

## 2. Security notes (demo-appropriate, tighten before real use)

- **Auth:** Supabase Auth (email + password). Passwords are hashed by Supabase, never touched by this app's code.
- **Row Level Security (RLS)** is enabled on every table. A user can only read/write a module's data if:
  - their account is `approved = true`, **and**
  - their `access_control` JSON has that module set to `true` (or they are `Admin`, who can access everything).
- **Delete** is restricted to `Admin` on every module, matching the spec.
- **Case edits** made by non-Admin/non-Chief-Resident users are flagged `needs_admin_approval = true` in the database — the app shows a pending banner until an Admin or Chief Resident clears it.
- The **anon key** is meant to be public — it only unlocks what your RLS policies allow, never more.
- For a real government deployment, also turn on: email confirmation, a strong password policy in Supabase Auth settings, and consider Supabase's audit-log add-ons or a WAF in front of Cloudflare/Vercel.

## 3. Migrating off Supabase later (Oracle or otherwise)

The spec asked for this to be easy — here's how it's set up:

- Every single database call in the app goes through one object: **`DB`** (search `JS:DB` in `index.html`). No other code calls `supabase-js` directly.
- To migrate: rewrite the methods inside `DB` to call your new backend (e.g. a REST API in front of Oracle) instead of `sb.from(...)`. Every module (`Modules.patient_record`, `Modules.cases`, etc.) keeps working unchanged, because they only ever call `DB.patients.list()`, `DB.cases.create()`, and so on.
- The schema avoids Postgres-only features where practical. `jsonb` columns (used for the multi-tab Case/OPD forms) map to `CLOB`/JSON columns on Oracle; `text[]` (used for Final Diagnosis bullets) maps to a small child table.
- Row Level Security would need to be re-implemented as either database views/procedures or as checks inside your new API layer.

## 4. What's already working

- Login / Sign-up (with Admin-approval gate) / Log out / Refresh / My Profile
- Collapsible sidebar nav, gated per-user by the Access Control checklist
- **Overview** — live stat cards + OB vs GYNE and Cases-by-Department charts
- **Patient Record** — create/search/filter/edit/delete, linked Cases shown on profile
- **Cases** — department picker → full 8-tab OB-GYN form (Admission, Obstetric History,
  Co-morbidities, Gynecological Conditions, MIGS, Blood, Final Diagnosis, Discharge),
  auto BMI, auto hospital-days, "+Not in the list" adds new dropdown options live,
  Admin/Chief-Resident approval flag on edits, Cases Data Summary with charts
- **OPD** — 5-tab form (Information, Consultation, Procedures, Final Diagnosis, Actions),
  OPD Data Summary with a monthly trend chart
- **Tasks** — assign by module, acknowledge, complete with notes
- **Directory** — add/search/edit contacts
- **Users** — list, search, approve/decline, per-module Access Control checklist, activity history
- **Activity Logs** — every create/update/delete is logged and filterable by module/user/date
- **Legends** — every dropdown in the system is admin-editable and pre-seeded from your spec
- Fully responsive/mobile layout (collapsible hamburger sidebar, stacked forms)
- Philippine Time (Asia/Manila) used for all displayed dates/times

## 5. TASK: TO BE UPDATED (left for a follow-up pass)

Search `index.html` for the literal phrase **`TASK: TO BE UPDATED`** — each spot is commented in place. In summary:

- **Wards module** — spec says "to follow upon the next update"; a placeholder screen and an empty `wards` table are in place, nothing else.
- **Other departments' Case forms** (Internal Medicine, Surgery, Pediatrics, etc.) — only OB-GYN's 8-tab form is built, per the spec's "for now the web-app is for OB-GYN Department." Selecting another department shows a friendly "not built yet" message instead of crashing.
- **CSV Import/Export & downloadable CSV templates** — mentioned throughout the spec (Patient Record, Cases, OPD, Legends) — not implemented in this pass; wire these up against `DB.patients`, `DB.cases`, `DB.opd`, `DB.legend_options` using a small CSV parser (e.g. PapaParse) when you're ready.
- **PDF export/download buttons** — currently trigger the browser's print dialog as a placeholder; swap in a proper PDF library (e.g. jsPDF) for formatted letterhead output matching your reference report.
- **Supabase → your production URL/key** — see §1.A step 4.

## 6. File map

- `index.html` — the entire application (HTML + CSS + JS in one file, per the requirement). Internally organized into clearly commented blocks (`STYLE:*`, `HTML:*`, `JS:*`) by module, so any one module (e.g. Cases) can be edited without touching the others.
- `supabase_schema.sql` — full schema, security policies, and seed data for every dropdown list in the spec.
- `README.md` — this file.
