-- MAIN RESOURCE. Apply only as part of the coordinated Marulas rollout.
-- A new private bucket; existing report-images and its policies are untouched.
-- The Edge function writes with its managed server credential. No anonymous or
-- authenticated client Storage policy is added for this bucket.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-photos-marulas', 'report-photos-marulas', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

-- Restrictive policies are ANDed with existing permissive policies. An older
-- public policy therefore cannot grant direct access to this proof bucket.
-- The server service_role bypasses RLS; other buckets retain their own policy.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage'
    and tablename = 'objects' and policyname = 'safepaths_marulas_server_only') then
    create policy safepaths_marulas_server_only on storage.objects
      as restrictive for all to anon, authenticated
      using (bucket_id <> 'report-photos-marulas')
      with check (bucket_id <> 'report-photos-marulas');
  end if;
end $$;

-- Still verify denied anonymous/client access against the hosted project before
-- considering this proof accepted; local Storage fixtures do not execute RLS.
