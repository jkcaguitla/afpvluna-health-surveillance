-- =========================================================================
-- AFP-VLUNA — Supabase (Postgres) schema — updated for:
--   * Directory auto-synced from Users (directory.user_id)
--   * OPD: multiple Consultants/Residents in-charge, multiple OB/GYNE Reasons
--   * Cases: multiple Indications for Primary CS, multiple Surgeons
--   * Tasks: assigned to a specific user, acknowledge/in-process/complete
--     workflow, and an actions/progress-notes log
--
-- Paste this whole file into the Supabase SQL Editor and run it once on a
-- fresh project. Portable-by-design (uuid/text/numeric/boolean/timestamptz/
-- jsonb only) so it still maps cleanly onto Oracle later — see the note at
-- the bottom of js/db.js.
-- =========================================================================

create extension if not exists "uuid-ossp";

create table users (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  auth_uid uuid unique references auth.users(id), -- links to Supabase Auth; see "AUTH" note at bottom
  email text unique not null,
  password_hash text,                        -- only used if NOT migrating to Supabase Auth; see note at bottom
  last_name text, first_name text, middle_name text,
  gender text, designation text, rank text, department text,
  address text, contact_number text, birthdate date,
  user_level text not null default 'Staff',  -- Admin, Chief Resident, Resident, Senior, Junior, Staff
  status text not null default 'pending',    -- pending, approved, declined
  access_opd boolean not null default false
);

create table patients (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  gender text, last_name text, first_name text, middle_name text,
  birthdate date, rank text, bos text, pc text, care_of text,
  address text, contact_number text, email text, notes text,
  status text not null default 'Non-Admitted' -- Admitted, Discharged, Deceased, Non-Admitted
);

create table cases (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  case_number text,
  department text not null,
  patient_id uuid references patients(id),
  status text not null default 'Admitted',
  admission_date date, weight numeric, height numeric, bmi numeric,
  case_type text, pcos_history text, evac text, evac_from text,
  ob_g int, ob_p int, ob_ft int, ob_pt int, ob_ab int,
  comorbidities jsonb default '[]',
  admission_reasons jsonb default '[]',
  surgery_type text,
  procedures jsonb default '[]',
  cs_indications jsonb default '[]',          -- was a single text column; now multi-add
  surgeons jsonb default '[]',                -- [{directory_id, name}, ...]; was a single text column
  migs_surgeon text, migs_assist text,
  blood_transfused text, blood_reaction text,
  final_diagnosis jsonb default '[]',
  discharge_date date, within_allowable text, patient_condition text, discharge_status text
);

create table opd_visits (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  consultation_date date, gender text,
  patient_id uuid references patients(id),
  registration_status text, birthdate date, rank text, bos text, pc text,
  care_of text, contact_number text, address text, email text, notes text,
  last_name text, first_name text, middle_name text,
  case_type text, high_risk text,
  consultants jsonb default '[]',             -- [{directory_id, name}, ...]; was a single text column
  residents jsonb default '[]',               -- [{directory_id, name}, ...]; was a single text column
  ob_reasons jsonb default '[]',              -- was a single text column
  gyne_reasons jsonb default '[]',            -- was a single text column
  family_planning text,
  procedures jsonb default '[]', final_diagnosis jsonb default '[]', actions jsonb default '[]'
);

create table directory (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  user_id uuid unique references users(id) on delete cascade, -- set when this row is auto-synced from Users; null = manually-added contact
  last_name text, first_name text, middle_name text, gender text,
  rank text, department text, designation text,
  contact_number text, email text, address text, birthdate date,
  emergency_contact_name text, emergency_contact_number text
);

create table tasks (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  module text not null, title text not null,
  assigned_user_id uuid references users(id), -- was assigned_to_role text; now a specific user
  status text not null default 'open' check (status in ('open','acknowledged','done')),
  due_date date,
  actions jsonb default '[]'                   -- [{date, actor, note}, ...] progress/completion log
);

create table legends (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  category text unique not null,
  data jsonb not null default '[]'   -- every dropdown lives here, editable via the Legends module
);

create table activity_logs (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  module text not null, record_id uuid, action text not null,
  actor_id uuid references users(id), actor_name text,
  before jsonb, after jsonb
);

-- =========================================================================
-- ROW LEVEL SECURITY
-- =========================================================================
alter table users enable row level security;
alter table patients enable row level security;
alter table cases enable row level security;
alter table opd_visits enable row level security;
alter table directory enable row level security;
alter table tasks enable row level security;
alter table legends enable row level security;
alter table activity_logs enable row level security;

-- Helper: look up the calling user's row in public.users via their Supabase
-- Auth id. SECURITY DEFINER so it can read `users` even though `users`
-- itself has RLS enabled.
create or replace function is_approved()
returns boolean language sql security definer stable
as $$ select exists (select 1 from public.users where auth_uid = auth.uid() and status = 'approved'); $$;

create or replace function is_admin_or_chief()
returns boolean language sql security definer stable
as $$ select exists (select 1 from public.users where auth_uid = auth.uid() and status = 'approved' and user_level in ('Admin','Chief Resident')); $$;

create or replace function is_admin()
returns boolean language sql security definer stable
as $$ select exists (select 1 from public.users where auth_uid = auth.uid() and status = 'approved' and user_level = 'Admin'); $$;

-- ---- users --------------------------------------------------------------
-- Anyone can INSERT their own row at signup (status defaults to 'pending').
-- Only approved users can read the directory of accounts; only Admin/Chief
-- Resident can approve/decline/edit; only Admin can delete.
create policy "users_insert_self" on users for insert
  with check (auth_uid = auth.uid());
create policy "users_select_approved" on users for select
  using (is_approved());
create policy "users_update_admin_or_self" on users for update
  using (is_admin_or_chief() or auth_uid = auth.uid());
create policy "users_delete_admin" on users for delete
  using (is_admin());

-- ---- patients / cases / opd_visits ---------------------------------------
-- Any approved, logged-in staff member can read and write clinical records.
-- Deletes restricted to Admin/Chief Resident (matches the app's UI, which
-- only shows delete buttons to Admins).
create policy "patients_select" on patients for select using (is_approved());
create policy "patients_insert" on patients for insert with check (is_approved());
create policy "patients_update" on patients for update using (is_approved());
create policy "patients_delete" on patients for delete using (is_admin_or_chief());

create policy "cases_select" on cases for select using (is_approved());
create policy "cases_insert" on cases for insert with check (is_approved());
create policy "cases_update" on cases for update using (is_approved());
create policy "cases_delete" on cases for delete using (is_admin_or_chief());

create policy "opd_select" on opd_visits for select using (is_approved());
create policy "opd_insert" on opd_visits for insert with check (is_approved());
create policy "opd_update" on opd_visits for update using (is_approved());
create policy "opd_delete" on opd_visits for delete using (is_admin_or_chief());

-- ---- directory ------------------------------------------------------------
-- Readable by any approved user. Manual contacts (user_id is null) can be
-- added/edited/deleted by any approved user; synced entries (user_id set)
-- can only be edited (never deleted) since Users is their source of truth.
create policy "directory_select" on directory for select using (is_approved());
create policy "directory_insert" on directory for insert with check (is_approved());
create policy "directory_update" on directory for update using (is_approved());
create policy "directory_delete_manual_only" on directory for delete
  using (is_approved() and user_id is null);

-- ---- tasks ----------------------------------------------------------------
-- Anyone approved can create/view tasks. A task can be updated (acknowledged,
-- actions added, marked complete) by the assignee or by Admin/Chief Resident;
-- only Admin can delete.
create policy "tasks_select" on tasks for select using (is_approved());
create policy "tasks_insert" on tasks for insert with check (is_approved());
create policy "tasks_update" on tasks for update
  using (is_admin_or_chief() or assigned_user_id = (select id from users where auth_uid = auth.uid()));
create policy "tasks_delete" on tasks for delete using (is_admin());

-- ---- legends ----------------------------------------------------------------
-- Everyone approved can read (needed to populate dropdowns); only
-- Admin/Chief Resident can add/edit/delete entries.
create policy "legends_select" on legends for select using (is_approved());
create policy "legends_insert" on legends for insert with check (is_admin_or_chief());
create policy "legends_update" on legends for update using (is_admin_or_chief());
create policy "legends_delete" on legends for delete using (is_admin_or_chief());

-- ---- activity_logs ----------------------------------------------------------
-- Append-only audit trail: any approved user can write (the app writes a row
-- on every create/update/delete) and read; nobody can update or delete past
-- entries through the API.
create policy "activity_select" on activity_logs for select using (is_approved());
create policy "activity_insert" on activity_logs for insert with check (is_approved());

-- =========================================================================
-- AUTH — read this before assuming the policies above are protecting data
-- =========================================================================
-- These policies key off auth.uid(), which only exists for requests made
-- with a real Supabase Auth session. The demo app's Login module currently
-- does its OWN email/password check against the `users` table using the
-- shared anon key — it does not call supabase.auth.signInWithPassword(), so
-- auth.uid() would be null for every request and every policy above would
-- simply deny access to everyone.
--
-- To make these policies actually take effect, two changes are needed in
-- the app (not in this SQL file):
--   1. Signup (js/modules/login.js) — call
--        supabase.auth.signUp({ email, password })
--      then insert the profile row into `users` with
--        auth_uid: <the returned user's id>
--   2. Login (js/modules/login.js) — call
--        supabase.auth.signInWithPassword({ email, password })
--      then look up the matching `users` row by auth_uid for the app-level
--      session (user_level, status, etc.) that the rest of the app already
--      expects in DB.getSession().
--
-- Until that swap is made, treat this file as the schema + policies to have
-- ready, not yet enforced. If you want the app to keep working exactly as-is
-- in the meantime (custom login, shared anon key) while you plan that
-- migration, you could temporarily relax policies to `using (true)` — but
-- do that knowingly: it means anyone with the anon key (visible in your
-- deployed JS) has full read/write on these tables, same exposure the app
-- already has today with DB_MODE: "local" and no server component at all.
