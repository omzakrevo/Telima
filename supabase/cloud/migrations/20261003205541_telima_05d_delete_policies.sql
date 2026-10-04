-- Migration appliquée sur le projet Supabase cloud : telima_05d_delete_policies

create policy business_members_delete on telima.business_members for delete
  using (role <> 'owner' and (telima.is_business_member(business_id, array['owner','manager']::telima.member_role[]) or user_id = auth.uid()));
create policy notifications_delete on telima.notifications for delete using (user_id = auth.uid());
create policy telima_storage_delete_own on storage.objects for delete to authenticated
  using (bucket_id like 'telima-%' and (storage.foldername(name))[1] = auth.uid()::text);
create trigger trg_ratings_refresh_del after delete on telima.ratings
  for each row execute function telima.tg_ratings_refresh_driver();
