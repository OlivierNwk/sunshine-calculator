-- Sunshine Island Calculator – Discord message for every new report
-- 1) In Discord: channel settings → Integrations → Webhooks → New Webhook → Copy Webhook URL
-- 2) Paste that URL below instead of PASTE-DISCORD-WEBHOOK-URL-HERE (keep the quotes)
-- 3) Supabase: SQL Editor → New query → paste everything → Run
-- The URL stays in your database only. Never share it.

create extension if not exists pg_net;

-- private settings table: RLS on and no policies = nobody can read it from the website
create table if not exists public.private_settings (
  key text primary key,
  value text not null
);
alter table public.private_settings enable row level security;
revoke all on public.private_settings from anon, authenticated;

insert into public.private_settings (key, value)
values ('discord_webhook', 'PASTE-DISCORD-WEBHOOK-URL-HERE')
on conflict (key) do update set value = excluded.value;

create or replace function public.notify_discord() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  hook text;
  who text;
  what text;
  label text;
  island text;
begin
  select value into hook from public.private_settings where key = 'discord_webhook';
  if hook is null or hook not like 'https://%discord%/api/webhooks/%' then
    return new;
  end if;

  select coalesce(nullif(display_name, ''), 'A player') into who
    from public.profiles where id = new.user_id;

  label := case
    when new.kind = 'other' and new.fields->>'sub' = 'trans' then 'Übersetzung'
    when new.kind = 'cruise' then 'Kreuzfahrt-Aufgabe'
    when new.kind = 'deco' then 'Deko'
    when new.kind = 'building' then 'Gebäude'
    when new.kind = 'prod' then 'Produktion'
    else 'Andere' end;
  what := coalesce(new.fields->>'item', new.fields->>'bld', '?');
  island := coalesce(' (' || (new.fields->>'isl') || ')', '');

  perform net.http_post(
    url := hook,
    body := jsonb_build_object(
      'username', 'Sunshine Island Rechner',
      'content', left(
        '📩 Neue Meldung: **' || label || '** – ' || what || island ||
        E'\nvon ' || coalesce(who, 'A player') ||
        case when cardinality(new.images) > 0 then ' · 📷 ' || cardinality(new.images) else '' end ||
        E'\n<https://sunshineisland-tools.com/>', 1900),
      'allowed_mentions', jsonb_build_object('parse', jsonb_build_array())
    ),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
  return new;
exception when others then
  return new; -- a Discord problem must never block a report
end $$;

drop trigger if exists submissions_discord on public.submissions;
create trigger submissions_discord after insert on public.submissions
  for each row execute function public.notify_discord();
