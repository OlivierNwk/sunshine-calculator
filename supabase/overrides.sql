-- Sunshine Island Calculator – accepted data ("Übernehmen")
-- Run once in Supabase: SQL Editor → New query → paste → Run.
-- Safe to run again.

-- 1) Translation reports may come without a screenshot
alter table public.submissions drop constraint if exists submissions_images_check;
alter table public.submissions add constraint submissions_images_check
  check (cardinality(images) between 0 and 4);

-- 2) Data accepted by an admin; everybody's calculator reads it
create table if not exists public.overrides (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('cruise','deco','building','trans')),
  data jsonb not null,
  submission_id bigint references public.submissions(id) on delete set null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists overrides_created_idx on public.overrides(created_at);

alter table public.overrides enable row level security;

drop policy if exists "overrides read" on public.overrides;
create policy "overrides read" on public.overrides for select
  to anon, authenticated using (true);

drop policy if exists "overrides admin insert" on public.overrides;
create policy "overrides admin insert" on public.overrides for insert
  to authenticated with check (public.is_admin());

drop policy if exists "overrides admin update" on public.overrides;
create policy "overrides admin update" on public.overrides for update
  to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "overrides admin delete" on public.overrides;
create policy "overrides admin delete" on public.overrides for delete
  to authenticated using (public.is_admin());

grant select on public.overrides to anon, authenticated;
grant insert, update, delete on public.overrides to authenticated;
