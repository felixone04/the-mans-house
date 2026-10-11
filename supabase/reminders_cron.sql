-- Pianifica l'invio dei promemoria WhatsApp ogni 5 minuti.
-- Da eseguire UNA VOLTA nel SQL Editor di Supabase dopo aver:
--   1. pubblicato la funzione:   supabase functions deploy send-reminders --no-verify-jwt
--   2. impostato i segreti:      supabase secrets set REMINDER_SECRET=... (vedi README)
-- Sostituisci <PROJECT_REF> e <REMINDER_SECRET> con i valori reali.

create extension if not exists pg_cron;
create extension if not exists pg_net;

select vault.create_secret('<REMINDER_SECRET>', 'reminder_secret');

select cron.schedule(
  'send-whatsapp-reminders',
  '*/5 * * * *',
  $$
  select net.http_post(
    url     := 'https://<PROJECT_REF>.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-reminder-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'reminder_secret')
    ),
    body    := '{}'::jsonb
  );
  $$
);
