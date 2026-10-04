-- Migration appliquée sur le projet Supabase cloud : telima_02a2_require

create or replace function telima.require_active_user()
returns uuid language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if not exists (select 1 from telima.users where id = v_uid and is_active) then
    raise exception 'Compte désactivé ou introuvable' using errcode = '28000';
  end if;
  return v_uid;
end $$;

create or replace function telima.require_staff()
returns uuid language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if not telima.is_staff() then
    raise exception 'Accès réservé à l''administration' using errcode = '42501';
  end if;
  return v_uid;
end $$;

create or replace function telima.require_admin()
returns uuid language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if not telima.is_admin() then
    raise exception 'Accès réservé aux administrateurs' using errcode = '42501';
  end if;
  return v_uid;
end $$;

create or replace function telima.get_setting(p_key text, p_default jsonb default null)
returns jsonb language sql stable security definer set search_path = telima, public as $$
  select coalesce((select value from telima.app_settings where key = p_key), p_default)
$$;

create or replace function telima.normalize_phone(p_phone text)
returns text language plpgsql immutable as $$
declare v text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
begin
  if v like '00%' then v := '+' || substr(v, 3); end if;
  if v ~ '^[0-9]{8}$' then v := '+226' || v; end if;
  if v ~ '^226[0-9]{8}$' then v := '+' || v; end if;
  if v !~ '^\+[0-9]{8,15}$' then
    raise exception 'Numéro de téléphone invalide : %', p_phone using errcode = '22023';
  end if;
  return v;
end $$;

create or replace function telima.haversine_km(lat1 double precision, lng1 double precision,
                                               lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 2 * 6371.0 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ))
$$;

create or replace function telima.next_code(p_scope text, p_prefix text)
returns text language plpgsql security definer set search_path = telima, public as $$
declare
  v_year int := extract(year from now() at time zone 'Africa/Ouagadougou')::int;
  v_last int;
begin
  insert into telima.code_counters(scope, year, last) values (p_scope, v_year, 1)
  on conflict (scope, year) do update set last = telima.code_counters.last + 1
  returning last into v_last;
  return format('%s-%s-%s', p_prefix, v_year, lpad(v_last::text, 6, '0'));
end $$;

create or replace function telima.log_admin_action(p_action text, p_entity text, p_entity_id text, p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = telima, public as $$
  insert into telima.admin_logs(admin_id, action, entity, entity_id, details)
  values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_details, '{}'::jsonb));
$$;

create or replace function telima.notify_user(p_user_id uuid, p_type text, p_title text, p_body text, p_data jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  if p_user_id is null then return; end if;
  insert into telima.notifications(user_id, type, title, body, data)
  values (p_user_id, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
end $$;

create or replace function telima.notify_staff(p_type text, p_title text, p_body text, p_data jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = telima, public as $$
  insert into telima.notifications(user_id, type, title, body, data)
  select id, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb)
  from telima.users where role in ('admin', 'operator') and is_active;
$$;
