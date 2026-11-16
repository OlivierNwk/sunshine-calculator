-- Run AFTER you have signed in on the website once with your Google account.
-- Replace the e-mail address with the one you signed in with.
insert into public.admins (user_id)
select id from auth.users where email = 'YOUR-EMAIL@gmail.com'
on conflict do nothing;
