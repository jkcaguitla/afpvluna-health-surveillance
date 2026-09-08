# AFP Medical Center — OB-GYN Health Surveillance System

A single-file web app (`index.html`) for the AFP Medical Center OB-GYN Department, backed by Supabase. Military-green themed, mobile-friendly, and built so each module's logic is easy to find and troubleshoot independently.

## Files in this delivery
| File | Purpose |
|---|---|
| `index.html` | The entire web app — HTML, CSS, and JS in one file (logo embedded). This is what you deploy/host. |
| `supabase_schema.sql` | Paste into Supabase's SQL Editor once to create every table, trigger, security rule, and seed the dropdown lists ("Legends"). |
| `README.md` | This file. |

---

## 1. Set up Supabase (5 minutes)

1. Go to [supabase.com](https://supabase.com) → create a free project (choose a region close to the Philippines, e.g. Singapore).
2. In your project, go to **SQL Editor → New query**, paste the **entire contents of `supabase_schema.sql`**, and click **Run**. This creates:
   - `profiles`, `directory`, `patients`, `cases`, `opd`, `tasks`, `activity_logs`, `legends`
   - Triggers so every new signup gets a profile row, and every **Approved** user is automatically mirrored into **Directory**
   - Row Level Security (only approved users can read/write; only Admin/Chief Resident can delete or approve)
   - All the dropdown values from the spec (Rank, BOS, PC, Department, Designation, Comorbidities, OB-GYN Procedures, Indications for Primary CS, Discharge Status, OB/GYNE Reasons, etc.) pre-loaded into the `legends` table
3. Go to **Project Settings → API**. Copy:
   - **Project URL**
   - **anon public key**
4. **Turn off "Confirm email"** for a smoother demo: **Authentication → Providers → Email → toggle "Confirm email" off** (or, if you keep it on, users must click the confirmation link before they can log in).

## 2. Connect the app to Supabase

Open `index.html` in a text editor, find this near the top of the `<script>` section:

```js
const SUPABASE_URL = "YOUR_SUPABASE_URL_HERE";
const SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY_HERE";
```

Paste in the values from step 1.3. Save the file. That's the **only** required edit.

## 3. Create your first Admin account

1. Open `index.html` in a browser (double-click it, or host it — see below).
2. Click **Sign Up**, fill out the registration form (Designation and Rank are now dropdowns), and submit.
3. You'll see "awaiting Admin approval" — this is expected, every new account starts as **Pending**.
4. Back in Supabase **SQL Editor**, run (replace the email):
   ```sql
   update public.profiles
     set user_level = 'Admin', status = 'Approved',
         access_control = '["OPD","Overview","Directory","Cases","Legends","Activity Logs","Users","Tasks","Wards","Patient Record"]'
   where email = 'youremail@example.com';
   ```
5. Log in again in the app — you now have full Admin access, including approving every future user from the **Users** module (no more manual SQL needed after this).

## 4. Hosting

`index.html` is fully static — host it anywhere:
- Easiest: drag-and-drop the file into [Netlify Drop](https://app.netlify.com/drop) or Vercel.
- Or serve it from any web server / intranet server your unit already runs.
- No build step, no npm install — it's plain HTML/CSS/JS + the Supabase CDN script tag.

---

## What was updated in this build (per your latest requests)

**Login Page**
- Sign-up **Designation** field is now a dropdown (pulled live from the `legends` table, so Admin can add more designations later from the Legends module without touching code).

**Users → Directory**
- The moment an Admin/Chief Resident **Approves** a pending user, a Postgres trigger automatically inserts/updates that person in the **Directory** table. No manual step needed, and it stays in sync if their name/rank/department is edited later.

**Directory**
- Lists every approved system user (tagged "Registered User") plus any manually added contacts (e.g., doctors who don't need system logins), all in one list.

**OPD**
- "Consultant in-charge" and "Resident in-charge" are now **+ Add** buttons that open a searchable picker pulling names straight from the Directory. Add as many as needed; each becomes a removable chip.
- "OB Reason" is now a **+ Add OB Reason** multi-picker (same searchable-chip pattern) — add as many as needed.

**Cases**
- The OB-GYN Procedures list is no longer a native `<select>` (which is why long procedure names were pushing buttons off-screen). It's now a custom **searchable dropdown** that scrolls internally and always fits the screen, on both desktop and mobile.
- "Indication for PRIMARY CS" is now a **+ Add** multi-picker — add as many as needed.
- "Surgeon" is now a **+ Add SURGEON** multi-picker pulling doctors from the Directory — add as many as needed.

**Tasks**
- Simple task creation: assign a **User**, pick the **Module**, describe the **Task**, set a **Due Date**.
- Tasks are clickable → opens the full assignment with an **Action/Completion notes** field the assignee fills in to close it out.
- An **Acknowledge** button (plus "Mark In-Process") lets the assignee signal they've seen/started the task before marking it Completed.

---

## Module map (for future maintenance)

Every module's rendering + data functions are grouped and commented in numbered sections inside the single `<script>` block, in this order:

1. Config & state
2. Generic helpers (dates, toasts, modal, activity logging, the reusable "searchable multi-add" and "bullet list" components used everywhere)
3. Legends + Directory cache loaders
4. Auth (login, signup, session, sidebar/access-control)
5. Init
6. Overview
7. Users
8. Directory
9. Profile (self)
10. Patient Record
11. Cases (8-tab form)
12. OPD (5-tab form)
13. Tasks
14. Legends (admin CRUD for every dropdown)
15. Activity Logs
16. Wards (placeholder — "to follow upon the next update," as specified)

Because each module owns its own `render_<module>()` function and its own DB calls, you can edit or fix one module (e.g. Cases) without touching any other module's code — exactly the "separate code per tab" requirement from the spec.

## Extensible dropdowns ("Legends")
Every list in the app (Rank, BOS, Department, Comorbidities, OB-GYN Procedures, Discharge Status, etc.) reads from the `legends` table at runtime. Add, edit, or retire any value from the in-app **Legends** module (or directly in Supabase) — no code change or redeploy needed. "+ Not in the list" buttons in the Cases form write straight into `legends` too, so the next person sees the new option immediately.

## Migrating off Supabase later
The app only talks to the database through the `supabase.from('table')...` calls inside each module's functions — there's no ORM or vendor-specific SQL scattered in the UI code. To move to Oracle or another platform:
1. Recreate the same tables/columns (schema is plain, portable SQL — see `supabase_schema.sql`; JSONB columns become CLOB/JSON columns in Oracle).
2. Replace the Supabase JS client init and the `.from().select()/.insert()/.update()/.delete()` calls with your new platform's client (a thin data-access wrapper). Because every module calls these in the same handful of patterns, this is a mechanical find-and-replace rather than a rewrite.
3. Re-implement the two triggers (`profiles`→`directory` sync, case-number generator) as stored procedures/triggers in the new database, or move that logic into the app layer.

## Known simplifications in this demo build (roadmap)
The master spec is very large; this build focuses on making every module **functional end-to-end** with the specific fixes you asked for. Not yet built (flagged so nothing is silently missing):
- Advanced dashboard graphs (weekly/monthly/yearly bar charts, top-10 admission causes, death-rate monitoring formulas, BOS/PC/Rank breakdown charts) — Overview/Cases/OPD currently show live **stat cards** instead; the underlying data (cases, opd, patients tables) already supports adding charts (e.g. with Chart.js) later.
- Case/OPD/Patient CSV **import** is implemented for Patient Record; Cases/OPD import is stubbed (needs a field-mapping decision from your team since those forms are multi-tab).
- "PDF" downloads currently use the browser's print dialog (Save as PDF) rather than a generated PDF file — this keeps the app dependency-free; a proper PDF library can be added if a branded PDF layout is required.
- Only the **Obstetrics and Gynecology (OB-GYN)** case form is built; other departments are selectable in "+ New Case" but show a "coming soon" message, per the spec's phased rollout.
- Wards module is a placeholder, per the spec ("to follow upon the next update").

## Security note
This is explicitly a **demo-grade** RLS setup (any approved user can read/write clinical data; only Admin/Chief Resident can delete or approve). Before real deployment with government health data, tighten Row Level Security further (e.g., per-department access, audit-only fields, encrypted-at-rest columns for PII) and put the app behind your unit's VPN/intranet.
