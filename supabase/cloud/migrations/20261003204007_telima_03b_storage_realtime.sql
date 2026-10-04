-- Migration appliquée sur le projet Supabase cloud : telima_03b_storage_realtime

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('telima-avatars', 'telima-avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('telima-package-photos', 'telima-package-photos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp']),
  ('telima-proofs', 'telima-proofs', false, 3145728, array['image/jpeg', 'image/png', 'image/webp']),
  ('telima-driver-documents', 'telima-driver-documents', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('telima-vehicle-photos', 'telima-vehicle-photos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy telima_storage_upload_own on storage.objects for insert to authenticated
  with check (bucket_id in ('telima-avatars', 'telima-package-photos', 'telima-proofs', 'telima-driver-documents', 'telima-vehicle-photos')
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy telima_storage_update_own on storage.objects for update to authenticated
  using (bucket_id like 'telima-%' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id like 'telima-%' and (storage.foldername(name))[1] = auth.uid()::text);

create policy telima_storage_avatars_read on storage.objects for select
  using (bucket_id = 'telima-avatars');

create policy telima_storage_private_read on storage.objects for select to authenticated using (
  bucket_id in ('telima-package-photos', 'telima-proofs', 'telima-driver-documents', 'telima-vehicle-photos')
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or telima.is_staff()
    or (bucket_id = 'telima-package-photos' and exists (
          select 1 from telima.deliveries d where d.package_photo_path = name and telima.can_access_delivery(d.id)))
    or (bucket_id = 'telima-proofs' and exists (
          select 1 from telima.deliveries d
           where (d.proof_photo_path = name or d.proof_signature_path = name) and telima.can_access_delivery(d.id)))
  )
);

alter publication supabase_realtime add table
  telima.deliveries, telima.delivery_locations, telima.messages, telima.notifications, telima.drivers;

grant all on all tables in schema telima to service_role;
grant all on all sequences in schema telima to service_role;
grant execute on all functions in schema telima to service_role;
