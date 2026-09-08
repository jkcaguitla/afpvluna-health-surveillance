-- ============================================================================
-- AFP MEDICAL CENTER — OB-GYN HEALTH SURVEILLANCE SYSTEM
-- Supabase Schema (PostgreSQL)
-- Paste this whole file into: Supabase Dashboard -> SQL Editor -> New query -> Run
-- ============================================================================
-- Notes:
-- 1) Uses Supabase Auth (auth.users) for login. profiles is a 1-1 extension.
-- 2) "legends" is a generic, extensible lookup table so every dropdown in the
--    app (Rank, BOS, PC, Department, Designation, Comorbidity, Procedures,
--    Indications, Reasons, etc.) can have new options added without a schema
--    change or redeploy. This is what the spec calls "Legends Module".
-- 3) A trigger auto-mirrors every approved user into the "directory" table,
--    satisfying: "Registered Users automatically registered to Directory".
-- 4) Data-heavy fields for Cases/OPD (tabs, multi-add lists, notes) are kept
--    as JSONB so the form structure can evolve without migrations, while
--    core reporting fields are real columns for fast filtering/graphs.
-- 5) Everything is written in plain, portable SQL/JSON so migrating off
--    Supabase to Oracle/Postgres/etc later mainly means re-pointing the
--    thin data-access layer in the HTML file (see js: const db = {...}).
-- ============================================================================

-- Timezone: Philippine Standard Time for this session's DDL defaults
set timezone = 'Asia/Manila';

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. LEGENDS (extensible dropdown lists)
-- ---------------------------------------------------------------------------
create table if not exists public.legends (
  id uuid primary key default gen_random_uuid(),
  category text not null,          -- e.g. 'rank','bos','pc','department','designation',
                                    -- 'comorbidity','ob_admission_reason','ob_gyn_procedure',
                                    -- 'indication_primary_cs','discharge_status','ob_reason',
                                    -- 'gyne_reason','ob_opd_procedure','family_planning','evac_from'
  value text not null,
  sort_order int default 0,
  active boolean default true,
  created_by uuid references auth.users(id),
  created_at timestamptz default now()
);
create unique index if not exists legends_category_value_uidx on public.legends (category, lower(value));
create index if not exists legends_category_idx on public.legends (category);

-- ---------------------------------------------------------------------------
-- 2. PROFILES (extends auth.users)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  last_name text,
  first_name text,
  middle_name text,
  gender text check (gender in ('Male','Female')),
  designation text,                 -- dropdown, from legends category 'designation'
  rank text,
  department text,
  address text,
  contact_number text,
  birthdate date,
  user_level text default 'Pending' check (user_level in ('Pending','Admin','Chief Resident','Resident','Senior','Junior','Staff')),
  status text default 'Pending Approval' check (status in ('Pending Approval','Approved','Declined')),
  access_control jsonb default '[]'::jsonb, -- e.g. ["OPD","Overview","Directory","Cases","Legends","Activity Logs","Users","Tasks","Wards","Patient Record"]
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- age is derived at query time (kept as a generated column for convenience)
alter table public.profiles drop column if exists age;
alter table public.profiles add column age int generated always as
  (date_part('year', age(birthdate))::int) stored;

-- ---------------------------------------------------------------------------
-- 3. DIRECTORY (hospital contact directory — includes all registered users
--    PLUS manually-added contacts who may not have a login)
-- ---------------------------------------------------------------------------
create table if not exists public.directory (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null, -- null = manual contact
  last_name text,
  first_name text,
  middle_name text,
  gender text check (gender in ('Male','Female')),
  rank text,
  department text,
  designation text,
  contact_number text,
  email text,
  address text,
  birthdate date,
  emergency_contact_name text,
  emergency_contact_number text,
  is_doctor boolean default false, -- true for OB-Surgeon/OB-Doctor designations, used for OPD/Cases pickers
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.directory drop column if exists age;
alter table public.directory add column age int generated always as
  (date_part('year', age(birthdate))::int) stored;

-- ---------------------------------------------------------------------------
-- 4. PATIENT RECORD
-- ---------------------------------------------------------------------------
create table if not exists public.patients (
  id uuid primary key default gen_random_uuid(),
  last_name text,
  first_name text,
  middle_name text,
  gender text check (gender in ('Male','Female')),
  birthdate date,
  rank text,
  bos text,       -- Branch of Service
  pc text,        -- Patient Category
  ps text default 'Non-Admitted' check (ps in ('Admitted','Discharged','Deceased','Non-Admitted')),
  care_of text,
  address text,
  contact_number text,
  email text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.patients drop column if exists age;
alter table public.patients add column age int generated always as
  (date_part('year', age(birthdate))::int) stored;
create index if not exists patients_name_idx on public.patients (last_name, first_name);

-- ---------------------------------------------------------------------------
-- 5. CASES (OB-GYN case form — 8 tabs stored as JSONB "data" + key columns)
-- ---------------------------------------------------------------------------
create table if not exists public.cases (
  id uuid primary key default gen_random_uuid(),
  case_no text unique,
  department text default 'Obstetrics and Gynecology (OB-GYN)',
  patient_id uuid references public.patients(id),
  case_type text check (case_type in ('OB','GYNE')),
  status text default 'Admitted' check (status in ('Admitted','Discharged','Deceased')),
  admission_date date,
  discharge_date date,
  surgeons jsonb default '[]'::jsonb,             -- array of directory ids/names
  indications_primary_cs jsonb default '[]'::jsonb, -- array of strings
  comorbidities jsonb default '[]'::jsonb,
  ob_gyn_admission_reasons jsonb default '[]'::jsonb,
  ob_gyn_procedures jsonb default '[]'::jsonb,
  final_diagnosis jsonb default '[]'::jsonb,       -- array of bullet strings
  data jsonb default '{}'::jsonb,                  -- everything else (all 8 tabs)
  needs_admin_approval boolean default false,
  approved boolean default true,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create sequence if not exists public.case_no_seq start 1;
create index if not exists cases_patient_idx on public.cases (patient_id);
create index if not exists cases_status_idx on public.cases (status);

-- ---------------------------------------------------------------------------
-- 6. OPD (Outpatient Department)
-- ---------------------------------------------------------------------------
create table if not exists public.opd (
  id uuid primary key default gen_random_uuid(),
  consultation_date date default (now() at time zone 'Asia/Manila')::date,
  patient_id uuid references public.patients(id),
  registration_status text check (registration_status in ('Registered','Not-Registered','New','Old')),
  case_type text check (case_type in ('OB','Gyne')),
  high_risk boolean default false,
  consultants jsonb default '[]'::jsonb,  -- array of {id,name} from Directory (multi-add)
  residents jsonb default '[]'::jsonb,    -- array of {id,name} from Directory (multi-add)
  ob_reasons jsonb default '[]'::jsonb,   -- multi-add
  gyne_reasons jsonb default '[]'::jsonb, -- multi-add
  family_planning text,
  procedures jsonb default '[]'::jsonb,
  final_diagnosis jsonb default '[]'::jsonb,
  actions jsonb default '[]'::jsonb,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists opd_date_idx on public.opd (consultation_date desc);
create index if not exists opd_patient_idx on public.opd (patient_id);

-- ---------------------------------------------------------------------------
-- 7. TASKS
-- ---------------------------------------------------------------------------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  assigned_to uuid references public.profiles(id),
  module text,        -- which module the task refers to (OPD, Cases, Wards, etc)
  task text,
  due_date date,
  status text default 'Pending' check (status in ('Pending','Acknowledged','In-Process','Completed')),
  completion_notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists tasks_assigned_idx on public.tasks (assigned_to);

-- ---------------------------------------------------------------------------
-- 8. ACTIVITY LOGS
-- ---------------------------------------------------------------------------
create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  module text,
  activity text,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz default now()
);
create index if not exists activity_logs_module_idx on public.activity_logs (module);
create index if not exists activity_logs_created_idx on public.activity_logs (created_at desc);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- updated_at helper
create or replace function public.set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_profiles_updated on public.profiles;
create trigger trg_profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();
drop trigger if exists trg_directory_updated on public.directory;
create trigger trg_directory_updated before update on public.directory
  for each row execute function public.set_updated_at();
drop trigger if exists trg_patients_updated on public.patients;
create trigger trg_patients_updated before update on public.patients
  for each row execute function public.set_updated_at();
drop trigger if exists trg_cases_updated on public.cases;
create trigger trg_cases_updated before update on public.cases
  for each row execute function public.set_updated_at();
drop trigger if exists trg_opd_updated on public.opd;
create trigger trg_opd_updated before update on public.opd
  for each row execute function public.set_updated_at();
drop trigger if exists trg_tasks_updated on public.tasks;
create trigger trg_tasks_updated before update on public.tasks
  for each row execute function public.set_updated_at();

-- Auto-create a Pending profile row whenever someone signs up via Supabase Auth
create or replace function public.handle_new_auth_user() returns trigger as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- "Registered Users automatically registered to Directory"
-- Whenever a profile is approved (status = 'Approved'), upsert it into Directory.
create or replace function public.sync_profile_to_directory() returns trigger as $$
begin
  if new.status = 'Approved' then
    insert into public.directory (
      profile_id, last_name, first_name, middle_name, gender, rank,
      department, designation, contact_number, email, address, birthdate,
      is_doctor
    ) values (
      new.id, new.last_name, new.first_name, new.middle_name, new.gender, new.rank,
      new.department, new.designation, new.contact_number, new.email, new.address, new.birthdate,
      (new.designation in ('OB-Surgeon','OB-Doctor'))
    )
    on conflict (profile_id) do update set
      last_name = excluded.last_name,
      first_name = excluded.first_name,
      middle_name = excluded.middle_name,
      gender = excluded.gender,
      rank = excluded.rank,
      department = excluded.department,
      designation = excluded.designation,
      contact_number = excluded.contact_number,
      email = excluded.email,
      address = excluded.address,
      birthdate = excluded.birthdate,
      is_doctor = excluded.is_doctor,
      updated_at = now();
  end if;
  return new;
end;
$$ language plpgsql security definer;

-- profile_id must be unique so the upsert above (on conflict) works
create unique index if not exists directory_profile_id_uidx on public.directory (profile_id) where profile_id is not null;

drop trigger if exists trg_sync_profile_to_directory on public.profiles;
create trigger trg_sync_profile_to_directory
  after insert or update of status, last_name, first_name, middle_name, gender, rank,
    department, designation, contact_number, address, birthdate
  on public.profiles
  for each row execute function public.sync_profile_to_directory();

-- Auto case number generator: CASE-YYYY-000001
create or replace function public.set_case_no() returns trigger as $$
begin
  if new.case_no is null then
    new.case_no := 'CASE-' || to_char(now(),'YYYY') || '-' || lpad(nextval('public.case_no_seq')::text,6,'0');
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_set_case_no on public.cases;
create trigger trg_set_case_no before insert on public.cases
  for each row execute function public.set_case_no();

-- ============================================================================
-- ROW LEVEL SECURITY  (demo-friendly: any authenticated + approved user may
-- read/write; only Admin/Chief Resident may delete or approve users. Tighten
-- further per real deployment / when migrating to a stricter platform.)
-- ============================================================================
alter table public.legends enable row level security;
alter table public.profiles enable row level security;
alter table public.directory enable row level security;
alter table public.patients enable row level security;
alter table public.cases enable row level security;
alter table public.opd enable row level security;
alter table public.tasks enable row level security;
alter table public.activity_logs enable row level security;

create or replace function public.is_admin() returns boolean as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and user_level in ('Admin','Chief Resident') and status = 'Approved'
  );
$$ language sql security definer stable;

create or replace function public.is_approved() returns boolean as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and status = 'Approved'
  );
$$ language sql security definer stable;

-- profiles: user can see/update own row; approved users can see all (Users module list);
-- only admin can update others / approve / change user_level.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (auth.uid() = id or public.is_approved());

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update
  using (auth.uid() = id or public.is_admin());

drop policy if exists profiles_delete_admin on public.profiles;
create policy profiles_delete_admin on public.profiles for delete
  using (public.is_admin());

-- Generic policy shape for the rest: approved users can select/insert/update,
-- only admin can delete.
do $$
declare t text;
begin
  foreach t in array array['legends','directory','patients','cases','opd','tasks','activity_logs'] loop
    execute format('drop policy if exists %I_select on public.%I;', t, t);
    execute format('create policy %I_select on public.%I for select using (public.is_approved());', t, t);
    execute format('drop policy if exists %I_insert on public.%I;', t, t);
    execute format('create policy %I_insert on public.%I for insert with check (public.is_approved());', t, t);
    execute format('drop policy if exists %I_update on public.%I;', t, t);
    execute format('create policy %I_update on public.%I for update using (public.is_approved());', t, t);
    execute format('drop policy if exists %I_delete on public.%I;', t, t);
    execute format('create policy %I_delete on public.%I for delete using (public.is_admin());', t, t);
  end loop;
end $$;

-- ============================================================================
-- SEED DATA — Legends (from the AFP_VLUNA spec)
-- ============================================================================
insert into public.legends (category, value, sort_order) values
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
-- PC
('pc','MIL',1),('pc','DEP',2),('pc','CIV/E',3),('pc','CIV/P',4),
-- PS
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
-- Comorbidity
('comorbidity','Hypertension (High blood pressure)',1),('comorbidity','Congestive Heart Failure (CHF)',2),
('comorbidity','Coronary Artery Disease (CAD)',3),('comorbidity','Peripheral Vascular Disease (PVD)',4),
('comorbidity','Cardiac arrhythmias',5),('comorbidity','Chronic Obstructive Pulmonary Disease (COPD)',6),
('comorbidity','Asthma moderate',7),('comorbidity','Asthma severe',8),
('comorbidity','Chronic respiratory failure or oxygen dependence',9),
('comorbidity','Diabetes Mellitus Type 1',10),('comorbidity','Diabetes Mellitus Type 2',11),
('comorbidity','Diabetes Mellitus with chronic complications',12),
('comorbidity','Diabetes Mellitus without chronic complications',13),('comorbidity','Hypothyroidism',14),
('comorbidity','Obesity Class 1 (Moderate: 30-34.9 BMI)',15),
('comorbidity','Obesity Class 2 (Severe: 35.0-39.9 BMI)',16),
('comorbidity','Obesity Class 3 (Morbid: 40.0 above BMI)',17),
('comorbidity','Cerebrovascular Disease',18),('comorbidity','Dementia or Alzheimer''s Disease',19),
('comorbidity','Chronic depression',20),('comorbidity','Parkinson''s disease or multiple sclerosis',21),
('comorbidity','Chronic Kidney Disease (CKD)',22),
('comorbidity','Cirrhosis or chronic hepatitis / liver failure',23),
('comorbidity','Solid tumors / Cancer localized',24),
('comorbidity','Solid tumors / Cancer undergoing treatment',25),
('comorbidity','Solid tumors / Cancer metastatic',26),
('comorbidity','Leukemia, lymphoma or multiple myeloma',27),('comorbidity','HIV / AIDS',28),
('comorbidity','Rheumatologic/autoimmune disease',29),('comorbidity','Peptic ulcer disease',30),
('comorbidity','Inflammatory Bowel Disease',31),
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
-- OB-GYN Procedures
('ob_gyn_procedure','Spontaneous Vaginal Delivery',1),
('ob_gyn_procedure','Assisted Vaginal Delivery (Forceps/Vacuum)',2),
('ob_gyn_procedure','Completion curettage',3),('ob_gyn_procedure','Dilatation and curettage',4),
('ob_gyn_procedure','Endometrial Biopsy',5),('ob_gyn_procedure','Cervical Biopsy',6),
('ob_gyn_procedure','Suction Curettage',7),('ob_gyn_procedure','Cesarean Delivery',8),
('ob_gyn_procedure','Primary CS',9),('ob_gyn_procedure','Repeat CS',10),
('ob_gyn_procedure','Repeat CS w/ BTL',11),('ob_gyn_procedure','Hysterectomy',12),
('ob_gyn_procedure','Adnexal Surgery',13),('ob_gyn_procedure','Myomectomy',14),
('ob_gyn_procedure','Vaginal Hysterectomy',15),('ob_gyn_procedure','TAHBS',16),
('ob_gyn_procedure','TAHBSO',17),('ob_gyn_procedure','EHBSO',18),('ob_gyn_procedure','RHBSO',19),
('ob_gyn_procedure','Unilateral Oophoro-Cystectomy',20),
('ob_gyn_procedure','Bilateral Oophorocystectomy',21),
('ob_gyn_procedure','Unilateral Oophorectomy',22),('ob_gyn_procedure','Bilateral Oophorectomy',23),
('ob_gyn_procedure','Unilateral Salpingo-Oophorectomy',24),
('ob_gyn_procedure','Bilateral Salpingo-oophorecotmy',25),
('ob_gyn_procedure','Unilateral Salpingectomy',26),('ob_gyn_procedure','Bilateral Salpingectomy',27),
('ob_gyn_procedure','Hysteroscopic Guided Endometrial Biopsy',28),
('ob_gyn_procedure','Electrocautery',29),('ob_gyn_procedure','Hysteroscopic guided polypectomy',30),
('ob_gyn_procedure','Laparoscopic Salpingectomy',31),('ob_gyn_procedure','Unilateral fimbriectomy',32),
('ob_gyn_procedure','Hysteroscopic guided IUD removal',33),
('ob_gyn_procedure','EL Salpingophorectomy Right with Frozen section and Total Abdominal Hysterectomy with Salpingectomy Left with Adhesiolysis',34),
('ob_gyn_procedure','EL, PFC, Extrafascial Hysterectomy with Bilateral Salpingoophorectomy, Vaginectomy with BLND, PALS under SAB/CEA converted to GA',35),
('ob_gyn_procedure','LEEP',36),('ob_gyn_procedure','Cervical Polypectomy',37),
('ob_gyn_procedure','Colposcopy',38),
('ob_gyn_procedure','Evacuation of Hematoma, Ligation of bleeders, and Repair of Perineal Laceration',39),
('ob_gyn_procedure','Excision of perineal granulation tissue',40),
('ob_gyn_procedure','Enterolysis, Adhesiolysis, TAH',41),
('ob_gyn_procedure','Bilateral Oophorocystectomy with excision of Paratubal Cyst, Right',42),
('ob_gyn_procedure','Resection of septum Diagnostic Laparoscopy, chromopertubation',43),
('ob_gyn_procedure','Endometrial curettage',44),
('ob_gyn_procedure','EL, Evacuation of Hemoperitoneum, Salpingectomy, Left under Spinal anesthesia',45),
-- Indication for Primary CS
('indication_primary_cs','NRFHRP',1),('indication_primary_cs','Fetal Malpresentation',2),
('indication_primary_cs','Failed Induction of labor',3),
('indication_primary_cs','Preeclampsia with severe features - uncontrolled',4),
('indication_primary_cs','Arrest in cervical Dilation',5),
('indication_primary_cs','Prolonged Second Stage',6),
('indication_primary_cs','Prolonged Deceleration Phase',7),
('indication_primary_cs','Abnormal Placentation',8),
('indication_primary_cs','Cephalopelvic Disproportion',9),
('indication_primary_cs','Deteriorating Fetal Status',10),('indication_primary_cs','Placenta previa',11),
('indication_primary_cs','Oligohydramnios',12),('indication_primary_cs','Poor Bishop Score',13),
('indication_primary_cs','Non inducible cervix',14),('indication_primary_cs','Failure in Descent',15),
('indication_primary_cs','Arrest in Descent',16),
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
('ob_opd_procedure','PAP SMEAR',1),('ob_opd_procedure','VIA',2),('ob_opd_procedure','COLPOSCOPY',3),
('ob_opd_procedure','OFFICE ENDOMETRIAL BIOPSY',4),('ob_opd_procedure','CERVICAL PUNCH BIOPSY',5),
('ob_opd_procedure','HYSTEROGRAM',6),
-- Family Planning
('family_planning','BTL',1),('family_planning','CS WITH BTL',2),('family_planning','IUD',3),
('family_planning','PILLS',4),('family_planning','DMPA',5),('family_planning','IMPLANT',6),
('family_planning','CONTEMPLATING',7),('family_planning','NONE',8),
-- Registration Status (OPD)
('registration_status','Registered',1),('registration_status','Not-Registered',2),
('registration_status','New',3),('registration_status','Old',4),
-- Access modules (for Access Control checklist)
('access_module','OPD',1),('access_module','Overview',2),('access_module','Directory',3),
('access_module','Cases',4),('access_module','Legends',5),('access_module','Activity Logs',6),
('access_module','Users',7),('access_module','Tasks',8),('access_module','Wards',9),
('access_module','Patient Record',10)
on conflict (category, lower(value)) do nothing;

-- ============================================================================
-- OPTIONAL: create your first Admin account
-- 1) Sign up normally through the app's Sign Up form first.
-- 2) Then run this (replace the email) to approve yourself as Admin:
--
-- update public.profiles
--   set user_level = 'Admin', status = 'Approved',
--       access_control = '["OPD","Overview","Directory","Cases","Legends","Activity Logs","Users","Tasks","Wards","Patient Record"]'
--   where email = 'youremail@example.com';
-- ============================================================================
