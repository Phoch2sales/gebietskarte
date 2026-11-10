-- P² Sales MultiTool: Personal, freie Handelsvertreter (V2.32). Darf mehrfach ausgeführt werden.
-- Provision und Höchstbetrag je Vertrag pro Vertreter. NULL = Standard aus hr_settings
-- (free_commission_pct / free_commission_cap, im Reiter „Einstellungen“ änderbar).
-- Die bestehenden Admin-Policies (supabase/personal.sql) gelten automatisch für die neuen Spalten.
alter table public.hr_employees
  add column if not exists commission_pct numeric check (commission_pct is null or (commission_pct >= 0 and commission_pct <= 100)),
  add column if not exists commission_cap numeric check (commission_cap is null or commission_cap >= 0);
