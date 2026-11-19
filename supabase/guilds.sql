-- Sunshine Island Calculator – Guilds (cruise tournament sign-up)
-- Run once in Supabase: SQL Editor → New query → paste → Run.
-- Safe to run again.

create extension if not exists pgcrypto;

-- 1) Tables -----------------------------------------------------------------
create table if not exists public.guilds (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  rules text not null default '' check (char_length(rules) <= 2000),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- invite codes: only the leader can read them
create table if not exists public.guild_codes (
  guild_id uuid primary key references public.guilds(id) on delete cascade,
  member_code text not null unique,
  co_code text not null unique
);

create table if not exists public.guild_members (
  guild_id uuid not null references public.guilds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('lead','co','mem')),
  ign text not null check (char_length(ign) between 1 and 30),
  joined_at timestamptz not null default now(),
  primary key (guild_id, user_id)
);

create table if not exists public.guild_events (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.guilds(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 80),
  archived boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists guild_events_guild_idx on public.guild_events(guild_id, created_at);

create table if not exists public.guild_tasks (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.guild_events(id) on delete cascade,
  guild_id uuid not null references public.guilds(id) on delete cascade,
  isl text not null, item text not null, tier int not null check (tier between 1 and 6),
  q text not null, p text not null, h text not null default '', hrs numeric not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists guild_tasks_event_idx on public.guild_tasks(event_id);

create table if not exists public.guild_signups (
  task_id uuid not null references public.guild_tasks(id) on delete cascade,
  guild_id uuid not null references public.guilds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (task_id, user_id)
);

-- 2) Helper: my role in a guild ------------------------------------------------
create or replace function public.g_role(gid uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.guild_members where guild_id = gid and user_id = auth.uid()
$$;

-- 3) Actions (run with checks inside) ------------------------------------------
create or replace function public.create_guild(gname text, my_ign text) returns uuid
language plpgsql security definer set search_path = public as $$
declare gid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into guilds(name, created_by) values (left(trim(gname),40), auth.uid()) returning id into gid;
  insert into guild_codes values (gid, encode(gen_random_bytes(9),'hex'), encode(gen_random_bytes(9),'hex'));
  insert into guild_members(guild_id,user_id,role,ign) values (gid, auth.uid(), 'lead', left(trim(my_ign),30));
  return gid;
end $$;

create or replace function public.join_guild(code text, my_ign text) returns uuid
language plpgsql security definer set search_path = public as $$
declare gid uuid; r text; cur text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select guild_id, case when co_code = code then 'co' else 'mem' end into gid, r
    from guild_codes where member_code = code or co_code = code;
  if gid is null then raise exception 'invalid code'; end if;
  select role into cur from guild_members where guild_id = gid and user_id = auth.uid();
  if cur is null then
    insert into guild_members(guild_id,user_id,role,ign) values (gid, auth.uid(), r, left(trim(my_ign),30));
  elsif cur = 'mem' and r = 'co' then
    update guild_members set role = 'co' where guild_id = gid and user_id = auth.uid();
  end if;
  return gid;
end $$;

create or replace function public.set_guild_ign(gid uuid, my_ign text) returns void
language sql security definer set search_path = public as $$
  update guild_members set ign = left(trim(my_ign),30)
   where guild_id = gid and user_id = auth.uid() and char_length(trim(my_ign)) > 0
$$;

create or replace function public.new_guild_codes(gid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.g_role(gid) <> 'lead' then raise exception 'not allowed'; end if;
  update guild_codes set member_code = encode(gen_random_bytes(9),'hex'), co_code = encode(gen_random_bytes(9),'hex') where guild_id = gid;
end $$;

-- 4) Row level security --------------------------------------------------------
alter table public.guilds enable row level security;
alter table public.guild_codes enable row level security;
alter table public.guild_members enable row level security;
alter table public.guild_events enable row level security;
alter table public.guild_tasks enable row level security;
alter table public.guild_signups enable row level security;

drop policy if exists "g read" on public.guilds;
create policy "g read" on public.guilds for select to authenticated using (public.g_role(id) is not null);
drop policy if exists "g edit" on public.guilds;
create policy "g edit" on public.guilds for update to authenticated
  using (public.g_role(id) in ('lead','co')) with check (public.g_role(id) in ('lead','co'));
drop policy if exists "g delete" on public.guilds;
create policy "g delete" on public.guilds for delete to authenticated using (public.g_role(id) = 'lead');

drop policy if exists "gc read" on public.guild_codes;
create policy "gc read" on public.guild_codes for select to authenticated using (public.g_role(guild_id) = 'lead');

drop policy if exists "gm read" on public.guild_members;
create policy "gm read" on public.guild_members for select to authenticated using (public.g_role(guild_id) is not null);
drop policy if exists "gm leave or remove" on public.guild_members;
create policy "gm leave or remove" on public.guild_members for delete to authenticated
  using ((user_id = auth.uid() and role <> 'lead') or (public.g_role(guild_id) = 'lead' and user_id <> auth.uid()));

drop policy if exists "ge read" on public.guild_events;
create policy "ge read" on public.guild_events for select to authenticated using (public.g_role(guild_id) is not null);
drop policy if exists "ge write" on public.guild_events;
create policy "ge write" on public.guild_events for all to authenticated
  using (public.g_role(guild_id) in ('lead','co')) with check (public.g_role(guild_id) in ('lead','co'));

drop policy if exists "gt read" on public.guild_tasks;
create policy "gt read" on public.guild_tasks for select to authenticated using (public.g_role(guild_id) is not null);
drop policy if exists "gt write" on public.guild_tasks;
create policy "gt write" on public.guild_tasks for all to authenticated
  using (public.g_role(guild_id) in ('lead','co')) with check (public.g_role(guild_id) in ('lead','co'));

drop policy if exists "gs read" on public.guild_signups;
create policy "gs read" on public.guild_signups for select to authenticated using (public.g_role(guild_id) is not null);
drop policy if exists "gs add own" on public.guild_signups;
create policy "gs add own" on public.guild_signups for insert to authenticated
  with check (user_id = auth.uid() and public.g_role(guild_id) is not null
              and exists (select 1 from public.guild_tasks t where t.id = task_id and t.guild_id = guild_signups.guild_id));
drop policy if exists "gs remove" on public.guild_signups;
create policy "gs remove" on public.guild_signups for delete to authenticated
  using (user_id = auth.uid() or public.g_role(guild_id) in ('lead','co'));

grant select, update, delete on public.guilds to authenticated;
grant select on public.guild_codes to authenticated;
grant select, delete on public.guild_members to authenticated;
grant select, insert, update, delete on public.guild_events, public.guild_tasks to authenticated;
grant select, insert, delete on public.guild_signups to authenticated;
revoke all on function public.create_guild(text,text), public.join_guild(text,text), public.set_guild_ign(uuid,text), public.new_guild_codes(uuid) from public, anon;
grant execute on function public.g_role(uuid), public.create_guild(text,text), public.join_guild(text,text), public.set_guild_ign(uuid,text), public.new_guild_codes(uuid) to authenticated;
