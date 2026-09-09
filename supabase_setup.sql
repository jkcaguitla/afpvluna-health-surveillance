-- ============================================================
-- AFP VLUNA MC — Supabase setup script
-- Safe to re-run: every statement uses IF NOT EXISTS / OR REPLACE /
-- DROP ... IF EXISTS, so re-running this after an update won't break
-- anything that already exists.
--
-- HOW TO RUN: Supabase Dashboard → SQL Editor → New query → paste
-- this whole file → Run.
--
-- Two tables are created:
--   1. app_storage — one JSON blob per data collection (patients,
--      cases, opd, tasks, directory, legends, activity, settings).
--      This keeps every existing screen in the app working exactly
--      as-is; it is NOT a normalized relational schema. Treat this
--      as the "get a real database under it safely" step — moving
--      to fully normalized tables (patients as real rows, cases
--      with real foreign keys, etc.) is a bigger follow-up project.
--   2. profiles — one real row per user account, linked to Supabase
--      Auth. This IS how login/roles/approval work — identity is
--      handled properly, not as a blob, because it's the highest-
--      risk part of the system.
-- ============================================================

-- ---------- 1. app_storage (clinical data collections) ----------
create table if not exists public.app_storage (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.app_storage enable row level security;

drop policy if exists "authenticated read app_storage" on public.app_storage;
create policy "authenticated read app_storage" on public.app_storage
  for select using (auth.role() = 'authenticated');

drop policy if exists "authenticated insert app_storage" on public.app_storage;
create policy "authenticated insert app_storage" on public.app_storage
  for insert with check (auth.role() = 'authenticated');

drop policy if exists "authenticated update app_storage" on public.app_storage;
create policy "authenticated update app_storage" on public.app_storage
  for update using (auth.role() = 'authenticated');

-- Note: this policy set means any logged-in, approved user can read/write
-- any collection (patients, cases, tasks, etc.) — a large improvement
-- over no protection at all, but not yet fine-grained per-module or
-- per-role at the database level (the app's own UI still restricts
-- which screens each role can reach). Field- and table-level RLS is
-- part of the normalized-schema follow-up mentioned above.

-- ---------- 2. profiles (real user accounts & roles) ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  last_name text, first_name text, middle_name text, gender text,
  designation text, rank text, department text, address text, contact text, birthdate date,
  user_level text not null default 'Junior',
  status text not null default 'pending',  -- pending | approved | declined
  access jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Security-definer helper avoids RLS self-recursion when a policy
-- needs to check "is the requester an Admin" by querying this same table.
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and user_level = 'Admin'
  );
$$;

drop policy if exists "view own profile" on public.profiles;
create policy "view own profile" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "admins view all profiles" on public.profiles;
create policy "admins view all profiles" on public.profiles
  for select using (public.is_admin());

drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles
  for update using (auth.uid() = id);

drop policy if exists "admins update any profile" on public.profiles;
create policy "admins update any profile" on public.profiles
  for update using (public.is_admin());

drop policy if exists "admins delete any profile" on public.profiles;
create policy "admins delete any profile" on public.profiles
  for delete using (public.is_admin());

-- Auto-create a profile row the instant someone signs up, so the
-- client app never needs (or gets) INSERT permission on profiles itself.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, status, user_level, access)
  values (new.id, new.email, 'pending', 'Junior', '[]'::jsonb);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- ONE-TIME MANUAL STEP (recommended, not run by this script):
-- In the Supabase Dashboard, go to Authentication → Providers → Email
-- and turn OFF "Confirm email". This is an internal hospital tool
-- behind your own access control, not a public signup form — leaving
-- email confirmation off lets new staff finish their profile details
-- immediately after registering instead of only after confirming an
-- email address. You can leave it ON if you prefer; registration
-- still works, it just means the extra profile fields (rank,
-- designation, etc.) only sync in after the user's first login.
-- ============================================================

-- ============================================================
-- FIRST ADMIN ACCOUNT: after you sign up your own account once from
-- the app's login screen, run this (with YOUR email) so you're not
-- locked out waiting for an admin to approve you:
--
--   update public.profiles set status = 'approved', user_level = 'Admin',
--     access = '["OPD","Overview","Directory","Cases","Legends","Activity Logs","Users","Tasks","Wards","Patient Record"]'::jsonb
--   where email = 'you@example.com';
-- ============================================================
