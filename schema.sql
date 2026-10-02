-- Flowtask gemeinsame Arbeitsumgebung + Admin + gemeinsames Login-Passwort + E-Mail-Regeln
create extension if not exists pgcrypto;

create table if not exists public.flowtask_shared_state (
  id integer primary key default 1 check (id = 1),
  projects jsonb not null default '[]'::jsonb,
  tasks jsonb not null default '[]'::jsonb,
  settings jsonb not null default '{"defaultView":"board","workspaceName":"Flowtask Team","idleMinutes":10}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.flowtask_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.flowtask_workspace_config (
  id integer primary key default 1 check (id=1),
  password_hash text not null,
  idle_minutes integer not null default 10 check (idle_minutes between 1 and 1440),
  sender_name text not null default 'Flowtask',
  updated_at timestamptz not null default now()
);

create table if not exists public.flowtask_mail_rules (
  status_id text primary key,
  enabled boolean not null default false,
  recipient_source text not null default 'task' check (recipient_source in ('task','fixed')),
  fixed_email text not null default '',
  subject text not null default 'Flowtask: Status geändert',
  body text not null default 'Hallo {{recipient_name}},\n\nDer Auftrag {{title}} befindet sich jetzt in der Station {{status}}.',
  updated_at timestamptz not null default now()
);

create table if not exists public.flowtask_email_log (
  id bigint generated always as identity primary key,
  task_id text not null,
  status_id text not null,
  recipient text not null,
  sent_at timestamptz not null default now(),
  unique(task_id,status_id)
);

alter table public.flowtask_shared_state enable row level security;
alter table public.flowtask_admins enable row level security;
alter table public.flowtask_workspace_config enable row level security;
alter table public.flowtask_mail_rules enable row level security;
alter table public.flowtask_email_log enable row level security;

-- Default workspace configuration. The initial shared password is Flowtask2026! and should be changed by the admin immediately.
insert into public.flowtask_workspace_config(id,password_hash,idle_minutes,sender_name)
values(1,extensions.crypt('Flowtask2026!',extensions.gen_salt('bf')),10,'Flowtask')
on conflict(id) do nothing;

create or replace function public.is_flowtask_admin() returns boolean
language sql security definer set search_path=public as $$
  select exists(select 1 from public.flowtask_admins where user_id=auth.uid());
$$;

create or replace function public.claim_first_flowtask_admin() returns boolean
language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then return false; end if;
  if not exists(select 1 from public.flowtask_admins) then
    insert into public.flowtask_admins(user_id) values(auth.uid()) on conflict do nothing;
    return true;
  end if;
  return exists(select 1 from public.flowtask_admins where user_id=auth.uid());
end; $$;

create or replace function public.verify_flowtask_password(p_password text) returns boolean
language sql security definer set search_path=public as $$
  select exists(select 1 from public.flowtask_workspace_config where id=1 and password_hash=extensions.crypt(p_password,password_hash));
$$;

create or replace function public.set_flowtask_password(p_password text) returns boolean
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_flowtask_admin() then raise exception 'Admin erforderlich'; end if;
  if length(coalesce(p_password,'')) < 4 then raise exception 'Passwort zu kurz'; end if;
  update public.flowtask_workspace_config set password_hash=extensions.crypt(p_password,extensions.gen_salt('bf')),updated_at=now() where id=1;
  return true;
end; $$;

create or replace function public.get_flowtask_admin_settings() returns jsonb
language sql security definer set search_path=public as $$
  select jsonb_build_object('idle_minutes',idle_minutes,'sender_name',sender_name) from public.flowtask_workspace_config where id=1 and public.is_flowtask_admin();
$$;

-- Admin-only policies. Shared state remains writable by every authenticated user.
drop policy if exists flowtask_shared_select on public.flowtask_shared_state;
drop policy if exists flowtask_shared_insert on public.flowtask_shared_state;
drop policy if exists flowtask_shared_update on public.flowtask_shared_state;
create policy flowtask_shared_select on public.flowtask_shared_state for select to authenticated using(true);
create policy flowtask_shared_insert on public.flowtask_shared_state for insert to authenticated with check(true);
create policy flowtask_shared_update on public.flowtask_shared_state for update to authenticated using(true) with check(true);
grant select,insert,update on public.flowtask_shared_state to authenticated;

drop policy if exists flowtask_admin_self on public.flowtask_admins;
create policy flowtask_admin_self on public.flowtask_admins for select to authenticated using(user_id=auth.uid());

drop policy if exists flowtask_mail_admin_select on public.flowtask_mail_rules;
drop policy if exists flowtask_mail_admin_write on public.flowtask_mail_rules;
create policy flowtask_mail_admin_select on public.flowtask_mail_rules for select to authenticated using(public.is_flowtask_admin());
create policy flowtask_mail_admin_write on public.flowtask_mail_rules for all to authenticated using(public.is_flowtask_admin()) with check(public.is_flowtask_admin());
grant select,insert,update,delete on public.flowtask_mail_rules to authenticated;

-- Config is accessed through security-definer functions, not directly.
revoke all on public.flowtask_workspace_config from anon,authenticated;
revoke all on public.flowtask_email_log from anon,authenticated;
grant execute on function public.is_flowtask_admin() to authenticated;
grant execute on function public.claim_first_flowtask_admin() to authenticated;
grant execute on function public.verify_flowtask_password(text) to anon,authenticated;
grant execute on function public.set_flowtask_password(text) to authenticated;
grant execute on function public.get_flowtask_admin_settings() to authenticated;

insert into public.flowtask_mail_rules(status_id,enabled,recipient_source,subject,body)
select v.id,false,'task','Flowtask: '||v.name,
       'Hallo {{recipient_name}},'||E'\n\nDer Auftrag „{{title}}“ befindet sich jetzt in der Station „'||v.name||'“. '||E'\n\nViele Grüße'||E'\nFlowtask'
from (values
('incoming','Eingehende Aufträge'),('appointment','Termin wurde vereinbart'),('sampled','Bodenprobe entnommen'),('drying','Im Trockenschrank'),('prep','Probenaufbereitung'),('measure','Probe kann gemessen'),('feedback','Rückmeldung kann erfolgen'),('finish','Auftrag beenden'),('waiting','Kommt noch was? (Länger keine Rückmeldung)')
) v(id,name)
on conflict(status_id) do nothing;

-- Realtime
DO $$ BEGIN alter publication supabase_realtime add table public.flowtask_shared_state; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Preserve existing shared data. If the row does not exist, initialize it.
insert into public.flowtask_shared_state(id,projects,tasks,settings)
select 1,
  coalesce((select jsonb_agg(p order by p->>'name') from public.flowtask_state s, jsonb_array_elements(s.projects) p),'[]'::jsonb),
  coalesce((select jsonb_agg(t order by t->>'created') from public.flowtask_state s, jsonb_array_elements(s.tasks) t),'[]'::jsonb),
  '{"defaultView":"board","workspaceName":"Flowtask Team","idleMinutes":10}'::jsonb
where not exists(select 1 from public.flowtask_shared_state where id=1);
