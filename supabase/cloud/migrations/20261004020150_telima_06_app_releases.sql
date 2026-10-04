-- Migration appliquée sur le projet Supabase cloud : telima_06_app_releases

create table if not exists telima.app_releases (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'android' check (platform in ('android')),
  version_name text not null,
  version_code integer not null check (version_code > 0),
  apk_arm64_path text,
  apk_arm32_path text,
  apk_universal_path text,
  notes text,
  mandatory boolean not null default false,
  is_published boolean not null default true,
  created_by uuid references telima.users(id),
  created_at timestamptz not null default now(),
  unique (platform, version_code),
  check (apk_arm64_path is not null or apk_arm32_path is not null or apk_universal_path is not null)
);
create index if not exists app_releases_latest on telima.app_releases (platform, version_code desc) where is_published;

alter table telima.app_releases enable row level security;
create policy app_releases_read on telima.app_releases for select using (is_published or telima.is_admin());
create policy app_releases_admin_insert on telima.app_releases for insert with check (telima.is_admin());
create policy app_releases_admin_update on telima.app_releases for update using (telima.is_admin()) with check (telima.is_admin());
grant select on telima.app_releases to anon, authenticated;
grant insert, update on telima.app_releases to authenticated;
grant all on telima.app_releases to service_role;

create trigger trg_log_releases after insert or update on telima.app_releases
  for each row execute function telima.tg_admin_config_log();

-- Compartiment public des fichiers d'installation (lecture libre, dépôt réservé aux administrateurs)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('telima-releases', 'telima-releases', true, 52428800,
   array['application/vnd.android.package-archive', 'application/octet-stream'])
on conflict (id) do nothing;

create policy telima_releases_admin_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'telima-releases' and telima.is_admin());
create policy telima_releases_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'telima-releases' and telima.is_admin())
  with check (bucket_id = 'telima-releases' and telima.is_admin());
create policy telima_releases_read on storage.objects for select
  using (bucket_id = 'telima-releases');
