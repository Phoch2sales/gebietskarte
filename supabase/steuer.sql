-- P² Sales MultiTool: Admin-Bereich „Steuer“ (V2.36). Darf mehrfach ausgeführt werden.
-- Voraussetzung: public.is_admin() existiert (schema.sql) und supabase/personal.sql ist eingerichtet.
-- Vorsystem für den Steuerberater: Provisionsgutschriften, Belege, Monatszahlen, Export.
-- Nur Admins dürfen lesen und schreiben. Vertreter sehen nichts.
--
-- Unveränderbarkeit: Gutschriften sind ab Ausstellung festgeschrieben (nur Storno und Zahldatum
-- lassen sich noch setzen). Belege lassen sich festschreiben und danach nicht mehr ändern oder löschen.
-- Jede Änderung wird in tx_log protokolliert.

-- 1) Einstellungen (genau eine Zeile; Firmendaten, Kontenrahmen, DATEV-Nummern)
create table if not exists public.tx_settings (
  id   integer primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb
);
insert into public.tx_settings (id, data) values (1, '{}'::jsonb) on conflict (id) do nothing;

-- 2) Nummernkreise (lückenlos je Art und Jahr)
create table if not exists public.tx_counters (
  kind text not null,
  year integer not null,
  last integer not null default 0,
  primary key (kind, year)
);

-- 3) Provisionsgutschriften an Vertreter
create table if not exists public.tx_credit_notes (
  id            uuid primary key default gen_random_uuid(),
  number        text not null unique,
  employee_id   uuid not null references public.hr_employees(id) on delete restrict,
  month         date not null check (extract(day from month) = 1),
  issue_date    date not null default current_date,
  net           numeric(12,2) not null check (net >= 0),
  vat_rate      numeric(5,2)  not null check (vat_rate >= 0),
  vat           numeric(12,2) not null check (vat >= 0),
  gross         numeric(12,2) not null check (gross >= 0),
  carry_out     numeric(12,2) not null default 0 check (carry_out >= 0),
  snapshot      jsonb not null,          -- Aussteller, Empfänger, Positionen: so wie ausgestellt
  paid_at       date,
  cancelled_at  timestamptz,
  cancel_reason text,
  created_by    uuid default auth.uid(),
  created_at    timestamptz not null default now()
);
-- Je Vertreter und Monat höchstens eine gültige (nicht stornierte) Gutschrift
create unique index if not exists tx_credit_notes_one_valid on public.tx_credit_notes (employee_id, month) where cancelled_at is null;

-- 4) Belege (Eingangs- und Ausgangsrechnungen, erhaltene Provisionsabrechnungen)
create table if not exists public.tx_documents (
  id          uuid primary key default gen_random_uuid(),
  direction   text not null check (direction in ('ein','aus')),   -- ein = Ausgabe (Eingangsrechnung), aus = Einnahme
  doc_date    date not null,
  partner     text not null check (length(trim(partner)) > 0),
  doc_number  text not null default '',
  description text not null default '',
  category    text not null default 'sonstiges',
  account     text not null default '',                           -- Sachkonto (Vorschlag, vom Steuerberater zu prüfen)
  vat_case    text not null default 'normal' check (vat_case in ('normal','13b_eu','13b_sonst','frei','ku')),
  net         numeric(12,2) not null,
  vat_rate    numeric(5,2)  not null default 19 check (vat_rate >= 0),
  vat         numeric(12,2) not null default 0,
  gross       numeric(12,2) not null,
  paid_at     date,
  file_path   text,                                               -- Datei im Speicher-Bucket „belege“
  file_name   text,
  locked      boolean not null default false,
  locked_at   timestamptz,
  created_by  uuid default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists tx_documents_date on public.tx_documents (doc_date);

-- 5) Änderungsprotokoll
create table if not exists public.tx_log (
  id       bigint generated always as identity primary key,
  at       timestamptz not null default now(),
  user_id  uuid default auth.uid(),
  tbl      text not null,
  action   text not null,
  row_id   text,
  old_data jsonb,
  new_data jsonb
);

create or replace function public.tx_log_change() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.tx_log (tbl, action, row_id, old_data, new_data)
  values (tg_table_name, tg_op,
          case when tg_op = 'DELETE' then old.id::text else new.id::text end,
          case when tg_op = 'INSERT' then null else to_jsonb(old) end,
          case when tg_op = 'DELETE' then null else to_jsonb(new) end);
  return coalesce(new, old);
end $$;

drop trigger if exists tx_log_credit_notes on public.tx_credit_notes;
drop trigger if exists tx_log_documents    on public.tx_documents;
drop trigger if exists tx_log_settings     on public.tx_settings;
create trigger tx_log_credit_notes after insert or update or delete on public.tx_credit_notes for each row execute function public.tx_log_change();
create trigger tx_log_documents    after insert or update or delete on public.tx_documents    for each row execute function public.tx_log_change();
create trigger tx_log_settings     after insert or update or delete on public.tx_settings     for each row execute function public.tx_log_change();

-- 6) Festschreibung
create or replace function public.tx_guard_credit_note() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Gutschriften können nicht gelöscht werden. Bitte stornieren.'; end if;
  if old.cancelled_at is not null and new.cancelled_at is distinct from old.cancelled_at then raise exception 'Ein Storno kann nicht zurückgenommen werden.'; end if;
  if (to_jsonb(new) - 'paid_at' - 'cancelled_at' - 'cancel_reason') is distinct from (to_jsonb(old) - 'paid_at' - 'cancelled_at' - 'cancel_reason') then
    raise exception 'Gutschriften sind festgeschrieben. Nur Zahldatum und Storno lassen sich setzen.';
  end if;
  return new;
end $$;
drop trigger if exists tx_guard_credit_note on public.tx_credit_notes;
create trigger tx_guard_credit_note before update or delete on public.tx_credit_notes for each row execute function public.tx_guard_credit_note();

create or replace function public.tx_guard_document() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.locked then raise exception 'Festgeschriebene Belege können nicht gelöscht werden.'; end if;
    return old;
  end if;
  if old.locked then
    if (to_jsonb(new) - 'paid_at' - 'updated_at') is distinct from (to_jsonb(old) - 'paid_at' - 'updated_at') then
      raise exception 'Der Beleg ist festgeschrieben. Nur das Zahldatum lässt sich noch setzen.';
    end if;
  elsif new.locked then
    new.locked_at := now();
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists tx_guard_document on public.tx_documents;
create trigger tx_guard_document before update or delete on public.tx_documents for each row execute function public.tx_guard_document();

-- 7) Gutschrift ausstellen: vergibt die nächste Nummer und legt die Gutschrift in einem Schritt an
create or replace function public.tx_issue_credit_note(p_employee uuid, p_month date, p_issue_date date, p_net numeric, p_vat_rate numeric, p_carry_out numeric, p_snapshot jsonb)
returns public.tx_credit_notes language plpgsql security definer set search_path = public as $$
declare
  y integer := extract(year from p_issue_date);
  n integer;
  v numeric(12,2) := round(p_net * p_vat_rate / 100, 2);
  r public.tx_credit_notes;
begin
  if not public.is_admin() then raise exception 'Nur für Admins.'; end if;
  if exists (select 1 from public.tx_credit_notes where employee_id = p_employee and month = p_month and cancelled_at is null) then
    raise exception 'Für diesen Vertreter und Monat gibt es schon eine gültige Gutschrift.';
  end if;
  insert into public.tx_counters (kind, year, last) values ('GS', y, 1)
    on conflict (kind, year) do update set last = public.tx_counters.last + 1
    returning last into n;
  insert into public.tx_credit_notes (number, employee_id, month, issue_date, net, vat_rate, vat, gross, carry_out, snapshot)
  values ('GS-' || y || '-' || lpad(n::text, 4, '0'), p_employee, p_month, p_issue_date, round(p_net, 2), p_vat_rate, v, round(p_net, 2) + v, coalesce(p_carry_out, 0), p_snapshot)
  returning * into r;
  return r;
end $$;
revoke all on function public.tx_issue_credit_note(uuid, date, date, numeric, numeric, numeric, jsonb) from public, anon;
grant execute on function public.tx_issue_credit_note(uuid, date, date, numeric, numeric, numeric, jsonb) to authenticated;

-- 8) Row Level Security: nur Admin
alter table public.tx_settings     enable row level security;
alter table public.tx_counters     enable row level security;
alter table public.tx_credit_notes enable row level security;
alter table public.tx_documents    enable row level security;
alter table public.tx_log          enable row level security;

drop policy if exists "Admin alles" on public.tx_settings;
drop policy if exists "Admin alles" on public.tx_credit_notes;
drop policy if exists "Admin alles" on public.tx_documents;
drop policy if exists "Admin lesen" on public.tx_log;
create policy "Admin alles" on public.tx_settings     for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin alles" on public.tx_credit_notes for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin alles" on public.tx_documents    for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Admin lesen" on public.tx_log          for select to authenticated using (public.is_admin());

revoke all on public.tx_settings, public.tx_counters, public.tx_credit_notes, public.tx_documents, public.tx_log from anon, authenticated;
grant select, insert, update on public.tx_settings to authenticated;
grant select, update on public.tx_credit_notes to authenticated;          -- anlegen nur über tx_issue_credit_note
grant select, insert, update, delete on public.tx_documents to authenticated;
grant select on public.tx_log to authenticated;                           -- tx_counters: kein direkter Zugriff

-- 9) Speicher für Belegdateien (privat, nur Admin)
insert into storage.buckets (id, name, public) values ('belege', 'belege', false) on conflict (id) do nothing;
drop policy if exists "belege Admin lesen"     on storage.objects;
drop policy if exists "belege Admin hochladen" on storage.objects;
drop policy if exists "belege Admin löschen"   on storage.objects;
create policy "belege Admin lesen"     on storage.objects for select to authenticated using (bucket_id = 'belege' and public.is_admin());
create policy "belege Admin hochladen" on storage.objects for insert to authenticated with check (bucket_id = 'belege' and public.is_admin());
create policy "belege Admin löschen"   on storage.objects for delete to authenticated using (bucket_id = 'belege' and public.is_admin());
