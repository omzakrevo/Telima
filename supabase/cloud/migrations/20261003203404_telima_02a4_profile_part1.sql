-- Migration appliquée sur le projet Supabase cloud : telima_02a4_profile_part1

create or replace function telima.update_my_profile(p_full_name text, p_city_id uuid, p_avatar_url text default null)
returns telima.users language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_row telima.users;
begin
  if p_full_name is null or char_length(trim(p_full_name)) < 2 then
    raise exception 'Nom invalide' using errcode = '22023';
  end if;
  update telima.users
     set full_name = trim(p_full_name),
         city_id = p_city_id,
         avatar_url = coalesce(p_avatar_url, avatar_url)
   where id = v_uid returning * into v_row;
  update telima.drivers set city_id = p_city_id where user_id = v_uid;
  return v_row;
end $$;

create or replace function telima.register_device_token(p_token text, p_platform text)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  insert into telima.device_tokens(token, user_id, platform) values (p_token, v_uid, p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end $$;

create or replace function telima.mark_notifications_read(p_ids bigint[] default null)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  update telima.notifications set read_at = now()
   where user_id = v_uid and read_at is null and (p_ids is null or id = any(p_ids));
end $$;
