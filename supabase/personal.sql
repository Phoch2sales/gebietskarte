-- P² Sales MultiTool: Admin-Bereich „Personal“ (Mitarbeiter, Performance, Einstellungen).
-- Darf mehrfach ausgeführt werden. Voraussetzung: public.is_admin() existiert (kommt aus schema.sql).
-- Nur Admins (profiles.role = 'admin' und active) dürfen lesen und schreiben. Vertreter sehen nichts.

-- 1) Mitarbeiter
create table if not exists public.hr_employees (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (length(trim(name)) > 0),
  contract_type text not null default 'frei' check (contract_type in ('frei','befristet','unbefristet')),
  start_date    date not null,
  probation_end date,                 -- Start + 6 Monate (änderbar)
  fixed_end     date,                 -- Start + 24 Monate, nur bei „befristet“ (änderbar)
  status        text not null default 'aktiv' check (status in ('aktiv','ausgeschieden')),
  notes         text not null default '',
  user_id       uuid references auth.users(id) on delete set null,  -- optional: App-Nutzer
  created_at    timestamptz not null default now()
);

-- 2) Performance pro Mitarbeiter und Monat (month = immer der 1. des Monats)
create table if not exists public.hr_performance (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  month       date not null check (extract(day from month) = 1),
  closed      integer not null default 0 check (closed >= 0),
  cancelled   integer not null default 0 check (cancelled >= 0),
  updated_at  timestamptz not null default now(),
  unique (employee_id, month)
);

-- 3) Einstellungen (genau eine Zeile; Werte als JSON, damit nichts fest im Code steht)
create table if not exists public.hr_settings (
  id   integer primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb
);
insert into public.hr_settings (id, data) values (1, '{
  "fixed_salary": 2700,
  "tier_limit": 30,
  "rate_low": 30,
  "rate_high": 50,
  "employer_pct": 21,
  "bg_pct": 1,
  "revenue_per_contract": 150,
  "targets": [15, 30, 45, 55, 60],
  "yellow_from": 35,
  "probation_months": 6,
  "fixed_months": 24,
  "lead_probation_weeks": 8,
  "lead_month12_weeks": 8,
  "lead_fixed_weeks": 12
}'::jsonb) on conflict (id) do nothing;

-- 4) Row Level Security: nur Admin
alter table public.hr_employees   enable row level security;
alter table public.hr_performance enable row level security;
alter table public.hr_settings    enable row level security;

drop policy if exists "Admin alles" on public.hr_employees;
drop policy if exists "Admin alles" on public.hr_performance;
drop policy if exists "Admin alles" on public.hr_settings;
create policy "Admin alles" on public.hr_employees   for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin alles" on public.hr_performance for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin alles" on public.hr_settings    for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on public.hr_employees, public.hr_performance, public.hr_settings from anon, authenticated;
grant select, insert, update, delete on public.hr_employees, public.hr_performance, public.hr_settings to authenticated;
