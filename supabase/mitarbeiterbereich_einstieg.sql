-- P² Sales MultiTool: Mitarbeiterbereich, Checkliste "Dein Einstieg" (V2.35). Darf mehrfach ausgeführt werden.
-- Voraussetzung: public.is_admin() und public.is_active() (schema.sql).
-- Jeder aktive Zugang sieht und ändert nur seine eigenen Haken, Admins alle. Der Inhalt der Liste steht in der App.

create table if not exists public.member_checklist (
  user_id   uuid not null references auth.users(id) on delete cascade,
  item_key  text not null check (item_key ~ '^[a-z0-9_]{1,40}$'),
  done_at   timestamptz not null default now(),
  primary key (user_id, item_key)
);

alter table public.member_checklist enable row level security;

drop policy if exists "eigene Haken lesen"   on public.member_checklist;
drop policy if exists "eigene Haken setzen"  on public.member_checklist;
drop policy if exists "eigene Haken ändern"  on public.member_checklist;
drop policy if exists "eigene Haken löschen" on public.member_checklist;
drop policy if exists "Admin alles"          on public.member_checklist;

create policy "eigene Haken lesen"   on public.member_checklist for select to authenticated using (user_id = auth.uid() and public.is_active());
create policy "eigene Haken setzen"  on public.member_checklist for insert to authenticated with check (user_id = auth.uid() and public.is_active());
create policy "eigene Haken ändern"  on public.member_checklist for update to authenticated using (user_id = auth.uid() and public.is_active()) with check (user_id = auth.uid() and public.is_active());
create policy "eigene Haken löschen" on public.member_checklist for delete to authenticated using (user_id = auth.uid() and public.is_active());
create policy "Admin alles"          on public.member_checklist for all    to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on public.member_checklist from anon, authenticated;
grant select, insert, update, delete on public.member_checklist to authenticated;
