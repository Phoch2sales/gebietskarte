-- P² Sales MultiTool: Personal, V2.32 (freie Handelsvertreter, Sofort-Stornos). Darf mehrfach ausgeführt werden.
-- Die bestehenden Admin-only-Policies (supabase/personal.sql) gelten automatisch für die neuen Spalten.

-- 1) Provision und Höchstbetrag je Vertrag pro Vertreter. NULL = Standard aus hr_settings
--    (free_commission_pct / free_commission_cap, im Reiter „Einstellungen“ änderbar).
alter table public.hr_employees
  add column if not exists commission_pct numeric check (commission_pct is null or (commission_pct >= 0 and commission_pct <= 100)),
  add column if not exists commission_cap numeric check (commission_cap is null or commission_cap >= 0);

-- 2) Sofort-Stornos (schon vor der Auszahlung klar, z. B. Bonität): werden im selben Monat abgezogen.
--    Die bisherige Spalte "cancelled" gilt weiter für Folge-Stornos (Abzug im Folgemonat).
alter table public.hr_performance
  add column if not exists cancelled_instant integer not null default 0 check (cancelled_instant >= 0);
