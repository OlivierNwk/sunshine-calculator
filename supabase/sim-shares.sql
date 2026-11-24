-- Sunshine Island Tools – short links for shared islands (#s=abc1234)
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to run again.
-- Only signed-in players can create short links; anyone with the link can open it.
-- The table itself is not readable directly, so nobody can list all shared islands.

create table if not exists public.sim_shares (
  id text primary key,
  data jsonb not null,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists sim_shares_by_user on public.sim_shares (created_by, created_at);
alter table public.sim_shares enable row level security;
-- no policies: direct access is blocked, only the two functions below work

create or replace function public.create_sim_share(d jsonb) returns text
language plpgsql volatile security definer set search_path = public as $$
declare uid uuid := auth.uid(); nid text; existing text; i int := 0;
  chars text := 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  if uid is null then raise exception 'sign in first'; end if;
  if pg_column_size(d) > 60000 then raise exception 'too large'; end if;
  -- same island shared again by the same player → same link
  select id into existing from sim_shares where created_by = uid and data = d limit 1;
  if existing is not null then return existing; end if;
  if (select count(*) from sim_shares where created_by = uid and created_at > now() - interval '1 day') >= 100 then
    raise exception 'too many links today';
  end if;
  loop
    nid := '';
    for k in 1..7 loop nid := nid || substr(chars, 1 + floor(random() * length(chars))::int, 1); end loop;
    begin
      insert into sim_shares (id, data, created_by) values (nid, d, uid);
      return nid;
    exception when unique_violation then
      i := i + 1; if i > 5 then raise; end if;
    end;
  end loop;
end $$;

create or replace function public.get_sim_share(sid text) returns jsonb
language sql stable security definer set search_path = public as $$
  select data from sim_shares where id = sid;
$$;

revoke all on function public.create_sim_share(jsonb), public.get_sim_share(text) from public;
grant execute on function public.create_sim_share(jsonb) to authenticated;
grant execute on function public.get_sim_share(text) to anon, authenticated;
