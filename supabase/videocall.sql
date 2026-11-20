-- P² Sales MultiTool: Videocall (V2.45). Darf mehrfach ausgeführt werden.
-- Voraussetzung: public.is_admin() und public.profiles (id, role, active) aus schema.sql.
-- Regel, von der Datenbank erzwungen (nicht nur von der App):
--   Admin und Teamleiter dürfen jeden aktiven Zugang anrufen.
--   Alle anderen (Handelsvertreter) dürfen nur Admins und Teamleiter anrufen, nie einander.
-- Bild und Ton laufen direkt zwischen den beiden Geräten (WebRTC). Hier liegen nur die kurzen Verbindungsnachrichten.

-- 1) Teamleiter: kann nur der Admin vergeben, lesen darf jeder angemeldete Zugang (damit Vertreter wissen, wen sie anrufen dürfen).
create table if not exists public.team_leads (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.team_leads enable row level security;
drop policy if exists "Alle lesen" on public.team_leads;
drop policy if exists "Admin schreibt" on public.team_leads;
create policy "Alle lesen"     on public.team_leads for select to authenticated using (true);
create policy "Admin schreibt" on public.team_leads for all    to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.team_leads from anon, authenticated;
grant select, insert, delete on public.team_leads to authenticated;

-- 2) Wer darf wen anrufen?
create or replace function public.can_call(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a <> b
    and exists (select 1 from public.profiles p where p.id = a and p.active)
    and exists (select 1 from public.profiles p where p.id = b and p.active)
    and (
      exists (select 1 from public.profiles p where p.id = a and p.role = 'admin')
      or exists (select 1 from public.team_leads t where t.user_id = a)
      or exists (select 1 from public.profiles p where p.id = b and p.role = 'admin')
      or exists (select 1 from public.team_leads t where t.user_id = b)
    );
$$;
revoke all on function public.can_call(uuid, uuid) from public, anon;
grant execute on function public.can_call(uuid, uuid) to authenticated;

-- 3) Verbindungsnachrichten (Einladung, Annehmen, Angebot/Antwort, Netzwerkwege, Auflegen)
create table if not exists public.call_signals (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  call_id    uuid not null,
  from_user  uuid not null references auth.users(id) on delete cascade,
  to_user    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('invite','accept','offer','answer','ice','hangup','decline','busy')),
  payload    jsonb check (payload is null or length(payload::text) < 30000)
);
create index if not exists call_signals_to on public.call_signals (to_user, created_at);
alter table public.call_signals enable row level security;
drop policy if exists "Senden nur erlaubt" on public.call_signals;
drop policy if exists "Eigene lesen"       on public.call_signals;
drop policy if exists "Eigene loeschen"    on public.call_signals;
create policy "Senden nur erlaubt" on public.call_signals for insert to authenticated with check (from_user = auth.uid() and public.can_call(from_user, to_user));
create policy "Eigene lesen"       on public.call_signals for select to authenticated using (to_user = auth.uid() or from_user = auth.uid());
create policy "Eigene loeschen"    on public.call_signals for delete to authenticated using (to_user = auth.uid() or from_user = auth.uid());
revoke all on public.call_signals from anon, authenticated;
grant select, insert, delete on public.call_signals to authenticated;

-- Alte Nachrichten räumen sich bei jedem neuen Anruf selbst auf
create or replace function public.call_signals_cleanup() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.call_signals where created_at < now() - interval '1 hour';
  return null;
end $$;
drop trigger if exists call_signals_cleanup on public.call_signals;
create trigger call_signals_cleanup after insert on public.call_signals for each statement execute function public.call_signals_cleanup();

-- Live-Zustellung an den Angerufenen (Realtime)
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_signals') then
    alter publication supabase_realtime add table public.call_signals;
  end if;
end $$;
