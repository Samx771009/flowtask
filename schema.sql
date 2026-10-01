-- Flowtask Cloud-Datenbank für Supabase
create table if not exists public.flowtask_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  projects jsonb not null default '[]'::jsonb,
  tasks jsonb not null default '[]'::jsonb,
  settings jsonb not null default '{"defaultView":"board","workspaceName":"Mein Workspace"}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.flowtask_state enable row level security;

drop policy if exists "flowtask_select_own" on public.flowtask_state;
drop policy if exists "flowtask_insert_own" on public.flowtask_state;
drop policy if exists "flowtask_update_own" on public.flowtask_state;
drop policy if exists "flowtask_delete_own" on public.flowtask_state;

create policy "flowtask_select_own" on public.flowtask_state for select using (auth.uid() = user_id);
create policy "flowtask_insert_own" on public.flowtask_state for insert with check (auth.uid() = user_id);
create policy "flowtask_update_own" on public.flowtask_state for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "flowtask_delete_own" on public.flowtask_state for delete using (auth.uid() = user_id);

grant select, insert, update, delete on public.flowtask_state to authenticated;
