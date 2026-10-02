-- Runs the clockout-reminders Edge Function at 11:30 AM and 4:30 PM
-- Philippine time, every day: 30 minutes before each attendance session
-- ends. Paste into the Supabase SQL Editor once the function is deployed,
-- and run it. Everything here is on Supabase's free plan.

-- 1. The scheduler and the HTTP client it calls the function with.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- 2. A random secret that only the cron job and the function know, kept in
--    Vault so it isn't written into the job itself.
select vault.create_secret(
  replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  'clockout_reminder_secret'
);

-- 3. The two daily runs. pg_cron runs on UTC: 03:30 UTC is 11:30 AM and
--    08:30 UTC is 4:30 PM in the Philippines.
select cron.schedule(
  'clockout-reminders-am',
  '30 3 * * *',
  $$
  select net.http_post(
    url := 'https://hksswjhioztqsypbrkjy.supabase.co/functions/v1/clockout-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-reminder-secret', (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'clockout_reminder_secret'
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);

select cron.schedule(
  'clockout-reminders-pm',
  '30 8 * * *',
  $$
  select net.http_post(
    url := 'https://hksswjhioztqsypbrkjy.supabase.co/functions/v1/clockout-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-reminder-secret', (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'clockout_reminder_secret'
      )
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);

-- 4. Shows the secret. Copy it into Edge Functions → Secrets as
--    CLOCKOUT_REMINDER_SECRET; until then the function refuses the job.
select decrypted_secret as clockout_reminder_secret
from vault.decrypted_secrets
where name = 'clockout_reminder_secret';


-- ── Later, if needed ─────────────────────────────────────────────────
-- Recent runs, and what the function answered (newest first):
--   select * from cron.job_run_details order by start_time desc limit 10;
--   select status_code, content, created from net._http_response
--   order by created desc limit 10;
--
-- Stop the reminders:
--   select cron.unschedule('clockout-reminders-am');
--   select cron.unschedule('clockout-reminders-pm');
