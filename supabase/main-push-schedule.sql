-- Main rollout only; initially disabled. schedule. First place the dedicated worker key in Vault under
-- safepaths_marulas_worker_v1, matching MARULAS_WORKER_SECRET.
-- Never put the key itself in this file or in cron.job.command.
begin;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
do $$
begin
  if (select count(*) from vault.secrets where name='safepaths_marulas_worker_v1') <> 1 then
    raise exception 'Configure exactly one dedicated main worker secret first';
  end if;
  if exists(select 1 from cron.job where jobname='safepaths-main-push-v1') then
    raise exception 'Test worker already exists; inspect it before changing its schedule';
  end if;
end $$;
-- Managed pg_net grants can make queued headers readable to database roles.
-- Compute one-use HMAC tickets in a private, invoker-only function; the reusable
-- key never enters the queue. The Edge worker rejects expired/replayed tickets.
create schema if not exists safepaths_marulas_private;
revoke all on schema safepaths_marulas_private from public, anon, authenticated;
create or replace function safepaths_marulas_private.enqueue_push_worker()
returns bigint language plpgsql security invoker set search_path=pg_catalog as $function$
declare
  worker_key text;
  ticket_time text := floor(extract(epoch from clock_timestamp()))::bigint::text;
  ticket_nonce text := replace(gen_random_uuid()::text,'-','');
  ticket_signature text;
begin
  select decrypted_secret into strict worker_key from vault.decrypted_secrets where name='safepaths_marulas_worker_v1';
  ticket_signature := encode(extensions.hmac(ticket_time||'.'||ticket_nonce,worker_key,'sha256'),'hex');
  return net.http_post(
    url:='https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-main/push-drain',
    headers:=jsonb_build_object('Content-Type','application/json','x-proof-worker-time',ticket_time,
      'x-proof-worker-nonce',ticket_nonce,'x-proof-worker-signature',ticket_signature),
    body:='{}'::jsonb,timeout_milliseconds:=120000
  );
end $function$;
revoke all on function safepaths_marulas_private.enqueue_push_worker() from public, anon, authenticated;
select cron.schedule('safepaths-main-push-v1','*/5 * * * *','select safepaths_marulas_private.enqueue_push_worker();');
-- Activate only after the pending-job index and hosted checks have passed.
select cron.alter_job((select jobid from cron.job where jobname='safepaths-main-push-v1'),active:=false);
commit;
