-- Flowtask: gemeinsamer öffentlicher Arbeitsbereich für alle eingeloggten Benutzer.
-- Die bisherigen persönlichen Daten bleiben in flowtask_state erhalten.

create table if not exists public.flowtask_shared_state (
  id integer primary key default 1 check (id = 1),
  projects jsonb not null default '[]'::jsonb,
  tasks jsonb not null default '[]'::jsonb,
  settings jsonb not null default '{"defaultView":"board","workspaceName":"Flowtask Team"}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.flowtask_shared_state enable row level security;

drop policy if exists "flowtask_shared_select" on public.flowtask_shared_state;
drop policy if exists "flowtask_shared_insert" on public.flowtask_shared_state;
drop policy if exists "flowtask_shared_update" on public.flowtask_shared_state;

authenticated

create policy "flowtask_shared_select" on public.flowtask_shared_state
  for select to authenticated using (true);
create policy "flowtask_shared_insert" on public.flowtask_shared_state
  for insert to authenticated with check (true);
create policy "flowtask_shared_update" on public.flowtask_shared_state
  for update to authenticated using (true) with check (true);

grant select, insert, update on public.flowtask_shared_state to authenticated;

-- Falls noch kein gemeinsamer Datensatz existiert, werden vorhandene persönliche
-- Projekte/Aufgaben aus allen bisherigen Benutzerkonten einmalig zusammengeführt.
do $$
begin
  if not exists (select 1 from public.flowtask_shared_state where id = 1) then
    insert into public.flowtask_shared_state(id, projects, tasks, settings)
    select 1,
      coalesce((select jsonb_agg(p order by p->>'name')
                from public.flowtask_state s, jsonb_array_elements(s.projects) p), '[]'::jsonb),
      coalesce((select jsonb_agg(t order by t->>'created')
                from public.flowtask_state s, jsonb_array_elements(s.tasks) t), '[]'::jsonb),
      '{"defaultView":"board","workspaceName":"Flowtask Team"}'::jsonb;
  end if;
end $$;

-- Realtime für sofortige Aktualisierung bei allen geöffneten Browsern.
do $$
begin
  alter publication supabase_realtime add table public.flowtask_shared_state;
exception when duplicate_object then null;
end $$;
