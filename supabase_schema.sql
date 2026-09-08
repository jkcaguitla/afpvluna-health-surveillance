-- ============================================================================
-- AFP VLUNA — OB-GYN HEALTH SURVEILLANCE & RECORD SYSTEM
-- Supabase (PostgreSQL) Schema — v0.1 (DEMO)
-- Timezone: Asia/Manila (Philippine Standard Time)
-- ============================================================================
-- HOW TO USE
--   1. Create a new Supabase project.
--   2. Open SQL Editor > New query > paste this whole file > Run.
--   3. In Authentication > Providers, make sure "Email" is enabled and
--      "Confirm email" is set per your preference (OFF is easier for a demo).
--   4. Copy your Project URL and anon public key into config.js in the app.
--   5. Create the first ADMIN manually after signing up once (see bottom).
--
-- MIGRATION NOTE (per requirement: must be easy to move off Supabase)
--   - No Supabase-proprietary features are used beyond: `auth.users`,
--     Row Level Security (standard Postgres), and Storage (optional, for
--     future file attachments). Everything else is plain ANSI-ish SQL that
--     runs on any Postgres instance.
--   - If migrating to Oracle or another RDBMS: recreate `profiles` as your
--     own users table decoupled from `auth.users`, re-implement `auth_uid()`
--     to return the current session's user id, and re-write RLS as
--     view/procedure-level checks or application-layer checks. All table
--     and column names are portable (snake_case, no Postgres-only types
--     except `uuid`, `jsonb`, `text[]` — swap `jsonb` for `CLOB`/JSON and
--     `text[]` for a child table on Oracle).
-- ============================================================================

set timezone = 'Asia/Manila';

-- ----------------------------------------------------------------------------
-- EXTENSIONS
-- ----------------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. PROFILES  (extends auth.users — Login / Users Module)
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  email             text not null unique,
  last_name         text not null,
  first_name        text not null,
  middle_name       text,
  gender            text check (gender in ('Male','Female')),
  designation       text,
  rank              text,
  department        text,
  address           text,
  contact_number    text,
  birthdate         date,
  user_level        text not null default 'Junior'
                      check (user_level in ('Admin','Chief Resident','Resident','Senior','Junior','Staff')),
  approved          boolean not null default false,
  -- Access Control checklist per module (spec: OPD, Overview, Directory, Cases,
  -- Legends, Activity Logs, Users, Tasks, Wards, Patient Record)
  access_control    jsonb not null default '{
    "overview": true, "patient_record": true, "cases": true, "opd": true,
    "wards": false, "tasks": true, "directory": true, "users": false,
    "activity_logs": false, "legends": false
  }'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table public.profiles is 'App user profile, 1:1 with auth.users. approved=false blocks module access until an Admin approves.';

-- age is computed on the fly in the app / views, not stored (avoids drift)
create or replace view public.profiles_with_age as
  select *, date_part('year', age(current_date, birthdate))::int as age
  from public.profiles;

-- ----------------------------------------------------------------------------
-- 2. LEGENDS / DEFINITIONS  (Legends Module)
-- Generic key-value catalog so every dropdown in the app can be extended by
-- an Admin without a code deploy, per spec: "these definitions should be in
-- the database so the system can always add new selections."
-- ----------------------------------------------------------------------------
create table if not exists public.legend_options (
  id            uuid primary key default gen_random_uuid(),
  category      text not null,   -- e.g. 'rank','bos','pc','ps','department',...
  value         text not null,
  sort_order    int not null default 0,
  is_active     boolean not null default true,
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  unique (category, value)
);

create index if not exists idx_legend_category on public.legend_options(category);

-- ----------------------------------------------------------------------------
-- 3. PATIENTS  (Patient Record Module)
-- ----------------------------------------------------------------------------
create table if not exists public.patients (
  id                uuid primary key default gen_random_uuid(),
  gender            text check (gender in ('Male','Female')),
  last_name         text not null,
  first_name        text not null,
  middle_name       text,
  birthdate         date,
  rank              text,
  bos               text,
  pc                text,        -- Patient Category
  care_of           text,        -- Military Care Of
  address           text,
  contact_number    text,
  email             text,
  notes             text,
  status            text not null default 'Non-Admitted'
                      check (status in ('Admitted','Discharged','Deceased','Non-Admitted')),
  created_by        uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists idx_patients_lastname on public.patients (last_name);
create index if not exists idx_patients_status on public.patients (status);

-- ----------------------------------------------------------------------------
-- 4. CASES  (Cases Module — currently OB-GYN; other departments TBD)
-- The 8-tab OB-GYN form is stored as structured jsonb per tab so new
-- department forms can be added later without a schema migration.
-- ----------------------------------------------------------------------------
create sequence if not exists case_number_seq start 1;

create table if not exists public.cases (
  id                  uuid primary key default gen_random_uuid(),
  case_number         text not null unique default ('C-' || to_char(now(),'YYYY') || '-' || lpad(nextval('case_number_seq')::text,5,'0')),
  department          text not null default 'Obstetrics and Gynecology (OB-GYN)',
  patient_id          uuid references public.patients(id),
  case_type           text check (case_type in ('OB','GYNE')),
  status              text not null default 'Admitted'
                        check (status in ('Admitted','Discharged','Deceased')),

  -- Tab 1: Admission
  admission           jsonb not null default '{}'::jsonb,
  -- Tab 2: Obstetric History (Obstetric Score) — G,P,FT,PT,Ab
  obstetric_history    jsonb not null default '{}'::jsonb,
  -- Tab 3: Co-morbidities — array of {category, value}
  comorbidities        jsonb not null default '[]'::jsonb,
  -- Tab 4: Gynecological Conditions (reasons, procedures, indications, surgeon)
  gyne_conditions      jsonb not null default '{}'::jsonb,
  -- Tab 5: MIGS Information
  migs                 jsonb not null default '{}'::jsonb,
  -- Tab 6: Blood (not required)
  blood                jsonb not null default '{}'::jsonb,
  -- Tab 7: Final Diagnosis — array of bullet strings
  final_diagnosis      text[] not null default '{}',
  -- Tab 8: Discharge
  discharge            jsonb not null default '{}'::jsonb,

  needs_admin_approval boolean not null default false, -- edits after finalization need Admin/Chief Resident sign-off
  created_by          uuid references public.profiles(id),
  updated_by          uuid references public.profiles(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists idx_cases_patient on public.cases(patient_id);
create index if not exists idx_cases_status on public.cases(status);
create index if not exists idx_cases_department on public.cases(department);
create index if not exists idx_cases_created_at on public.cases(created_at);

-- ----------------------------------------------------------------------------
-- 5. OPD VISITS  (Outpatient Department Module)
-- ----------------------------------------------------------------------------
create table if not exists public.opd_visits (
  id                uuid primary key default gen_random_uuid(),
  patient_id        uuid references public.patients(id),
  consultation_date date not null default current_date,
  registration_status text check (registration_status in ('Registered','Not-Registered','New','Old')),
  info              jsonb not null default '{}'::jsonb,          -- Tab 1
  consultation      jsonb not null default '{}'::jsonb,          -- Tab 2
  procedures        jsonb not null default '[]'::jsonb,          -- Tab 3
  final_diagnosis   text[] not null default '{}',                -- Tab 4
  actions           jsonb not null default '[]'::jsonb,          -- Tab 5
  created_by        uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists idx_opd_patient on public.opd_visits(patient_id);
create index if not exists idx_opd_date on public.opd_visits(consultation_date);

-- ----------------------------------------------------------------------------
-- 6. TASKS  (Tasks Module)
-- ----------------------------------------------------------------------------
create table if not exists public.tasks (
  id                uuid primary key default gen_random_uuid(),
  module             text not null, -- which module this task pertains to
  task_text          text not null,
  assigned_to        uuid references public.profiles(id),
  due_date           date,
  status             text not null default 'Pending' check (status in ('Pending','In-Process','Completed')),
  acknowledged       boolean not null default false,
  completion_notes   text,
  created_by         uuid references public.profiles(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists idx_tasks_assigned on public.tasks(assigned_to);
create index if not exists idx_tasks_module on public.tasks(module);

-- ----------------------------------------------------------------------------
-- 7. DIRECTORY  (Directory Module)
-- ----------------------------------------------------------------------------
create table if not exists public.directory_contacts (
  id                  uuid primary key default gen_random_uuid(),
  last_name           text not null,
  first_name          text not null,
  middle_name         text,
  gender              text check (gender in ('Male','Female')),
  rank                text,
  department          text,
  designation         text,
  contact_number      text,
  email               text,
  address             text,
  birthdate           date,
  emergency_contact_name    text,
  emergency_contact_number  text,
  created_by          uuid references public.profiles(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists idx_directory_lastname on public.directory_contacts(last_name);

-- ----------------------------------------------------------------------------
-- 8. ACTIVITY LOGS  (Activity Logs Module) — append-only audit trail
-- ----------------------------------------------------------------------------
create table if not exists public.activity_logs (
  id            bigint generated always as identity primary key,
  user_id       uuid references public.profiles(id),
  module        text not null,
  action        text not null,       -- e.g. 'create','update','delete','approve','login'
  record_id     text,
  old_data      jsonb,
  new_data      jsonb,
  created_at    timestamptz not null default now()
);

create index if not exists idx_activity_module on public.activity_logs(module);
create index if not exists idx_activity_created on public.activity_logs(created_at desc);
create index if not exists idx_activity_user on public.activity_logs(user_id);

-- ----------------------------------------------------------------------------
-- 9. WARDS  (placeholder table — module explicitly "to follow upon next update")
-- ----------------------------------------------------------------------------
create table if not exists public.wards (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  notes         text,
  created_at    timestamptz not null default now()
);
comment on table public.wards is 'TASK: TO BE UPDATED — Wards Module structure not yet specified. Placeholder only.';

-- ============================================================================
-- TRIGGERS — updated_at auto-touch
-- ============================================================================
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['profiles','patients','cases','opd_visits','tasks','directory_contacts']
  loop
    execute format('drop trigger if exists trg_touch_updated_at on public.%I;', t);
    execute format('create trigger trg_touch_updated_at before update on public.%I for each row execute function public.touch_updated_at();', t);
  end loop;
end $$;

-- Auto-create a profile row (unapproved) whenever someone signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, email, last_name, first_name, middle_name, gender,
    designation, rank, department, address, contact_number, birthdate)
  values (
    new.id, new.email,
    coalesce(new.raw_user_meta_data->>'last_name',''),
    coalesce(new.raw_user_meta_data->>'first_name',''),
    new.raw_user_meta_data->>'middle_name',
    new.raw_user_meta_data->>'gender',
    new.raw_user_meta_data->>'designation',
    new.raw_user_meta_data->>'rank',
    new.raw_user_meta_data->>'department',
    new.raw_user_meta_data->>'address',
    new.raw_user_meta_data->>'contact_number',
    nullif(new.raw_user_meta_data->>'birthdate','')::date
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- HELPER FUNCTIONS FOR RLS (SECURITY DEFINER — read profile without recursion)
-- ============================================================================
create or replace function public.current_profile()
returns public.profiles language sql stable security definer set search_path = public as $$
  select * from public.profiles where id = auth.uid();
$$;

create or replace function public.is_approved()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select approved from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select user_level = 'Admin' and approved from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_admin_or_chief()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select user_level in ('Admin','Chief Resident') and approved from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.has_module_access(module_key text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select approved and (user_level = 'Admin' or (access_control->>module_key)::boolean is true)
     from public.profiles where id = auth.uid()),
    false
  );
$$;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
alter table public.profiles           enable row level security;
alter table public.legend_options     enable row level security;
alter table public.patients           enable row level security;
alter table public.cases              enable row level security;
alter table public.opd_visits         enable row level security;
alter table public.tasks              enable row level security;
alter table public.directory_contacts enable row level security;
alter table public.activity_logs      enable row level security;
alter table public.wards              enable row level security;

-- PROFILES ------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (auth.uid() = id or public.is_admin() or public.has_module_access('users'));

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update
  using (auth.uid() = id or public.is_admin())
  with check (
    auth.uid() = id and (select approved from public.profiles where id = auth.uid()) is not distinct from approved
    or public.is_admin()
  );

drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles for delete
  using (public.is_admin());

-- LEGEND_OPTIONS --------------------------------------------------------------
drop policy if exists legend_select on public.legend_options;
create policy legend_select on public.legend_options for select
  using (public.is_approved());

drop policy if exists legend_write on public.legend_options;
create policy legend_write on public.legend_options for insert
  with check (public.has_module_access('legends'));
drop policy if exists legend_update on public.legend_options;
create policy legend_update on public.legend_options for update
  using (public.has_module_access('legends'));
drop policy if exists legend_delete on public.legend_options;
create policy legend_delete on public.legend_options for delete
  using (public.has_module_access('legends'));

-- Generic pattern applied to the clinical/operational tables -----------------
-- SELECT: any approved user with module access. INSERT: same, stamped as
-- created_by = auth.uid(). UPDATE: module access holders; DELETE: Admin only
-- (spec: delete buttons are Admin-only across every module).

-- PATIENTS
drop policy if exists patients_select on public.patients;
create policy patients_select on public.patients for select using (public.has_module_access('patient_record'));
drop policy if exists patients_insert on public.patients;
create policy patients_insert on public.patients for insert with check (public.has_module_access('patient_record') and created_by = auth.uid());
drop policy if exists patients_update on public.patients;
create policy patients_update on public.patients for update using (public.has_module_access('patient_record'));
drop policy if exists patients_delete on public.patients;
create policy patients_delete on public.patients for delete using (public.is_admin());

-- CASES (edits after creation flagged for approval are still allowed to write,
-- the app enforces the "needs_admin_approval" workflow at the application layer)
drop policy if exists cases_select on public.cases;
create policy cases_select on public.cases for select using (public.has_module_access('cases'));
drop policy if exists cases_insert on public.cases;
create policy cases_insert on public.cases for insert with check (public.has_module_access('cases') and created_by = auth.uid());
drop policy if exists cases_update on public.cases;
create policy cases_update on public.cases for update using (public.has_module_access('cases'));
drop policy if exists cases_delete on public.cases;
create policy cases_delete on public.cases for delete using (public.is_admin());

-- OPD
drop policy if exists opd_select on public.opd_visits;
create policy opd_select on public.opd_visits for select using (public.has_module_access('opd'));
drop policy if exists opd_insert on public.opd_visits;
create policy opd_insert on public.opd_visits for insert with check (public.has_module_access('opd') and created_by = auth.uid());
drop policy if exists opd_update on public.opd_visits;
create policy opd_update on public.opd_visits for update using (public.has_module_access('opd'));
drop policy if exists opd_delete on public.opd_visits;
create policy opd_delete on public.opd_visits for delete using (public.is_admin());

-- TASKS (assignee or creator or admin can see/update; anyone with tasks access can create)
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks for select using (public.has_module_access('tasks'));
drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks for insert with check (public.has_module_access('tasks') and created_by = auth.uid());
drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks for update using (public.has_module_access('tasks') and (assigned_to = auth.uid() or created_by = auth.uid() or public.is_admin()));
drop policy if exists tasks_delete on public.tasks;
create policy tasks_delete on public.tasks for delete using (public.is_admin());

-- DIRECTORY
drop policy if exists directory_select on public.directory_contacts;
create policy directory_select on public.directory_contacts for select using (public.has_module_access('directory'));
drop policy if exists directory_insert on public.directory_contacts;
create policy directory_insert on public.directory_contacts for insert with check (public.has_module_access('directory') and created_by = auth.uid());
drop policy if exists directory_update on public.directory_contacts;
create policy directory_update on public.directory_contacts for update using (public.has_module_access('directory'));
drop policy if exists directory_delete on public.directory_contacts;
create policy directory_delete on public.directory_contacts for delete using (public.is_admin());

-- ACTIVITY LOGS (insert by any approved user for their own actions; read
-- restricted to those with activity_logs access; no update/delete — audit trail is immutable)
drop policy if exists activity_select on public.activity_logs;
create policy activity_select on public.activity_logs for select using (public.has_module_access('activity_logs'));
drop policy if exists activity_insert on public.activity_logs;
create policy activity_insert on public.activity_logs for insert with check (public.is_approved() and user_id = auth.uid());

-- WARDS (placeholder — read-only to any approved user for now)
drop policy if exists wards_select on public.wards;
create policy wards_select on public.wards for select using (public.is_approved());

-- ============================================================================
-- SEED: default legend_options from the spec's Definitions section
-- ============================================================================
insert into public.legend_options (category, value, sort_order) values
-- Rank
('rank','OFF',1),('rank','ENS',2),('rank','ODW',3),('rank','ODD',4),('rank','ODM',5),
('rank','EDW',6),('rank','EDD',7),('rank','EDM',8),('rank','CIV',9),('rank','CIV/P',10),
('rank','CIV/E',11),('rank','CAA',12),('rank','RSVT',13),('rank','RMP',14),('rank','SGT',15),
('rank','CHR',16),('rank','AW1C',17),('rank','SSG',18),('rank','TSG',19),('rank','PVT',20),
('rank','CPT',21),('rank','AW',22),('rank','RES',23),('rank','SN1',24),('rank','CPL',25),
('rank','AW2C',26),('rank','MSG',27),('rank','PO3',28),('rank','PFC',29),('rank','ASN',30),
('rank','MAJ',31),('rank','2LT',32),('rank','SN2',33),('rank','1LT',34),('rank','COL',35),
('rank','MSGT',36),('rank','LTC',37),('rank','CAFGU',38),('rank','PMA CDT',39),
-- BOS
('bos','PA',1),('bos','PAF',2),('bos','PN',3),('bos','PN(M)',4),('bos','TAS',5),('bos','CHR',6),
-- PC (Patient Category)
('pc','MIL',1),('pc','DEP',2),('pc','CIV/E',3),('pc','CIV/P',4),
-- PS (Patient Status)
('ps','Admitted',1),('ps','Discharged',2),('ps','Deceased',3),('ps','Non-Admitted',4),
-- User Level
('user_level','Admin',1),('user_level','Chief Resident',2),('user_level','Resident',3),
('user_level','Senior',4),('user_level','Junior',5),('user_level','Staff',6),
-- Case Type
('case_type','OB',1),('case_type','GYNE',2),
-- Department
('department','Obstetrics and Gynecology (OB-GYN)',1),('department','Internal Medicine',2),
('department','General Surgery',3),('department','Pediatrics',4),('department','Emergency Medicine',5),
('department','Anesthesia',6),('department','Urology',7),('department','Orthopedics and Traumatology',8),
('department','Ophthalmology / Eye Center',9),('department','Otolaryngology (ENT-HNS)',10),
('department','Psychiatry / Mental Health and Behavioral Sciences',11),
('department','Radiological Sciences and Imaging',12),('department','Pathology and Laboratory',13),
('department','Physical & Rehabilitation Medicine',14),
-- Designation
('designation','OB-Surgeon',1),('designation','OB-Doctor',2),
-- Comorbidity (category::subcategory encoded in value with " — " separator for grouping in UI)
('comorbidity','Cardiovascular — Hypertension (High blood pressure)',1),
('comorbidity','Cardiovascular — Congestive Heart Failure (CHF)',2),
('comorbidity','Cardiovascular — Coronary Artery Disease (CAD)',3),
('comorbidity','Cardiovascular — Peripheral Vascular Disease (PVD)',4),
('comorbidity','Cardiovascular — Cardiac arrhythmias',5),
('comorbidity','Respiratory — Chronic Obstructive Pulmonary Disease (COPD)',6),
('comorbidity','Respiratory — Asthma moderate',7),
('comorbidity','Respiratory — Asthma severe',8),
('comorbidity','Respiratory — Chronic respiratory failure or oxygen dependence',9),
('comorbidity','Endocrine & Metabolic — Diabetes Mellitus Type 1',10),
('comorbidity','Endocrine & Metabolic — Diabetes Mellitus Type 2',11),
('comorbidity','Endocrine & Metabolic — Diabetes Mellitus with chronic complications',12),
('comorbidity','Endocrine & Metabolic — Diabetes Mellitus without chronic complications',13),
('comorbidity','Endocrine & Metabolic — Hypothyroidism',14),
('comorbidity','Endocrine & Metabolic — Obesity Class 1 (Moderate: 30-34.9 BMI)',15),
('comorbidity','Endocrine & Metabolic — Obesity Class 2 (Severe: 35.0-39.9 BMI)',16),
('comorbidity','Endocrine & Metabolic — Obesity Class 3 (Morbid: 40.0 above BMI)',17),
('comorbidity','Neurological & Psychiatric — Cerebrovascular Disease',18),
('comorbidity','Neurological & Psychiatric — Dementia or Alzheimer''s Disease',19),
('comorbidity','Neurological & Psychiatric — Chronic depression',20),
('comorbidity','Neurological & Psychiatric — Parkinson''s disease or multiple sclerosis',21),
('comorbidity','Renal & Hepatic — Chronic Kidney Disease (CKD)',22),
('comorbidity','Renal & Hepatic — Cirrhosis or chronic hepatitis / liver failure',23),
('comorbidity','Oncology & Immunology — Solid tumors / Cancer localized',24),
('comorbidity','Oncology & Immunology — Solid tumors / Cancer undergoing treatment',25),
('comorbidity','Oncology & Immunology — Solid tumors / Cancer metastatic',26),
('comorbidity','Oncology & Immunology — Leukemia, lymphoma or multiple myeloma',27),
('comorbidity','Oncology & Immunology — HIV / AIDS',28),
('comorbidity','Oncology & Immunology — Rheumatologic/autoimmune disease',29),
('comorbidity','Gastrointestinal System — Peptic ulcer disease',30),
('comorbidity','Gastrointestinal System — Inflammatory Bowel Disease',31),
-- OB-GYNE Admission Reason
('ob_admission_reason','Labor and delivery',1),('ob_admission_reason','High-Risk Pregnancy',2),
('ob_admission_reason','Cancer (for chemotherapy)',3),('ob_admission_reason','Abnormal Uterine Bleeding',4),
('ob_admission_reason','Incomplete Miscarriage',5),('ob_admission_reason','Preterm Labor',6),
('ob_admission_reason','Threatened Miscarriage',7),('ob_admission_reason','Cancer (others)',8),
('ob_admission_reason','Infertility',9),('ob_admission_reason','Ovarian Mass',10),
('ob_admission_reason','Ectopic Pregnancy',11),('ob_admission_reason','For OR',12),
('ob_admission_reason','Funding',13),('ob_admission_reason','Medical Management',14),
('ob_admission_reason','Threatened Preterm Labor',15),('ob_admission_reason','Marsupialization',16),
('ob_admission_reason','Missed miscarriage',17),
-- EVAC From
('evac_from','AGH',1),('evac_from','Sangley Station Hospital',2),('evac_from','AFGH',3),
('evac_from','CNH',4),('evac_from','CGEASH',5),('evac_from','MNH',6),
('evac_from','Fernando Air Base Hospital',7),('evac_from','Fort Magsaysay',8),
('evac_from','Camp Nakar',9),('evac_from','Camp Capinpin',10),
('evac_from','Naval Station Ernesto Ogbinar',11),('evac_from','FSRR',12),
-- Discharge Status
('discharge_status','RETURN TO DUTY',1),('discharge_status','RETRO EVAC',2),('discharge_status','THOC',3),
('discharge_status','HOME',4),('discharge_status','HAMA',5),('discharge_status','TOS',6),
('discharge_status','ABSCONDED',7),('discharge_status','CDD',8),('discharge_status','DECEASED',9),
-- OB Reason
('ob_reason','NEW PNCU',1),('ob_reason','OLD PNCU',2),('ob_reason','HIGH RISK',3),
('ob_reason','NON HIGH RISK',4),('ob_reason','GESTATIONAL DIABETES',5),('ob_reason','OVERT DIABETES',6),
('ob_reason','APAS',7),('ob_reason','GESTATIONAL HYPERTENSION',8),
('ob_reason','PREECLAMPSIA W/ SEVERE FEATURES',9),('ob_reason','THYROID DISEASE',10),
('ob_reason','ASTHMA',11),('ob_reason','TEENAGE PREGNANCY',12),
('ob_reason','T/C IRON DEFICIENCY ANEMIA',13),('ob_reason','CHRONIC HYPERTENSION',14),
('ob_reason','ADVANCED MATERNAL AGE',15),('ob_reason','BETA THALASSEMIA',16),
('ob_reason','POOR OB SCORE',17),('ob_reason','T/C BREAST CANCER',18),('ob_reason','ACS',19),
-- GYNE Reason
('gyne_reason','AUB',1),('gyne_reason','GYNE INFECTIONS',2),('gyne_reason','MENOPAUSE',3),
('gyne_reason','OVARIAN NEW GROWTH',4),('gyne_reason','PID',5),('gyne_reason','INFERTILITY',6),
('gyne_reason','POP',7),('gyne_reason','PCOS',8),('gyne_reason','CANCER',9),
('gyne_reason','FAMILY PLANNING',10),('gyne_reason','DYSMENORRHEA',11),('gyne_reason','POLYP',12),
('gyne_reason','ENDOMETRIOSIS',13),('gyne_reason','IDCA',14),('gyne_reason','NO GYNE PATHOLOGY',15),
('gyne_reason','T/C ENDOMETRIOSIS',16),('gyne_reason','OVARIAN CYST',17),('gyne_reason','PMOS',18),
('gyne_reason','MYOMA UTERI',19),('gyne_reason','t/c BARTHOLIN CYST',20),
('gyne_reason','LABIAL ADHESION',21),('gyne_reason','t/c APAS',22),
-- OB OPD Procedures
('ob_opd_procedures','PAP SMEAR',1),('ob_opd_procedures','VIA',2),('ob_opd_procedures','COLPOSCOPY',3),
('ob_opd_procedures','OFFICE ENDOMETRIAL BIOPSY',4),('ob_opd_procedures','CERVICAL PUNCH BIOPSY',5),
('ob_opd_procedures','HYSTEROGRAM',6),
-- Family Planning
('family_planning','BTL',1),('family_planning','CS WITH BTL',2),('family_planning','IUD',3),
('family_planning','PILLS',4),('family_planning','DMPA',5),('family_planning','IMPLANT',6),
('family_planning','CONTEMPLATING',7),('family_planning','NONE',8),
-- OB-GYN Procedures (Minor/Major not pre-classified here — Admin can tag via Legends UI note)
('ob_gyn_procedures','Spontaneous Vaginal Delivery',1),
('ob_gyn_procedures','Assisted Vaginal Delivery (Forceps/Vacuum)',2),
('ob_gyn_procedures','Completion curettage',3),('ob_gyn_procedures','Dilatation and curettage',4),
('ob_gyn_procedures','Endometrial Biopsy',5),('ob_gyn_procedures','Cervical Biopsy',6),
('ob_gyn_procedures','Suction Curettage',7),('ob_gyn_procedures','Cesarean Delivery',8),
('ob_gyn_procedures','Primary CS',9),('ob_gyn_procedures','Repeat CS',10),
('ob_gyn_procedures','Repeat CS w/ BTL',11),('ob_gyn_procedures','Hysterectomy',12),
('ob_gyn_procedures','Adnexal Surgery',13),('ob_gyn_procedures','Myomectomy',14),
('ob_gyn_procedures','Vaginal Hysterectomy',15),('ob_gyn_procedures','TAHBS',16),
('ob_gyn_procedures','TAHBSO',17),('ob_gyn_procedures','EHBSO',18),('ob_gyn_procedures','RHBSO',19),
('ob_gyn_procedures','Unilateral Oophoro-Cystectomy',20),
('ob_gyn_procedures','Bilateral Oophorocystectomy',21),
('ob_gyn_procedures','Unilateral Oophorectomy',22),('ob_gyn_procedures','Bilateral Oophorectomy',23),
('ob_gyn_procedures','Unilateral Salpingo-Oophorectomy',24),
('ob_gyn_procedures','Bilateral Salpingo-oophorectomy',25),
('ob_gyn_procedures','Unilateral Salpingectomy',26),('ob_gyn_procedures','Bilateral Salpingectomy',27),
('ob_gyn_procedures','Hysteroscopic Guided Endometrial Biopsy',28),
('ob_gyn_procedures','Electrocautery',29),('ob_gyn_procedures','Hysteroscopic guided polypectomy',30),
('ob_gyn_procedures','Laparoscopic Salpingectomy',31),('ob_gyn_procedures','Unilateral fimbriectomy',32),
('ob_gyn_procedures','Hysteroscopic guided IUD removal',33),
('ob_gyn_procedures','LEEP',34),('ob_gyn_procedures','Cervical Polypectomy',35),
('ob_gyn_procedures','Colposcopy',36),
('ob_gyn_procedures','Evacuation of Hematoma, Ligation of bleeders, and Repair of Perineal Laceration',37),
('ob_gyn_procedures','Excision of perineal granulation tissue',38),
('ob_gyn_procedures','Enterolysis, Adhesiolysis, TAH',39),
('ob_gyn_procedures','Resection of septum Diagnostic Laparoscopy, chromopertubation',40),
('ob_gyn_procedures','Endometrial curettage',41),
-- Indication for Primary CS
('indication_primary_cs','NRFHRP',1),('indication_primary_cs','Fetal Malpresentation',2),
('indication_primary_cs','Failed Induction of labor',3),
('indication_primary_cs','Preeclampsia with severe features - uncontrolled',4),
('indication_primary_cs','Arrest in cervical Dilation',5),
('indication_primary_cs','Prolonged Second Stage',6),
('indication_primary_cs','Prolonged Deceleration Phase',7),
('indication_primary_cs','Abnormal Placentation',8),
('indication_primary_cs','Cephalopelvic Disproportion',9),
('indication_primary_cs','Deteriorating Fetal Status',10),
('indication_primary_cs','Placenta previa',11),('indication_primary_cs','Oligohydramnios',12),
('indication_primary_cs','Poor Bishop Score',13),('indication_primary_cs','Non inducible cervix',14),
('indication_primary_cs','Failure in Descent',15),('indication_primary_cs','Arrest in Descent',16)
on conflict (category, value) do nothing;

-- ============================================================================
-- AFTER RUNNING THIS FILE:
--   1. Sign up your first user through the app's Sign-up form.
--   2. In the SQL editor, run:
--        update public.profiles set user_level = 'Admin', approved = true
--        where email = 'your-admin-email@example.com';
--   3. Log back in — you'll now see the Users module and can approve others.
-- ============================================================================
