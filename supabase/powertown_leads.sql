-- P² Sales MultiTool: Powertown-Leadpool (Anfragen aus Instagram/Facebook/Landingpage).
-- Darf mehrfach ausgeführt werden. Voraussetzung: public.is_admin() (schema.sql).
--
-- Grundsätze:
--  * Nur Admins (Inhaber) sehen und bearbeiten Powertown-Leads. KEIN Zugriff für Vertreter, Teamleiter oder Anonyme.
--  * Anfragen kommen ausschließlich über die Edge Function "powertown-intake" (Service-Rolle) herein.
--    Anonyme Nutzer haben keinerlei direkte Rechte auf diese Tabellen.
--  * Keine automatische Weitergabe an Handelsvertreter oder Leadverteiler. Exporte nur einzeln, manuell, protokolliert,
--    und erst nachdem "export_enabled" in powertown_settings bewusst eingeschaltet wurde (Standard: aus).
--  * Einwilligung zur Kontaktaufnahme (Pflicht) und Einwilligung in Werbung (freiwillig) werden getrennt gespeichert.
--  * Meta-Veröffentlichung: zentraler Not-Aus (publishing_enabled, Standard: aus) und Protokoll jeder externen Aktion.

-- ---------- Leads ----------
create table if not exists public.powertown_leads (
  id                   uuid primary key default gen_random_uuid(),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  request_id           uuid unique,                                  -- vom Formular erzeugt: doppelte Absendung = derselbe Datensatz
  channel              text not null default 'landingpage' check (channel in ('landingpage','instagram','instagram_dm','facebook','whatsapp','email','telefon','manuell')),
  reel_id              text,
  utm_source           text, utm_medium text, utm_campaign text, utm_content text,
  name                 text not null check (length(trim(name)) between 2 and 120),
  phone                text,
  email                text,
  zip                  text check (zip is null or zip ~ '^[0-9]{5}$'),
  product              text not null default 'beides' check (product in ('strom','gas','beides')),
  customer_type        text not null default 'privat' check (customer_type in ('privat','gewerbe')),
  contact_pref         text not null default 'telefon' check (contact_pref in ('telefon','whatsapp','email')),
  current_supplier     text,
  consumption_kwh      numeric check (consumption_kwh is null or consumption_kwh >= 0),
  message              text check (message is null or length(message) <= 1000),
  status               text not null default 'neu' check (status in ('neu','bestaetigt','kontaktieren','info_fehlt','vergleich','angebot','gewonnen','verloren','wiedervorlage')),
  next_due             date,                                          -- Rückruf / nächster Schritt fällig am
  next_action          text,
  last_contact         timestamptz,
  contact_count        integer not null default 0 check (contact_count >= 0),
  notes                text not null default '',
  -- Einwilligungen (Nachweis: Zeitpunkt, Textfassung, Quelle)
  consent_contact      boolean not null default false,                -- Rückmeldung zur eigenen Anfrage (Pflicht im Formular)
  consent_contact_at   timestamptz,
  consent_marketing    boolean not null default false,                -- spätere Werbung/Newsletter (freiwillig, Standard nein)
  consent_marketing_at timestamptz,
  consent_text_version text,
  consent_source       text,
  dedupe_key           text,                                          -- normalisierte Telefonnummer bzw. E-Mail
  delete_after         date,                                          -- Löschfrist
  constraint powertown_contact_way check (phone is not null or email is not null)
);
create index if not exists powertown_leads_status  on public.powertown_leads (status);
create index if not exists powertown_leads_due     on public.powertown_leads (next_due) where next_due is not null;
create index if not exists powertown_leads_dedupe  on public.powertown_leads (dedupe_key);
create index if not exists powertown_leads_created on public.powertown_leads (created_at desc);

-- ---------- Verlauf (Eingang, Statuswechsel, Kontaktversuche, Notizen, Exporte) ----------
create table if not exists public.powertown_lead_events (
  id         uuid primary key default gen_random_uuid(),
  lead_id    uuid not null references public.powertown_leads(id) on delete cascade,
  created_at timestamptz not null default now(),
  kind       text not null check (kind in ('eingang','erneute_anfrage','status','kontakt','notiz','export')),
  channel    text,                                                    -- z. B. telefon, whatsapp, email, instagram_dm
  status     text,
  note       text check (note is null or length(note) <= 2000),
  created_by uuid default auth.uid()
);
create index if not exists powertown_events_lead on public.powertown_lead_events (lead_id, created_at desc);

-- ---------- Exportprotokoll (Weitergabe an einen freigegebenen Leadverteiler, nur manuell) ----------
create table if not exists public.powertown_exports (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  lead_id     uuid references public.powertown_leads(id) on delete set null,
  recipient   text not null check (length(trim(recipient)) > 0),
  purpose     text not null check (length(trim(purpose)) > 0),
  legal_basis text not null check (length(trim(legal_basis)) > 0),
  fields      text[] not null default '{}',
  created_by  uuid default auth.uid()
);

-- ---------- Einstellungen (eine Zeile) ----------
create table if not exists public.powertown_settings (
  id                  integer primary key default 1 check (id = 1),
  export_enabled      boolean not null default false,  -- Leadverteiler-Export: erst nach Prüfung von Empfänger und Rechtsgrundlage einschalten
  publishing_enabled  boolean not null default false,  -- NOT-AUS für jede Meta-Veröffentlichung. Aus = nichts wird gepostet.
  publishing_note     text,                            -- Grund für Stopp, z. B. Warnung von Meta
  retention_days      integer not null default 365 check (retention_days between 30 and 3650),
  updated_at          timestamptz not null default now()
);
insert into public.powertown_settings (id) values (1) on conflict (id) do nothing;

-- ---------- Protokoll externer Aktionen (Veröffentlichungen, API-Aufrufe) ----------
create table if not exists public.powertown_action_log (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  kind       text not null,                            -- z. B. publish_reel, read_test, publish_blocked
  account    text,                                     -- betroffenes Konto
  target     text,                                     -- Datei / Medien-ID / URL
  status     text not null check (status in ('ok','fehler','blockiert')),
  detail     text,
  created_by uuid default auth.uid()
);
create index if not exists powertown_action_log_created on public.powertown_action_log (created_at desc);

-- ---------- Einfache Ratenbegrenzung für den Formular-Eingang (nur Hash, keine IP im Klartext) ----------
create table if not exists public.powertown_intake_hits (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  ip_hash    text not null
);
create index if not exists powertown_hits_ip on public.powertown_intake_hits (ip_hash, created_at desc);

-- ---------- Zugriffsregeln: nur Admin ----------
alter table public.powertown_leads        enable row level security;
alter table public.powertown_lead_events  enable row level security;
alter table public.powertown_exports      enable row level security;
alter table public.powertown_settings     enable row level security;
alter table public.powertown_action_log   enable row level security;
alter table public.powertown_intake_hits  enable row level security;   -- keine Policy: nur Service-Rolle

drop policy if exists "Admin alles" on public.powertown_leads;
drop policy if exists "Admin alles" on public.powertown_lead_events;
drop policy if exists "Admin lesen" on public.powertown_exports;
drop policy if exists "Admin anlegen wenn freigegeben" on public.powertown_exports;
drop policy if exists "Admin alles" on public.powertown_settings;
drop policy if exists "Admin lesen" on public.powertown_action_log;
create policy "Admin alles" on public.powertown_leads       for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin alles" on public.powertown_lead_events for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin alles" on public.powertown_settings    for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin lesen" on public.powertown_action_log  for select to authenticated using (public.is_admin());
create policy "Admin lesen" on public.powertown_exports     for select to authenticated using (public.is_admin());
-- Export nur, wenn er in den Einstellungen bewusst freigeschaltet ist (serverseitig erzwungen, nicht nur in der Oberfläche)
create policy "Admin anlegen wenn freigegeben" on public.powertown_exports for insert to authenticated
  with check (public.is_admin() and exists (select 1 from public.powertown_settings s where s.id = 1 and s.export_enabled));

revoke all on public.powertown_leads, public.powertown_lead_events, public.powertown_exports,
              public.powertown_settings, public.powertown_action_log, public.powertown_intake_hits from anon, authenticated;
grant select, insert, update, delete on public.powertown_leads, public.powertown_lead_events to authenticated;
grant select, update on public.powertown_settings to authenticated;
grant select, insert on public.powertown_exports to authenticated;
grant select on public.powertown_action_log to authenticated;
-- Exportprotokoll und Aktionsprotokoll sind unveränderlich: kein update/delete für angemeldete Nutzer.

-- ---------- Löschfrist ----------
-- Setzt delete_after beim Anlegen (falls leer) und löscht abgelaufene, abgeschlossene Leads.
create or replace function public.powertown_set_delete_after() returns trigger language plpgsql as $$
begin
  if new.delete_after is null then
    new.delete_after := (now() + make_interval(days => coalesce((select retention_days from public.powertown_settings where id = 1), 365)))::date;
  end if;
  return new;
end $$;
drop trigger if exists powertown_leads_delete_after on public.powertown_leads;
create trigger powertown_leads_delete_after before insert on public.powertown_leads for each row execute function public.powertown_set_delete_after();

create or replace function public.powertown_purge() returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.is_admin() and current_user not in ('postgres','service_role') then raise exception 'nur Admin'; end if;
  delete from public.powertown_leads where delete_after < current_date and status in ('gewonnen','verloren','neu','bestaetigt','info_fehlt');
  get diagnostics n = row_count;
  delete from public.powertown_intake_hits where created_at < now() - interval '2 days';
  return n;
end $$;
revoke all on function public.powertown_purge() from public, anon;
grant execute on function public.powertown_purge() to authenticated;
-- Optional automatisch (wenn pg_cron aktiv ist): select cron.schedule('powertown-purge', '15 3 * * *', 'select public.powertown_purge()');
