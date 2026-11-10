-- P² Sales MultiTool: Mitarbeiterbereich, Stammdatenblatt (V2.33). Darf mehrfach ausgeführt werden.
-- Voraussetzung: public.is_admin() und public.is_active() existieren (schema.sql).
--
-- Datenschutz: Jeder aktive Zugang sieht und ändert NUR sein eigenes Stammdatenblatt.
-- Admins sehen und ändern alle. Alle anderen (andere Vertreter, Anonyme) haben keinen Zugriff.
-- Enthält personenbezogene Daten (Steuer-ID, IBAN, Sozialversicherungsnummer): nicht in Logs/Exporte kopieren.

create table if not exists public.member_profiles (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  member_type    text not null default 'frei' check (member_type in ('frei','fest')),
  first_name     text,
  last_name      text,
  birth_date     date,
  street         text,
  zip            text check (zip is null or zip ~ '^[0-9]{5}$'),
  city           text,
  phone          text,
  -- Selbstständigkeit (nur freie Handelsvertreter)
  company_name            text,
  gewerbe_since           date,
  reisegewerbekarte_no    text,
  reisegewerbekarte_until date,
  small_business          boolean not null default false,
  -- Steuer und Sozialversicherung
  tax_id          text check (tax_id is null or tax_id ~ '^[1-9][0-9]{10}$'),
  tax_number      text,
  vat_id          text,
  sv_number       text,
  health_insurance text,
  -- Bank
  account_holder  text,
  iban            text check (iban is null or iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
  bic             text,
  -- Notfallkontakt
  emergency_name  text,
  emergency_phone text,
  -- Einwilligungen
  privacy_ack_at       timestamptz,           -- Datenschutzhinweis bestätigt
  location_sharing     boolean not null default false,  -- Live-Standort freigegeben (freiwillig, widerrufbar)
  location_consent_at  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table public.member_profiles enable row level security;

drop policy if exists "eigenes Blatt lesen"   on public.member_profiles;
drop policy if exists "eigenes Blatt anlegen" on public.member_profiles;
drop policy if exists "eigenes Blatt ändern"  on public.member_profiles;
drop policy if exists "Admin alles"           on public.member_profiles;

create policy "eigenes Blatt lesen"   on public.member_profiles for select to authenticated using (user_id = auth.uid() and public.is_active());
create policy "eigenes Blatt anlegen" on public.member_profiles for insert to authenticated with check (user_id = auth.uid() and public.is_active());
create policy "eigenes Blatt ändern"  on public.member_profiles for update to authenticated using (user_id = auth.uid() and public.is_active()) with check (user_id = auth.uid() and public.is_active());
create policy "Admin alles"           on public.member_profiles for all    to authenticated using (public.is_admin()) with check (public.is_admin());

-- Kein Löschen für Vertreter selbst (nur Admin über die Admin-Policy)
revoke all on public.member_profiles from anon, authenticated;
grant select, insert, update, delete on public.member_profiles to authenticated;
