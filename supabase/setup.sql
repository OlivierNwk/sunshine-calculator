-- Sunshine Island Calculator – database setup
-- Run once in Supabase: SQL Editor → New query → paste → Run.

-- 1) Tables -----------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.saves (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

create table if not exists public.submissions (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('cruise','deco','building','prod','other')),
  fields jsonb not null default '{}'::jsonb,
  note text check (char_length(note) <= 1000),
  images text[] not null default '{}' check (cardinality(images) between 1 and 4),
  status text not null default 'new' check (status in ('new','accepted','rejected')),
  created_at timestamptz not null default now()
);
create index if not exists submissions_user_idx on public.submissions(user_id);
create index if not exists submissions_created_idx on public.submissions(created_at desc);

-- 2) Helper: is the current user an admin? ----------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to authenticated;

-- 3) Spam protection: max 30 reports per player per day ---------------
create or replace function public.limit_submissions() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.submissions
      where user_id = auth.uid() and created_at > now() - interval '1 day') >= 30 then
    raise exception 'Daily limit reached';
  end if;
  new.user_id := auth.uid();
  new.status := 'new';
  return new;
end $$;
drop trigger if exists submissions_limit on public.submissions;
create trigger submissions_limit before insert on public.submissions
  for each row execute function public.limit_submissions();

-- Players may only change the status through the admin policy below,
-- and nobody may change who sent a report or its content afterwards.
create or replace function public.protect_submissions() returns trigger
language plpgsql set search_path = public as $$
begin
  new.user_id := old.user_id; new.kind := old.kind; new.fields := old.fields;
  new.note := old.note; new.images := old.images; new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists submissions_protect on public.submissions;
create trigger submissions_protect before update on public.submissions
  for each row execute function public.protect_submissions();

-- 4) Row Level Security ----------------------------------------------
alter table public.profiles    enable row level security;
alter table public.saves       enable row level security;
alter table public.admins      enable row level security;
alter table public.submissions enable row level security;

-- profiles: own row; admins can read all (to show names next to reports)
drop policy if exists "profiles own" on public.profiles;
create policy "profiles own" on public.profiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists "profiles admin read" on public.profiles;
create policy "profiles admin read" on public.profiles for select to authenticated
  using (public.is_admin());

-- saves: strictly private, nobody else (not even admins) can read them
drop policy if exists "saves own" on public.saves;
create policy "saves own" on public.saves for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- admins table: no direct access from the website (managed in SQL only)

-- submissions
drop policy if exists "subs insert own" on public.submissions;
create policy "subs insert own" on public.submissions for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists "subs read own or admin" on public.submissions;
create policy "subs read own or admin" on public.submissions for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists "subs admin update" on public.submissions;
create policy "subs admin update" on public.submissions for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists "subs admin delete" on public.submissions;
create policy "subs admin delete" on public.submissions for delete to authenticated
  using (public.is_admin());

-- 5) Screenshot storage (private bucket, images only, max 3 MB) -------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('screenshots', 'screenshots', false, 3145728, array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public = false, file_size_limit = 3145728,
  allowed_mime_types = array['image/webp','image/jpeg','image/png'];

drop policy if exists "shots upload own folder" on storage.objects;
create policy "shots upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'screenshots' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "shots read own or admin" on storage.objects;
create policy "shots read own or admin" on storage.objects for select to authenticated
  using (bucket_id = 'screenshots' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
drop policy if exists "shots admin delete" on storage.objects;
create policy "shots admin delete" on storage.objects for delete to authenticated
  using (bucket_id = 'screenshots' and public.is_admin());
