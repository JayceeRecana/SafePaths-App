-- Test only. The existing reusable worker key stays in Vault. Only a short-lived,
-- purpose-bound HMAC ticket enters pg_net; app roles cannot call the signer.
begin;
do $$ begin
  if exists(select 1 from cron.job where jobname='safepaths-proof-core-v1') then
    raise exception 'Inspect the existing core schedule before changing it';
  end if;
  if (select count(*) from vault.secrets where name='safepaths_proof_push_worker_v1') <> 1 then
    raise exception 'Expected dedicated test worker secret';
  end if;
end $$;
create or replace function safepaths_proof_private.enqueue_core_worker()
returns bigint language plpgsql security invoker set search_path=pg_catalog as $function$
declare
  worker_key text;
  ticket_time text := floor(extract(epoch from clock_timestamp()))::bigint::text;
  ticket_nonce text := replace(gen_random_uuid()::text,'-','');
  ticket_signature text;
begin
  select decrypted_secret into strict worker_key from vault.decrypted_secrets where name='safepaths_proof_push_worker_v1';
  ticket_signature := encode(extensions.hmac(ticket_time||'.'||ticket_nonce||'.core-maintenance',worker_key,'sha256'),'hex');
  return net.http_post(
    url:='https://bbteuzgfgnrjjrqewidc.supabase.co/functions/v1/safepaths-report-proof/core-maintenance',
    headers:=jsonb_build_object('Content-Type','application/json','x-proof-worker-time',ticket_time,
      'x-proof-worker-nonce',ticket_nonce,'x-proof-worker-signature',ticket_signature),
    body:='{}'::jsonb,timeout_milliseconds:=120000
  );
end $function$;
revoke all on function safepaths_proof_private.enqueue_core_worker() from public,anon,authenticated;
select cron.schedule('safepaths-proof-core-v1','*/4 * * * *','select safepaths_proof_private.enqueue_core_worker();');
select cron.alter_job((select jobid from cron.job where jobname='safepaths-proof-core-v1'),active:=false);
commit;
