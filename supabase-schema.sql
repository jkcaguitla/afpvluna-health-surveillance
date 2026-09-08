-- =========================================================================
-- AFP-VLUNA — Supabase (Postgres) schema, with Row Level Security + real
-- Supabase Auth integration. This matches the app's actual code (js/db.js
-- and js/modules/login.js already call supabase.auth.signUp /
-- signInWithPassword when APP_CONFIG.DB_MODE = "supabase" — this is not a
-- sketch, it's wired up and working).
--
-- HOW TO USE THIS FILE
--   1. Create a Supabase project.
--   2. Open the SQL Editor, paste this ENTIRE file, click Run.
--   3. In Authentication -> Providers -> Email, turn OFF "Confirm email"
--      (see the AUTH section at the bottom for why — recommended for this
--      internal-tool signup+approval workflow).
--   4. In index.html, set APP_CONFIG.DB_MODE = "supabase" and fill in
--      SUPABASE_URL / SUPABASE_ANON_KEY (Project Settings -> API).
--   5. Sign up your first real account through the app itself, then run
--      the "BOOTSTRAP YOUR FIRST ADMIN" statement at the very bottom of
--      this file (edit the email first) to make that account an Admin.
-- =========================================================================

create extension if not exists "uuid-ossp";

-- =========================================================================
-- TABLES
-- =========================================================================

create table users (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  auth_uid uuid unique references auth.users(id) on delete cascade, -- links this profile row to a real Supabase Auth account
  email text unique not null,
  password_hash text,                        -- unused in supabase mode (Supabase Auth manages passwords) — left in for local-mode compatibility
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
  cs_indications jsonb default '[]',          -- multi-add: Indication/s for Primary CS
  surgeons jsonb default '[]',                -- multi-add: [{directory_id, name}, ...]
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
  consultants jsonb default '[]',             -- multi-add: [{directory_id, name}, ...]
  residents jsonb default '[]',               -- multi-add: [{directory_id, name}, ...]
  ob_reasons jsonb default '[]',              -- multi-add
  gyne_reasons jsonb default '[]',            -- multi-add
  family_planning text,
  procedures jsonb default '[]', final_diagnosis jsonb default '[]', actions jsonb default '[]'
);

create table directory (
  id uuid primary key default uuid_generate_v4(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  user_id uuid unique references users(id) on delete cascade, -- set when auto-synced from Users; null = manually-added contact
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
  assigned_user_id uuid references users(id),
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

-- ---- helper functions ----------------------------------------------------
-- SECURITY DEFINER so these can read `users` even though `users` itself has
-- RLS enabled (otherwise checking a policy would need to check a policy...).
create or replace function is_approved()
returns boolean language sql security definer stable
as $$ select exists (select 1 from public.users where auth_uid = auth.uid() and status = 'approved'); $$;

create or replace function is_admin_or_chief()
returns boolean language sql security definer stable
as $$ select exists (select 1 from public.users where auth_uid = auth.uid() and status = 'approved' and user_level in ('Admin','Chief Resident')); $$;

create or replace function is_admin()
returns boolean language sql security definer stable
as $$ select exists (select 1 from public.users where auth_uid = auth.uid() and status = 'approved' and user_level = 'Admin'); $$;

create or replace function current_app_user_id()
returns uuid language sql security definer stable
as $$ select id from public.users where auth_uid = auth.uid(); $$;

-- ---- users ----------------------------------------------------------------
-- Anyone can insert their own row at signup. Everyone can always read their
-- OWN row regardless of approval status (this is what lets a pending user's
-- browser find their profile to show the "waiting for approval" screen);
-- approved users can read everyone. Only Admin/Chief Resident can update
-- someone else's row (approve/decline/edit); only Admin can delete.
create policy "users_insert_self" on users for insert
  with check (auth_uid = auth.uid());
create policy "users_select_self_or_approved" on users for select
  using (auth_uid = auth.uid() or is_approved());
create policy "users_update_admin_or_self" on users for update
  using (is_admin_or_chief() or auth_uid = auth.uid());
create policy "users_delete_admin" on users for delete
  using (is_admin());

-- Privilege-escalation guard: a regular signed-in user is allowed to UPDATE
-- their own row (e.g. future self-service profile edits), but must never be
-- able to change status / user_level / access_opd on ANY row, including
-- their own, by calling the API directly — only Admin/Chief Resident can.
-- auth.uid() is null when this statement runs from the SQL Editor, a
-- service-role key, or a direct Postgres connection (no end-user session
-- attached) — that's treated as a trusted/administrative context and left
-- unrestricted, which is what makes the bootstrap step at the bottom work.
create or replace function prevent_self_privilege_escalation()
returns trigger language plpgsql security definer as $$
begin
  if auth.uid() is not null and not is_admin_or_chief() then
    if new.status is distinct from old.status
       or new.user_level is distinct from old.user_level
       or new.access_opd is distinct from old.access_opd then
      raise exception 'Only Admin or Chief Resident can change status, user_level, or access_opd.';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_prevent_self_privilege_escalation
before update on users
for each row execute function prevent_self_privilege_escalation();

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
-- can be edited (e.g. emergency contact info) but never deleted through the
-- API, since Users is their source of truth — matches the app's UI.
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
  using (is_admin_or_chief() or assigned_user_id = current_app_user_id());
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
-- entries through the API (no update/delete policy exists for this table,
-- so those operations are denied by default with RLS enabled).
create policy "activity_select" on activity_logs for select using (is_approved());
create policy "activity_insert" on activity_logs for insert with check (is_approved());

-- =========================================================================
-- AUTH — how sign-in actually works in this app
-- =========================================================================
-- js/modules/login.js, in "supabase" mode:
--   Signup  -> supabase.auth.signUp({ email, password }), then inserts a
--              matching row into `users` with auth_uid = the new auth user's
--              id (status starts 'pending', user_level starts 'Staff').
--   Sign in -> supabase.auth.signInWithPassword({ email, password }), then
--              looks up the `users` row where auth_uid matches, and uses
--              THAT row for the app session (status, user_level, etc).
--
-- RECOMMENDED SETTING: Authentication -> Providers -> Email -> turn OFF
-- "Confirm email". Reason: with confirmation ON, signUp() returns no active
-- session until the person clicks the emailed link, so the app can't insert
-- their `users` profile row right away (RLS requires auth_uid = auth.uid(),
-- which needs an active session) — the app handles this gracefully (it asks
-- them to confirm, then finishes profile setup on their first successful
-- sign-in), but for an internal staff tool with its own Admin-approval gate
-- already built in, email confirmation is a redundant second gate. Turning
-- it off makes signup -> pending-approval instant and simpler to support.
--
-- =========================================================================
-- BOOTSTRAP YOUR FIRST ADMIN ACCOUNT
-- =========================================================================
-- There's no Admin yet to approve the first account, so:
--   1. Open the deployed app, click "Sign up", fill in your own details,
--      create the account normally. You'll land on the "pending approval"
--      screen — that's expected, ignore it for now.
--   2. Come back here (SQL Editor) and run ONLY the statement below, with
--      your email swapped in:

-- update public.users
--    set status = 'approved', user_level = 'Admin'
--  where email = 'you@example.com';

--   3. Go back to the app and sign in again (or just click Sign In if you
--      never signed out) — you're now an approved Admin and can approve
--      everyone else from the Users module from here on.
