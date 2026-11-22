-- Sunshine Island Calculator – Admin overview of all guilds
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to run again.
-- Only admins (table "admins") can use these functions.

create or replace function public.admin_guilds()
returns table (id uuid, name text, created_at timestamptz, members int, leader text, tasks int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  return query
    select g.id, g.name, g.created_at,
           (select count(*)::int from guild_members m where m.guild_id = g.id),
           (select m.ign from guild_members m where m.guild_id = g.id and m.role = 'lead' limit 1),
           (select count(*)::int from guild_tasks t where t.guild_id = g.id)
      from guilds g order by g.created_at desc;
end $$;

create or replace function public.admin_delete_guild(gid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  delete from guilds where id = gid;
end $$;

revoke all on function public.admin_guilds(), public.admin_delete_guild(uuid) from public, anon;
grant execute on function public.admin_guilds(), public.admin_delete_guild(uuid) to authenticated;
