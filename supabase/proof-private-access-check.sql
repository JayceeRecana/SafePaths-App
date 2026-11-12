-- Synthetic proof bucket only. All attempted writes are rolled back.
begin;
do $$ begin
  if not exists(select 1 from storage.objects where bucket_id='report-photos-proof') then
    raise exception 'A real synthetic proof object is required before testing RLS';
  end if;
end $$;
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}';
do $$
declare affected integer; insert_blocked boolean := false;
begin
  if exists(select 1 from storage.objects where bucket_id='report-photos-proof') then
    raise exception 'Authenticated client can read proof object metadata';
  end if;
  update storage.objects set metadata=metadata where bucket_id='report-photos-proof';
  get diagnostics affected = row_count;
  if affected<>0 then raise exception 'Authenticated client can update proof metadata'; end if;
  begin
    delete from storage.objects where bucket_id='report-photos-proof';
    get diagnostics affected = row_count;
    if affected<>0 then raise exception 'Authenticated client can delete proof objects'; end if;
  exception when insufficient_privilege then
    -- Hosted Storage also blocks direct SQL deletion with its own guard trigger.
    null;
  end;
  begin
    insert into storage.objects(bucket_id,name) values('report-photos-proof','reports/spark-proof-other/rls-insert-check');
  exception when insufficient_privilege then
    insert_blocked := true;
  end;
  if not insert_blocked then raise exception 'Authenticated client can insert proof metadata'; end if;
end $$;
reset role;
select json_build_object('authenticated_storage_rls_passed',true,'writes_rolled_back',true) as proof_rls;
rollback;
