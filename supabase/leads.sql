-- P² Sales MultiTool: Leads (Telefon-CRM) nur für Admins. Darf mehrfach ausgeführt werden.
-- Voraussetzung: public.is_admin() (schema.sql).
-- Enthält Firmen- und Personendaten (Ansprechpartner, Telefon, E-Mail): kein Zugriff für Vertreter oder Anonyme.

create table if not exists public.leads (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  source          text not null default '',                 -- Name der Liste, z. B. "Liste 3 SLP-Betriebe"
  company         text not null check (length(trim(company)) > 0),
  contact_name    text,
  contact_role    text,
  phone           text,
  email           text,
  street          text,
  zip             text,
  city            text,
  industry        text,
  size            text,
  revenue         text,
  website         text,
  linkedin        text,
  region          text not null default '',                 -- Ja / Grenzfall / Nein / Unklar (aus der Liste)
  fit             text not null default 'passt' check (fit in ('passt','ungeeignet')),
  status          text not null default 'neu' check (status in ('neu','nicht_erreicht','rueckruf','interesse','termin','angebot','abschluss','kein_interesse','falsche_nummer')),
  next_call       date,                                     -- Wiedervorlage
  last_call       timestamptz,
  call_count      integer not null default 0 check (call_count >= 0),
  consumption_kwh numeric check (consumption_kwh is null or consumption_kwh >= 0),
  meter_type      text check (meter_type is null or meter_type in ('slp','rlm')),
  supplier        text,
  contract_end    date,
  notes           text not null default ''
);
create index if not exists leads_status    on public.leads (status);
create index if not exists leads_next_call on public.leads (next_call) where next_call is not null;
create index if not exists leads_source    on public.leads (source);

create table if not exists public.lead_calls (
  id         uuid primary key default gen_random_uuid(),
  lead_id    uuid not null references public.leads(id) on delete cascade,
  created_at timestamptz not null default now(),
  result     text not null check (result in ('neu','nicht_erreicht','rueckruf','interesse','termin','angebot','abschluss','kein_interesse','falsche_nummer')),
  note       text,
  next_call  date
);
create index if not exists lead_calls_lead    on public.lead_calls (lead_id, created_at desc);
create index if not exists lead_calls_created on public.lead_calls (created_at desc);

alter table public.leads      enable row level security;
alter table public.lead_calls enable row level security;

drop policy if exists "Admin alles" on public.leads;
drop policy if exists "Admin alles" on public.lead_calls;
create policy "Admin alles" on public.leads      for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin alles" on public.lead_calls for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on public.leads, public.lead_calls from anon, authenticated;
grant select, insert, update, delete on public.leads, public.lead_calls to authenticated;
