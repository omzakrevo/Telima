-- Migration appliquée sur le projet Supabase cloud : telima_07d_push_admin

create or replace function telima.admin_push_status()
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
begin
  if not telima.is_staff() then raise exception 'Réservé au personnel'; end if;
  return jsonb_build_object(
    'client_configured', exists (select 1 from telima.app_settings where key = 'firebase'),
    'server_configured', exists (select 1 from telima.push_secrets where key = 'fcm_service_account'),
    'project_id', (select value ->> 'projectId' from telima.app_settings where key = 'firebase'),
    'devices', (select count(*) from telima.device_tokens),
    'users_with_device', (select count(distinct user_id) from telima.device_tokens));
end $$;

create or replace function telima.admin_set_firebase(p_client jsonb, p_service jsonb)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare v_client jsonb; v_app jsonb; v_project text;
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur'; end if;
  if p_client is not null then
    v_project := p_client #>> '{project_info,project_id}';
    select c into v_app from jsonb_array_elements(p_client -> 'client') c
     where c #>> '{client_info,android_client_info,package_name}' = 'app.telima.telima' limit 1;
    if v_project is null or v_app is null then
      raise exception 'Fichier google-services.json invalide ou sans application « app.telima.telima »';
    end if;
    v_client := jsonb_build_object(
      'apiKey', v_app #>> '{api_key,0,current_key}',
      'appId', v_app #>> '{client_info,mobilesdk_app_id}',
      'messagingSenderId', p_client #>> '{project_info,project_number}',
      'projectId', v_project,
      'storageBucket', p_client #>> '{project_info,storage_bucket}');
    insert into telima.app_settings(key, value, description, is_public, updated_by)
    values ('firebase', v_client, 'Configuration Firebase (notifications push)', true, auth.uid())
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();
  end if;
  if p_service is not null then
    if p_service ->> 'type' <> 'service_account' or p_service ->> 'private_key' is null then
      raise exception 'Clé de compte de service invalide';
    end if;
    insert into telima.push_secrets(key, value) values ('fcm_service_account', p_service::text)
    on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;
  return telima.admin_push_status();
end $$;

create or replace function telima.send_test_notification()
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  if auth.uid() is null then raise exception 'Non connecté'; end if;
  perform telima.notify_user(auth.uid(), 'info', 'Notifications activées ✅',
    'Vous recevrez ici vos courses, livraisons et messages, même application fermée.');
end $$;
