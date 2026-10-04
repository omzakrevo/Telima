-- =====================================================================
-- TELIMA — Migration 2 : fonctions métier (validation côté serveur)
-- Toutes les opérations sensibles passent par des fonctions SECURITY DEFINER
-- qui vérifient l'identité (auth.uid()), le rôle et l'état avant d'agir.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Aides générales
-- ---------------------------------------------------------------------
create or replace function telima.current_user_role()
returns telima.user_role
language sql stable security definer set search_path = telima, public as $$
  select role from telima.users where id = auth.uid() and is_active
$$;

create or replace function telima.is_admin()
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (select 1 from telima.users where id = auth.uid() and role = 'admin' and is_active)
$$;

-- admin ou opérateur (personnel de la plateforme)
create or replace function telima.is_staff()
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (select 1 from telima.users where id = auth.uid() and role in ('admin', 'operator') and is_active)
$$;

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
  if v ~ '^[0-9]{8}$' then v := '+226' || v; end if;         -- numéro burkinabè local
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

-- ---------------------------------------------------------------------
-- Portefeuille : unique point d'écriture des soldes
-- ---------------------------------------------------------------------
create or replace function telima.ensure_wallet(p_user_id uuid)
returns uuid language plpgsql security definer set search_path = telima, public as $$
declare v_id uuid;
begin
  select id into v_id from telima.wallets where user_id = p_user_id;
  if v_id is null then
    insert into telima.wallets(user_id) values (p_user_id)
    on conflict (user_id) do nothing returning id into v_id;
    if v_id is null then select id into v_id from telima.wallets where user_id = p_user_id; end if;
  end if;
  return v_id;
end $$;

create or replace function telima.wallet_apply(
  p_user_id uuid, p_type telima.wallet_tx_type, p_amount integer,
  p_delivery_id uuid default null, p_withdrawal_id uuid default null,
  p_description text default null, p_allow_negative boolean default false)
returns integer language plpgsql security definer set search_path = telima, public as $$
declare
  v_wallet uuid := telima.ensure_wallet(p_user_id);
  v_balance integer;
begin
  if p_amount = 0 then
    select balance into v_balance from telima.wallets where id = v_wallet;
    return v_balance;
  end if;
  select balance into v_balance from telima.wallets where id = v_wallet for update;
  if not p_allow_negative and v_balance + p_amount < 0 then
    raise exception 'Solde insuffisant (solde : % FCFA)', v_balance using errcode = 'P0001';
  end if;
  update telima.wallets set balance = balance + p_amount, updated_at = now()
   where id = v_wallet returning balance into v_balance;
  insert into telima.wallet_transactions(wallet_id, type, amount, balance_after, delivery_id, withdrawal_id, description, created_by)
  values (v_wallet, p_type, p_amount, v_balance, p_delivery_id, p_withdrawal_id, p_description, auth.uid());
  return v_balance;
end $$;

-- ---------------------------------------------------------------------
-- Création du profil à l'inscription (déclencheur sur auth.users)
-- ---------------------------------------------------------------------
create or replace function telima.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare
  v_meta  jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_phone text;
  v_role  telima.user_role := 'client';
  v_city  uuid;
begin
  v_phone := telima.normalize_phone(coalesce(v_meta->>'phone', new.phone, split_part(new.email, '@', 1)));
  if v_meta->>'role' = 'driver' then v_role := 'driver'; end if;   -- admin/opérateur jamais auto-attribués
  if v_meta ? 'city_id' and nullif(v_meta->>'city_id', '') is not null then
    select id into v_city from telima.cities where id = (v_meta->>'city_id')::uuid;
  end if;

  insert into telima.users(id, phone, full_name, city_id, avatar_url, role)
  values (new.id, v_phone, coalesce(nullif(trim(v_meta->>'full_name'), ''), 'Utilisateur'), v_city,
          nullif(v_meta->>'avatar_url', ''), v_role);
  insert into telima.customers(user_id) values (new.id);
  perform telima.ensure_wallet(new.id);
  if v_role = 'driver' then
    insert into telima.drivers(user_id, city_id) values (new.id, v_city);
  end if;
  return new;
end $$;

drop trigger if exists telima_on_auth_user_created on auth.users;
create trigger telima_on_auth_user_created after insert on auth.users
  for each row when (new.email like '%@telima.app') execute function telima.handle_new_auth_user();

-- Empêche un utilisateur de modifier lui-même son rôle, son statut ou son téléphone
create or replace function telima.tg_users_guard()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if auth.uid() is null or telima.is_admin() then
    return new;  -- service_role ou administrateur
  end if;
  if new.role is distinct from old.role
     or new.phone is distinct from old.phone
     or (new.is_active is distinct from old.is_active and not (old.id = auth.uid() and new.is_active = false))
     or new.id is distinct from old.id then
    raise exception 'Modification non autorisée' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_users_guard before update on telima.users
  for each row execute function telima.tg_users_guard();

-- ---------------------------------------------------------------------
-- Profil
-- ---------------------------------------------------------------------
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

create or replace function telima.deactivate_my_account()
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if exists (select 1 from telima.deliveries
             where (customer_id = v_uid or driver_id = v_uid)
               and status not in ('completed', 'cancelled')) then
    raise exception 'Impossible : vous avez une livraison en cours' using errcode = 'P0001';
  end if;
  update telima.users set is_active = false, deactivated_at = now() where id = v_uid;
  update telima.drivers set is_online = false where user_id = v_uid;
  -- les jetons de notification sont retirés par l'application juste avant (RLS device_tokens_own)
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

-- ---------------------------------------------------------------------
-- Tarification
-- ---------------------------------------------------------------------
create or replace function telima.vehicle_rank(p telima.vehicle_type)
returns int language sql immutable as $$
  select case p when 'moto' then 1 when 'tricycle' then 2 when 'voiture' then 2 when 'utilitaire' then 3 end
$$;

-- Véhicule conseillé selon la taille / le poids / la catégorie
create or replace function telima.suggest_vehicle(p_size telima.package_size, p_weight numeric, p_category telima.package_category)
returns telima.vehicle_type language sql immutable as $$
  select case
    when p_size = 'tres_grand' or coalesce(p_weight, 0) > 300 then 'utilitaire'::telima.vehicle_type
    when p_size = 'grand' or p_category = 'gros_colis' or coalesce(p_weight, 0) > 30 then 'tricycle'::telima.vehicle_type
    else 'moto'::telima.vehicle_type
  end
$$;

-- Le véhicule du livreur peut-il transporter une demande prévue pour p_requested ?
create or replace function telima.vehicle_can_serve(p_driver telima.vehicle_type, p_requested telima.vehicle_type)
returns boolean language sql immutable as $$
  select p_driver = p_requested
      or p_driver = 'utilitaire'
      or (p_driver in ('voiture', 'tricycle') and p_requested = 'moto')
$$;

create or replace function telima.find_city(p_lat double precision, p_lng double precision)
returns uuid language sql stable security definer set search_path = telima, public as $$
  select id from telima.cities
   where is_active and telima.haversine_km(p_lat, p_lng, center_lat, center_lng) <= radius_km
   order by telima.haversine_km(p_lat, p_lng, center_lat, center_lng)
   limit 1
$$;

create or replace function telima.find_zone(p_city uuid, p_lat double precision, p_lng double precision)
returns telima.delivery_zones language sql stable security definer set search_path = telima, public as $$
  select z.* from telima.delivery_zones z
   where z.is_active and z.city_id = p_city
     and telima.haversine_km(p_lat, p_lng, z.center_lat, z.center_lng) <= z.radius_km
   order by z.extra_fee desc, z.multiplier desc
   limit 1
$$;

create or replace function telima.round_up_to(p_value numeric, p_step integer)
returns integer language sql immutable as $$
  select case when coalesce(p_step, 0) <= 1 then ceil(p_value)::int
              else (ceil(p_value / p_step) * p_step)::int end
$$;

create or replace function telima.compute_commission(p_total integer)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_cfg jsonb := telima.get_setting('commission', '{"type":"percent","value":15}');
  v_type telima.commission_type := coalesce(v_cfg->>'type', 'percent')::telima.commission_type;
  v_value numeric := coalesce((v_cfg->>'value')::numeric, 15);
  v_amount integer;
begin
  if v_type = 'percent' then
    v_amount := round(p_total * v_value / 100.0)::int;
  else
    v_amount := round(v_value)::int;
  end if;
  v_amount := greatest(0, least(v_amount, p_total));
  return jsonb_build_object('type', v_type, 'value', v_value, 'amount', v_amount, 'driver_earning', p_total - v_amount);
end $$;

-- Devis : utilisé pour l'affichage AVANT confirmation ET pour l'enregistrement (même calcul).
-- p_route_km : distance routière fournie par le client (OSRM) ; acceptée seulement si plausible.
create or replace function telima.quote_delivery(
  p_pickup_lat double precision, p_pickup_lng double precision,
  p_dropoff_lat double precision, p_dropoff_lng double precision,
  p_vehicle_type telima.vehicle_type default null,
  p_size telima.package_size default 'petit',
  p_fragile boolean default false,
  p_weight_kg numeric default null,
  p_category telima.package_category default 'petit_colis',
  p_route_km numeric default null,
  p_is_extra_stop boolean default false)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_straight double precision := telima.haversine_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng);
  v_factor numeric := coalesce((telima.get_setting('road_factor', '1.3'))::text::numeric, 1.3);
  v_rounding int := coalesce((telima.get_setting('price_rounding', '50'))::text::int, 50);
  v_distance numeric;
  v_suggested telima.vehicle_type := telima.suggest_vehicle(p_size, p_weight_kg, p_category);
  v_vehicle telima.vehicle_type;
  v_city uuid;
  v_zone telima.delivery_zones;
  v_zone2 telima.delivery_zones;
  v_rule telima.pricing_rules;
  v_base int := 0; v_dist_price int := 0; v_extras int := 0; v_zone_fee int := 0;
  v_subtotal numeric; v_total int; v_mult numeric := 1;
begin
  if p_pickup_lat is null or p_dropoff_lat is null then
    raise exception 'Coordonnées manquantes' using errcode = '22023';
  end if;
  v_vehicle := coalesce(p_vehicle_type, v_suggested);
  -- un véhicule trop petit pour le colis est refusé
  if telima.vehicle_rank(v_vehicle) < telima.vehicle_rank(v_suggested) then
    v_vehicle := v_suggested;
  end if;

  if p_route_km is not null and p_route_km >= v_straight * 0.95 and p_route_km <= greatest(v_straight * 2.5, v_straight + 2) then
    v_distance := round(p_route_km::numeric, 2);
  else
    v_distance := round((v_straight * v_factor)::numeric, 2);
  end if;

  v_city := telima.find_city(p_pickup_lat, p_pickup_lng);
  select * into v_rule from telima.pricing_rules
   where is_active and vehicle_type = v_vehicle and (city_id = v_city or city_id is null)
   order by (city_id is null) limit 1;
  if v_rule.id is null then
    raise exception 'Aucun tarif configuré pour le véhicule %', v_vehicle using errcode = 'P0001';
  end if;

  if not p_is_extra_stop then
    v_base := v_rule.base_price;
    v_dist_price := ceil(greatest(0, v_distance - v_rule.included_km) * v_rule.price_per_km)::int;
  else
    v_base := v_rule.extra_stop_fee;
    v_dist_price := ceil(v_distance * v_rule.price_per_km)::int;
  end if;

  v_extras := case p_size when 'moyen' then v_rule.size_fee_moyen
                          when 'grand' then v_rule.size_fee_grand
                          when 'tres_grand' then v_rule.size_fee_tres_grand
                          else 0 end
              + case when p_fragile then v_rule.fragile_fee else 0 end;

  if v_city is not null then
    v_zone := telima.find_zone(v_city, p_pickup_lat, p_pickup_lng);
    v_zone2 := telima.find_zone(v_city, p_dropoff_lat, p_dropoff_lng);
    if v_zone2.id is not null and (v_zone.id is null or v_zone2.extra_fee > v_zone.extra_fee) then
      v_zone := v_zone2;
    end if;
    if v_zone.id is not null then
      v_zone_fee := v_zone.extra_fee;
      v_mult := v_zone.multiplier;
    end if;
  end if;

  v_subtotal := (v_base + v_dist_price + v_extras) * v_mult;
  -- l'écart du multiplicateur est affiché dans les frais de zone
  v_zone_fee := v_zone_fee + round(v_subtotal - (v_base + v_dist_price + v_extras))::int;
  v_total := telima.round_up_to(greatest(v_subtotal + coalesce(v_zone.extra_fee, 0),
                                         case when p_is_extra_stop then 0 else v_rule.min_price end), v_rounding);
  -- l'arrondi est intégré aux frais de distance pour que la somme des lignes = total
  v_dist_price := v_total - v_base - v_extras - v_zone_fee;

  return jsonb_build_object(
    'distance_km', v_distance,
    'straight_km', round(v_straight::numeric, 2),
    'vehicle_type', v_vehicle,
    'suggested_vehicle', v_suggested,
    'city_id', v_city,
    'zone_id', v_zone.id,
    'zone_name', v_zone.name,
    'price_base', v_base,
    'price_distance', v_dist_price,
    'price_extras', v_extras,
    'price_zone', v_zone_fee,
    'total_price', v_total,
    'currency', 'FCFA'
  );
end $$;

-- ---------------------------------------------------------------------
-- Création d'une livraison (cœur commun : client, entreprise, opérateur)
-- ---------------------------------------------------------------------
create or replace function telima._insert_delivery(
  p jsonb, p_customer_id uuid, p_customer_name text, p_customer_phone text,
  p_created_by uuid, p_via text, p_batch_id uuid default null, p_stop_order int default 1,
  p_is_extra_stop boolean default false, p_from_lat double precision default null,
  p_from_lng double precision default null, p_price_override integer default null)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_pick jsonb := p->'pickup';
  v_drop jsonb := p->'dropoff';
  v_pkg  jsonb := coalesce(p->'package', '{}'::jsonb);
  v_method telima.payment_method := coalesce(p->>'payment_method', 'cash')::telima.payment_method;
  v_enabled jsonb := telima.get_setting('payment_methods', '["cash","cash_on_delivery","orange_money","moov_money","wallet"]');
  v_quote jsonb;
  v_comm jsonb;
  v_total int;
  v_row telima.deliveries;
  v_status telima.delivery_status;
  v_payment_status telima.payment_status := 'pending';
begin
  if v_pick is null or v_drop is null then
    raise exception 'Point de récupération et destination obligatoires' using errcode = '22023';
  end if;
  if coalesce(trim(v_pick->>'address'), '') = '' or coalesce(trim(v_drop->>'address'), '') = '' then
    raise exception 'Adresse obligatoire' using errcode = '22023';
  end if;
  if not (v_enabled ? v_method::text) then
    raise exception 'Moyen de paiement indisponible' using errcode = 'P0001';
  end if;

  v_quote := telima.quote_delivery(
    coalesce(p_from_lat, (v_pick->>'lat')::float8), coalesce(p_from_lng, (v_pick->>'lng')::float8),
    (v_drop->>'lat')::float8, (v_drop->>'lng')::float8,
    nullif(p->>'vehicle_type', '')::telima.vehicle_type,
    coalesce(nullif(v_pkg->>'size', ''), 'petit')::telima.package_size,
    coalesce((v_pkg->>'fragile')::boolean, false),
    nullif(v_pkg->>'weight_kg', '')::numeric,
    coalesce(nullif(v_pkg->>'category', ''), 'petit_colis')::telima.package_category,
    nullif(p->>'route_km', '')::numeric,
    p_is_extra_stop);

  v_total := coalesce(p_price_override, (v_quote->>'total_price')::int);
  if v_total < 0 then raise exception 'Prix invalide' using errcode = '22023'; end if;
  v_comm := telima.compute_commission(v_total);

  v_status := case when v_method in ('orange_money', 'moov_money') then 'created' else 'searching' end;
  if p_batch_id is not null and p_stop_order > 1 then
    v_status := 'created';  -- les arrêts suivants suivent le premier arrêt du lot
  end if;

  insert into telima.deliveries(
    code, status, customer_id, customer_name, customer_phone, business_id, created_by, created_via,
    vehicle_type, city_id, zone_id, batch_id, stop_order,
    pickup_address, pickup_lat, pickup_lng, pickup_contact_name, pickup_contact_phone, pickup_instructions,
    dropoff_address, dropoff_lat, dropoff_lng, dropoff_contact_name, dropoff_contact_phone, dropoff_instructions,
    package_category, package_description, package_photo_path, package_quantity, package_fragile, package_size, package_weight_kg,
    distance_km, price_base, price_distance, price_extras, price_zone, total_price,
    commission_type, commission_value, commission_amount, driver_earning,
    payment_method, payment_status, searching_at)
  values (
    telima.next_code('delivery', 'LIV'), v_status, p_customer_id, p_customer_name, p_customer_phone,
    nullif(p->>'business_id', '')::uuid, p_created_by, p_via,
    (v_quote->>'vehicle_type')::telima.vehicle_type, nullif(v_quote->>'city_id', '')::uuid, nullif(v_quote->>'zone_id', '')::uuid,
    p_batch_id, p_stop_order,
    trim(v_pick->>'address'), (v_pick->>'lat')::float8, (v_pick->>'lng')::float8,
    coalesce(nullif(trim(v_pick->>'contact_name'), ''), p_customer_name),
    telima.normalize_phone(coalesce(nullif(v_pick->>'contact_phone', ''), p_customer_phone)),
    nullif(trim(v_pick->>'instructions'), ''),
    trim(v_drop->>'address'), (v_drop->>'lat')::float8, (v_drop->>'lng')::float8,
    coalesce(nullif(trim(v_drop->>'contact_name'), ''), 'Destinataire'),
    telima.normalize_phone(v_drop->>'contact_phone'),
    nullif(trim(v_drop->>'instructions'), ''),
    coalesce(nullif(v_pkg->>'category', ''), 'petit_colis')::telima.package_category,
    nullif(trim(v_pkg->>'description'), ''), nullif(v_pkg->>'photo_path', ''),
    coalesce((v_pkg->>'quantity')::int, 1), coalesce((v_pkg->>'fragile')::boolean, false),
    coalesce(nullif(v_pkg->>'size', ''), 'petit')::telima.package_size, nullif(v_pkg->>'weight_kg', '')::numeric,
    (v_quote->>'distance_km')::numeric,
    case when p_price_override is null then (v_quote->>'price_base')::int else v_total end,
    case when p_price_override is null then (v_quote->>'price_distance')::int else 0 end,
    case when p_price_override is null then (v_quote->>'price_extras')::int else 0 end,
    case when p_price_override is null then (v_quote->>'price_zone')::int else 0 end,
    v_total,
    (v_comm->>'type')::telima.commission_type, (v_comm->>'value')::numeric,
    (v_comm->>'amount')::int, (v_comm->>'driver_earning')::int,
    v_method, 'pending', case when v_status = 'searching' then now() end)
  returning * into v_row;

  insert into telima.delivery_secrets(delivery_id, otp_code)
  values (v_row.id, lpad((floor(random() * 10000))::int::text, 4, '0'));

  -- Paiement
  if v_method = 'wallet' then
    if p_customer_id is null then
      raise exception 'Le portefeuille nécessite un compte client' using errcode = 'P0001';
    end if;
    perform telima.wallet_apply(p_customer_id, 'payment', -v_total, v_row.id, null,
                                'Paiement livraison ' || v_row.code);
    v_payment_status := 'paid';
  end if;
  insert into telima.payments(delivery_id, payer_id, amount, method, provider, status, paid_at, metadata)
  values (v_row.id, p_customer_id, v_total, v_method,
          case when v_method in ('orange_money', 'moov_money') then v_method::text
               when v_method = 'wallet' then 'internal' else 'cash' end,
          v_payment_status, case when v_payment_status = 'paid' then now() end,
          jsonb_build_object('kind', 'delivery'));
  if v_payment_status = 'paid' then
    update telima.deliveries set payment_status = 'paid' where id = v_row.id returning * into v_row;
  end if;

  return v_row;
end $$;

-- Avertit les livreurs en ligne proches d'une nouvelle demande
create or replace function telima.notify_nearby_drivers(p_delivery telima.deliveries)
returns integer language plpgsql security definer set search_path = telima, public as $$
declare
  v_radius numeric := coalesce((telima.get_setting('dispatch_radius_km', '7'))::text::numeric, 7);
  v_count int;
begin
  insert into telima.notifications(user_id, type, title, body, data)
  select d.user_id, 'new_request', 'Nouvelle demande de livraison',
         format('%s → %s · %s FCFA', p_delivery.pickup_address, p_delivery.dropoff_address, p_delivery.driver_earning),
         jsonb_build_object('delivery_id', p_delivery.id)
    from telima.drivers d
    join telima.vehicles v on v.driver_id = d.user_id and v.is_active
    join telima.users u on u.id = d.user_id and u.is_active
   where d.is_online and d.status = 'approved'
     and telima.vehicle_can_serve(v.type, p_delivery.vehicle_type)
     and d.current_lat is not null
     and telima.haversine_km(d.current_lat, d.current_lng, p_delivery.pickup_lat, p_delivery.pickup_lng) <= v_radius;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

create or replace function telima.create_delivery(p jsonb)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_user telima.users;
  v_row telima.deliveries;
begin
  select * into v_user from telima.users where id = v_uid;
  if (p->>'business_id') is not null and not exists (
      select 1 from telima.business_members where business_id = (p->>'business_id')::uuid and user_id = v_uid) then
    raise exception 'Vous n''êtes pas membre de ce compte professionnel' using errcode = '42501';
  end if;
  v_row := telima._insert_delivery(p, v_uid, v_user.full_name, v_user.phone, v_uid,
                                   case when p->>'business_id' is not null then 'business' else 'app' end);
  if v_row.status = 'searching' then
    perform telima.notify_nearby_drivers(v_row);
  end if;
  return v_row;
end $$;

-- Livraison multi-destinations : un point de récupération, plusieurs arrêts
-- p = { pickup:{...}, vehicle_type, payment_method, business_id, stops:[ {dropoff:{...}, package:{...}}, ... ] }
create or replace function telima.create_delivery_batch(p jsonb)
returns setof telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_user telima.users;
  v_batch uuid;
  v_stop jsonb;
  v_i int := 0;
  v_n int := jsonb_array_length(coalesce(p->'stops', '[]'::jsonb));
  v_prev_lat float8 := (p->'pickup'->>'lat')::float8;
  v_prev_lng float8 := (p->'pickup'->>'lng')::float8;
  v_row telima.deliveries;
  v_first telima.deliveries;
  v_total int := 0;
  v_vehicle text := p->>'vehicle_type';
begin
  if v_n < 1 or v_n > 15 then
    raise exception 'Entre 1 et 15 destinations' using errcode = '22023';
  end if;
  if (p->>'business_id') is not null and not exists (
      select 1 from telima.business_members where business_id = (p->>'business_id')::uuid and user_id = v_uid) then
    raise exception 'Vous n''êtes pas membre de ce compte professionnel' using errcode = '42501';
  end if;
  select * into v_user from telima.users where id = v_uid;
  insert into telima.delivery_batches(code, customer_id, business_id, stops_count)
  values (telima.next_code('batch', 'LOT'), v_uid, nullif(p->>'business_id', '')::uuid, v_n)
  returning id into v_batch;

  for v_stop in select * from jsonb_array_elements(p->'stops') loop
    v_i := v_i + 1;
    v_row := telima._insert_delivery(
      jsonb_build_object('pickup', p->'pickup', 'dropoff', v_stop->'dropoff', 'package', v_stop->'package',
                         'vehicle_type', v_vehicle, 'payment_method', p->>'payment_method',
                         'business_id', p->>'business_id'),
      v_uid, v_user.full_name, v_user.phone, v_uid,
      case when p->>'business_id' is not null then 'business' else 'app' end,
      v_batch, v_i, v_i > 1, v_prev_lat, v_prev_lng);
    -- tous les arrêts utilisent le véhicule du premier
    if v_i = 1 then v_vehicle := v_row.vehicle_type::text; v_first := v_row; end if;
    v_prev_lat := v_row.dropoff_lat; v_prev_lng := v_row.dropoff_lng;
    v_total := v_total + v_row.total_price;
    return next v_row;
  end loop;

  update telima.delivery_batches set total_price = v_total where id = v_batch;
  if v_first.status = 'searching' then
    perform telima.notify_nearby_drivers(v_first);
  end if;
  return;
end $$;

-- ---------------------------------------------------------------------
-- Paiements : simulation et confirmation (fournisseurs Mobile Money)
-- ---------------------------------------------------------------------
-- Confirmation interne d'un paiement (appelée par le mode simulation ou par le webhook d'un fournisseur)
create or replace function telima._confirm_payment(p_payment_id uuid, p_provider_ref text)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_pay telima.payments; v_del telima.deliveries;
begin
  select * into v_pay from telima.payments where id = p_payment_id for update;
  if v_pay.id is null then raise exception 'Paiement introuvable' using errcode = 'P0002'; end if;
  if v_pay.status = 'paid' then return v_pay; end if;
  if v_pay.status <> 'pending' then raise exception 'Paiement non confirmable' using errcode = 'P0001'; end if;

  update telima.payments set status = 'paid', paid_at = now(), provider_ref = p_provider_ref
   where id = p_payment_id returning * into v_pay;

  if v_pay.metadata->>'kind' = 'topup' then
    perform telima.wallet_apply(v_pay.payer_id, 'topup', v_pay.amount, null, null,
                                'Rechargement ' || v_pay.method::text);
  elsif v_pay.delivery_id is not null then
    update telima.deliveries set payment_status = 'paid' where id = v_pay.delivery_id returning * into v_del;
    if v_del.status = 'created' and v_del.stop_order = 1 then
      update telima.deliveries set status = 'searching', searching_at = now()
       where id = v_del.id returning * into v_del;
      perform telima.notify_nearby_drivers(v_del);
    end if;
  end if;
  return v_pay;
end $$;

-- Paiement simulé (disponible uniquement si payment_mode = "simulation")
create or replace function telima.confirm_simulated_payment(p_payment_id uuid)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_pay telima.payments;
begin
  if telima.get_setting('payment_mode', '"simulation"') #>> '{}' <> 'simulation' then
    raise exception 'Le mode simulation est désactivé' using errcode = '42501';
  end if;
  select * into v_pay from telima.payments where id = p_payment_id;
  if v_pay.payer_id is distinct from v_uid and not telima.is_staff() then
    raise exception 'Paiement introuvable' using errcode = 'P0002';
  end if;
  return telima._confirm_payment(p_payment_id, 'SIM-' || upper(substr(md5(random()::text), 1, 10)));
end $$;

create or replace function telima.mark_payment_failed(p_payment_id uuid, p_reason text default null)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_pay telima.payments;
begin
  select * into v_pay from telima.payments where id = p_payment_id for update;
  if v_pay.id is null or (v_pay.payer_id is distinct from v_uid and not telima.is_staff()) then
    raise exception 'Paiement introuvable' using errcode = 'P0002';
  end if;
  if v_pay.status <> 'pending' then return v_pay; end if;
  update telima.payments set status = 'failed', metadata = metadata || jsonb_build_object('failure', p_reason)
   where id = p_payment_id returning * into v_pay;
  if v_pay.delivery_id is not null then
    update telima.deliveries set payment_status = 'failed' where id = v_pay.delivery_id;
  end if;
  return v_pay;
end $$;

-- Change le moyen de paiement d'une livraison non encore payée (ex. échec Mobile Money → espèces)
create or replace function telima.change_payment_method(p_delivery_id uuid, p_method telima.payment_method)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or (v_del.customer_id is distinct from v_uid and not telima.is_staff()) then
    raise exception 'Livraison introuvable' using errcode = 'P0002';
  end if;
  if v_del.payment_status = 'paid' or v_del.status not in ('created', 'searching') then
    raise exception 'Le moyen de paiement ne peut plus être modifié' using errcode = 'P0001';
  end if;
  if p_method in ('orange_money', 'moov_money', 'wallet') and v_del.batch_id is not null then
    raise exception 'Non disponible pour un lot' using errcode = 'P0001';
  end if;
  update telima.payments set status = 'cancelled' where delivery_id = p_delivery_id and status in ('pending', 'failed');
  if p_method = 'wallet' then
    perform telima.wallet_apply(v_del.customer_id, 'payment', -v_del.total_price, v_del.id, null, 'Paiement livraison ' || v_del.code);
  end if;
  insert into telima.payments(delivery_id, payer_id, amount, method, provider, status, paid_at, metadata)
  values (v_del.id, v_del.customer_id, v_del.total_price, p_method,
          case when p_method in ('orange_money', 'moov_money') then p_method::text when p_method = 'wallet' then 'internal' else 'cash' end,
          case when p_method = 'wallet' then 'paid' else 'pending' end::telima.payment_status,
          case when p_method = 'wallet' then now() end, jsonb_build_object('kind', 'delivery'));
  update telima.deliveries
     set payment_method = p_method,
         payment_status = case when p_method = 'wallet' then 'paid' else 'pending' end::telima.payment_status,
         status = case when p_method in ('orange_money', 'moov_money') then 'created'
                       when status = 'created' and stop_order = 1 then 'searching' else status end,
         searching_at = coalesce(searching_at, case when p_method not in ('orange_money', 'moov_money') then now() end)
   where id = p_delivery_id returning * into v_del;
  if v_del.status = 'searching' then perform telima.notify_nearby_drivers(v_del); end if;
  return v_del;
end $$;

-- Rechargement du portefeuille : crée un paiement en attente à confirmer par le fournisseur
create or replace function telima.request_wallet_topup(p_amount integer, p_method telima.payment_method)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_pay telima.payments;
begin
  if p_amount < 100 or p_amount > 1000000 then
    raise exception 'Montant invalide (100 à 1 000 000 FCFA)' using errcode = '22023';
  end if;
  if p_method not in ('orange_money', 'moov_money') then
    raise exception 'Rechargement possible via Orange Money ou Moov Money' using errcode = '22023';
  end if;
  insert into telima.payments(payer_id, amount, method, provider, status, metadata)
  values (v_uid, p_amount, p_method, p_method::text, 'pending', jsonb_build_object('kind', 'topup'))
  returning * into v_pay;
  return v_pay;
end $$;

-- ---------------------------------------------------------------------
-- Espace livreur
-- ---------------------------------------------------------------------
create or replace function telima.submit_driver_application(p jsonb)
returns telima.drivers language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_drv telima.drivers; v_city uuid;
begin
  v_city := coalesce(nullif(p->>'city_id', '')::uuid, (select city_id from telima.users where id = v_uid));
  insert into telima.drivers(user_id, city_id) values (v_uid, v_city) on conflict (user_id) do nothing;
  select * into v_drv from telima.drivers where user_id = v_uid for update;
  if v_drv.status = 'suspended' then
    raise exception 'Compte livreur suspendu, contactez le support' using errcode = '42501';
  end if;
  if coalesce(trim(p->>'id_document_number'), '') = '' then
    raise exception 'Numéro CNIB/CNI obligatoire' using errcode = '22023';
  end if;
  if coalesce(p->>'vehicle_type', '') = '' then
    raise exception 'Type de véhicule obligatoire' using errcode = '22023';
  end if;
  if (p->>'vehicle_type') <> 'moto' and coalesce(trim(p->>'license_number'), '') = '' and (p->>'vehicle_type') <> 'tricycle' then
    raise exception 'Permis de conduire obligatoire pour ce véhicule' using errcode = '22023';
  end if;

  update telima.drivers set
    city_id = v_city,
    id_document_number = trim(p->>'id_document_number'),
    id_document_path = coalesce(nullif(p->>'id_document_path', ''), id_document_path),
    license_number = nullif(trim(p->>'license_number'), ''),
    license_path = coalesce(nullif(p->>'license_path', ''), license_path),
    status = (case when status = 'approved' then 'approved' else 'pending' end)::telima.driver_status
  where user_id = v_uid returning * into v_drv;

  update telima.vehicles set is_active = false where driver_id = v_uid and is_active;
  insert into telima.vehicles(driver_id, type, brand, model, color, plate_number, photo_path, is_active)
  values (v_uid, (p->>'vehicle_type')::telima.vehicle_type, nullif(p->>'brand', ''), nullif(p->>'model', ''),
          nullif(p->>'color', ''), nullif(upper(trim(p->>'plate_number')), ''), nullif(p->>'vehicle_photo_path', ''), true);

  update telima.users set role = 'driver' where id = v_uid and role = 'client';
  if v_drv.status = 'pending' then
    perform telima.notify_staff('driver_application', 'Nouvelle inscription livreur',
      (select full_name || ' (' || phone || ')' from telima.users where id = v_uid),
      jsonb_build_object('driver_id', v_uid));
  end if;
  return v_drv;
end $$;

create or replace function telima.set_driver_online(p_online boolean, p_lat double precision default null, p_lng double precision default null)
returns telima.drivers language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_drv telima.drivers;
  v_balance int;
  v_max_debt int := coalesce((telima.get_setting('driver_max_debt', '10000'))::text::int, 10000);
begin
  select * into v_drv from telima.drivers where user_id = v_uid for update;
  if v_drv.user_id is null then raise exception 'Profil livreur introuvable' using errcode = 'P0002'; end if;
  if p_online then
    if v_drv.status <> 'approved' then
      raise exception 'Votre compte livreur n''est pas encore approuvé' using errcode = '42501';
    end if;
    if not exists (select 1 from telima.vehicles where driver_id = v_uid and is_active) then
      raise exception 'Aucun véhicule actif' using errcode = 'P0001';
    end if;
    select balance into v_balance from telima.wallets where user_id = v_uid;
    if coalesce(v_balance, 0) < -v_max_debt then
      raise exception 'Commissions dues trop élevées (% FCFA). Rechargez votre portefeuille.', -v_balance using errcode = 'P0001';
    end if;
  end if;
  update telima.drivers set is_online = p_online,
         current_lat = coalesce(p_lat, current_lat), current_lng = coalesce(p_lng, current_lng),
         last_location_at = case when p_lat is not null then now() else last_location_at end
   where user_id = v_uid returning * into v_drv;
  return v_drv;
end $$;

-- Demandes disponibles autour du livreur (informations limitées : pas de téléphones avant acceptation)
create or replace function telima.get_available_requests()
returns table (
  id uuid, code text, vehicle_type telima.vehicle_type,
  pickup_address text, pickup_lat double precision, pickup_lng double precision,
  dropoff_address text, dropoff_lat double precision, dropoff_lng double precision,
  package_category telima.package_category, package_size telima.package_size, package_fragile boolean,
  package_quantity integer, distance_km numeric, total_price integer, driver_earning integer,
  payment_method telima.payment_method, distance_to_pickup_km numeric, stops_count integer,
  batch_total_earning integer, created_at timestamptz)
language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_drv telima.drivers;
  v_vehicle telima.vehicle_type;
  v_radius numeric := coalesce((telima.get_setting('dispatch_radius_km', '7'))::text::numeric, 7);
begin
  select * into v_drv from telima.drivers where user_id = v_uid;
  if v_drv.user_id is null or v_drv.status <> 'approved' or not v_drv.is_online or v_drv.current_lat is null then
    return;
  end if;
  if exists (select 1 from telima.deliveries d where d.driver_id = v_uid and d.status in
             ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff')) then
    return;  -- une course à la fois
  end if;
  select type into v_vehicle from telima.vehicles where driver_id = v_uid and is_active;
  return query
    select d.id, d.code, d.vehicle_type, d.pickup_address, d.pickup_lat, d.pickup_lng,
           d.dropoff_address, d.dropoff_lat, d.dropoff_lng, d.package_category, d.package_size, d.package_fragile,
           d.package_quantity, d.distance_km, d.total_price, d.driver_earning, d.payment_method,
           round(telima.haversine_km(v_drv.current_lat, v_drv.current_lng, d.pickup_lat, d.pickup_lng)::numeric, 2),
           coalesce(b.stops_count, 1),
           coalesce((select sum(x.driver_earning)::int from telima.deliveries x where x.batch_id = d.batch_id), d.driver_earning),
           d.created_at
      from telima.deliveries d
      left join telima.delivery_batches b on b.id = d.batch_id
     where d.status = 'searching' and d.driver_id is null and d.stop_order = 1
       and telima.vehicle_can_serve(v_vehicle, d.vehicle_type)
       and telima.haversine_km(v_drv.current_lat, v_drv.current_lng, d.pickup_lat, d.pickup_lng) <= v_radius
       and not exists (select 1 from telima.delivery_declines x where x.delivery_id = d.id and x.driver_id = v_uid)
     order by 18 asc, d.created_at asc
     limit 20;
end $$;

create or replace function telima.accept_delivery(p_delivery_id uuid)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_drv telima.drivers;
  v_vehicle telima.vehicles;
  v_del telima.deliveries;
  v_speed numeric := coalesce((telima.get_setting('avg_speed_kmh', '25'))::text::numeric, 25);
  v_eta int;
begin
  select * into v_drv from telima.drivers where user_id = v_uid for update;
  if v_drv.user_id is null or v_drv.status <> 'approved' then
    raise exception 'Compte livreur non approuvé' using errcode = '42501';
  end if;
  if not v_drv.is_online then
    raise exception 'Passez EN LIGNE pour accepter une course' using errcode = 'P0001';
  end if;
  if exists (select 1 from telima.deliveries where driver_id = v_uid and status in
             ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff')) then
    raise exception 'Vous avez déjà une course en cours' using errcode = 'P0001';
  end if;
  select * into v_vehicle from telima.vehicles where driver_id = v_uid and is_active;

  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null then raise exception 'Demande introuvable' using errcode = 'P0002'; end if;
  if v_del.status <> 'searching' or v_del.driver_id is not null then
    raise exception 'Cette demande a déjà été prise par un autre livreur' using errcode = 'P0001';
  end if;
  if not telima.vehicle_can_serve(v_vehicle.type, v_del.vehicle_type) then
    raise exception 'Votre véhicule ne convient pas à ce colis' using errcode = 'P0001';
  end if;

  v_eta := case when v_drv.current_lat is null then null
                else greatest(1, ceil(telima.haversine_km(v_drv.current_lat, v_drv.current_lng, v_del.pickup_lat, v_del.pickup_lng)
                                     * 1.3 / v_speed * 60))::int end;

  update telima.deliveries
     set driver_id = v_uid, vehicle_id = v_vehicle.id, status = 'assigned', assigned_at = now(), eta_minutes = v_eta
   where id = p_delivery_id returning * into v_del;

  if v_del.batch_id is not null then
    update telima.deliveries set driver_id = v_uid, vehicle_id = v_vehicle.id, status = 'assigned', assigned_at = now()
     where batch_id = v_del.batch_id and id <> v_del.id and status in ('created', 'searching');
    update telima.delivery_batches set driver_id = v_uid where id = v_del.batch_id;
  end if;
  return v_del;
end $$;

create or replace function telima.decline_delivery(p_delivery_id uuid)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if not exists (select 1 from telima.drivers where user_id = v_uid) then
    raise exception 'Profil livreur introuvable' using errcode = 'P0002';
  end if;
  insert into telima.delivery_declines(delivery_id, driver_id) values (p_delivery_id, v_uid)
  on conflict do nothing;
end $$;

-- Ordre autorisé des étapes pour le livreur
create or replace function telima.next_driver_status(p telima.delivery_status)
returns telima.delivery_status language sql immutable as $$
  select case p
    when 'assigned'   then 'to_pickup'::telima.delivery_status
    when 'to_pickup'  then 'at_pickup'::telima.delivery_status
    when 'at_pickup'  then 'picked_up'::telima.delivery_status
    when 'picked_up'  then 'in_transit'::telima.delivery_status
    when 'in_transit' then 'at_dropoff'::telima.delivery_status
  end
$$;

create or replace function telima.driver_advance_status(p_delivery_id uuid, p_status telima.delivery_status,
                                                        p_lat double precision default null, p_lng double precision default null)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or v_del.driver_id is distinct from v_uid then
    raise exception 'Course introuvable' using errcode = 'P0002';
  end if;
  if v_del.status = p_status then return v_del; end if;   -- idempotent (reprise après coupure)
  if telima.next_driver_status(v_del.status) is distinct from p_status then
    raise exception 'Étape invalide : % → %', v_del.status, p_status using errcode = 'P0001';
  end if;
  if p_status = 'in_transit' and v_del.batch_id is not null and exists (
       select 1 from telima.deliveries x where x.batch_id = v_del.batch_id and x.stop_order < v_del.stop_order
          and x.status not in ('completed', 'cancelled')) then
    raise exception 'Terminez d''abord l''arrêt précédent' using errcode = 'P0001';
  end if;

  perform set_config('telima.status_lat', coalesce(p_lat::text, ''), true);
  perform set_config('telima.status_lng', coalesce(p_lng::text, ''), true);

  update telima.deliveries set status = p_status,
         picked_up_at = case when p_status = 'picked_up' then now() else picked_up_at end
   where id = p_delivery_id returning * into v_del;

  -- étapes communes au point de récupération d'un lot
  if v_del.batch_id is not null and p_status in ('to_pickup', 'at_pickup', 'picked_up') then
    update telima.deliveries set status = p_status,
           picked_up_at = case when p_status = 'picked_up' then now() else picked_up_at end
     where batch_id = v_del.batch_id and id <> v_del.id and driver_id = v_uid
       and telima.next_driver_status(status) = p_status;
  end if;
  return v_del;
end $$;

-- Le livreur abandonne une course avant récupération : retour en recherche
create or replace function telima.driver_release_delivery(p_delivery_id uuid, p_reason text)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or v_del.driver_id is distinct from v_uid then
    raise exception 'Course introuvable' using errcode = 'P0002';
  end if;
  if v_del.status not in ('assigned', 'to_pickup', 'at_pickup') then
    raise exception 'Impossible d''abandonner après récupération du colis' using errcode = 'P0001';
  end if;
  perform set_config('telima.status_note', 'Abandon livreur : ' || coalesce(p_reason, ''), true);
  update telima.deliveries set driver_id = null, vehicle_id = null, status = 'searching', assigned_at = null,
         eta_minutes = null, near_notified = false, searching_at = now()
   where (id = p_delivery_id or (v_del.batch_id is not null and batch_id = v_del.batch_id))
     and status in ('assigned', 'to_pickup', 'at_pickup')
     and driver_id = v_uid;
  update telima.deliveries set status = 'created'
   where v_del.batch_id is not null and batch_id = v_del.batch_id and stop_order > 1 and status = 'searching';
  insert into telima.delivery_declines(delivery_id, driver_id) values (p_delivery_id, v_uid) on conflict do nothing;
  select * into v_del from telima.deliveries where id = p_delivery_id;
  perform telima.notify_nearby_drivers(v_del);
  perform telima.notify_staff('driver_release', 'Course abandonnée', v_del.code || ' : ' || coalesce(p_reason, ''),
                              jsonb_build_object('delivery_id', v_del.id));
  return v_del;
end $$;

-- Position GPS du livreur (limitée en fréquence côté serveur)
create or replace function telima.driver_update_location(p_lat double precision, p_lng double precision,
                                                         p_heading double precision default null, p_speed double precision default null)
returns void language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_min_interval int := coalesce((telima.get_setting('location_min_interval_s', '10'))::text::int, 10);
  v_near_km numeric := coalesce((telima.get_setting('near_pickup_km', '0.5'))::text::numeric, 0.5);
  v_del record;
  v_last timestamptz;
begin
  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then
    raise exception 'Position invalide' using errcode = '22023';
  end if;
  update telima.drivers set current_lat = p_lat, current_lng = p_lng, last_location_at = now()
   where user_id = v_uid;
  if not found then raise exception 'Profil livreur introuvable' using errcode = 'P0002'; end if;

  for v_del in select * from telima.deliveries
                where driver_id = v_uid and status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff')
  loop
    select max(recorded_at) into v_last from telima.delivery_locations where delivery_id = v_del.id;
    if v_last is null or v_last < now() - make_interval(secs => v_min_interval) then
      insert into telima.delivery_locations(delivery_id, driver_id, lat, lng, heading, speed)
      values (v_del.id, v_uid, p_lat, p_lng, p_heading, p_speed);
    end if;
    if v_del.status = 'to_pickup' and not v_del.near_notified and v_del.stop_order = 1
       and telima.haversine_km(p_lat, p_lng, v_del.pickup_lat, v_del.pickup_lng) <= v_near_km then
      update telima.deliveries set near_notified = true where id = v_del.id;
      perform telima.notify_user(v_del.customer_id, 'driver_near', v_del.code,
                                 'Votre livreur arrive dans quelques minutes.', jsonb_build_object('delivery_id', v_del.id));
    end if;
  end loop;
end $$;

-- Preuve de livraison + clôture + règlement financier
create or replace function telima.complete_delivery(
  p_delivery_id uuid, p_otp text default null, p_receiver_name text default null,
  p_photo_path text default null, p_signature_path text default null,
  p_lat double precision default null, p_lng double precision default null)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_del telima.deliveries;
  v_secret telima.delivery_secrets;
  v_mode text := coalesce(telima.get_setting('proof_mode', '"otp"') #>> '{}', 'otp');
  v_max int := coalesce((telima.get_setting('otp_max_attempts', '5'))::text::int, 5);
  v_proof telima.proof_type;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or (v_del.driver_id is distinct from v_uid and not telima.is_staff()) then
    raise exception 'Course introuvable' using errcode = 'P0002';
  end if;
  if v_del.status not in ('in_transit', 'at_dropoff') then
    raise exception 'La livraison ne peut pas être terminée à cette étape' using errcode = 'P0001';
  end if;

  select * into v_secret from telima.delivery_secrets where delivery_id = p_delivery_id for update;
  if p_otp is not null and p_otp <> '' then
    if v_secret.locked then
      raise exception 'Code bloqué après trop d''essais. Contactez le support.' using errcode = 'P0001';
    end if;
    if v_secret.otp_code <> trim(p_otp) then
      update telima.delivery_secrets set attempts = attempts + 1, locked = (attempts + 1 >= v_max)
       where delivery_id = p_delivery_id;
      -- on valide l'incrément malgré l'erreur grâce à un retour sans exception
      return null;
    end if;
    v_proof := 'otp';
  elsif v_mode = 'otp' and not telima.is_staff() then
    raise exception 'Code de livraison requis' using errcode = 'P0001';
  elsif p_photo_path is not null then
    v_proof := 'photo';
  elsif p_signature_path is not null then
    v_proof := 'signature';
  elsif coalesce(trim(p_receiver_name), '') <> '' then
    v_proof := 'name';
  else
    raise exception 'Une preuve de livraison est requise' using errcode = 'P0001';
  end if;

  perform set_config('telima.status_lat', coalesce(p_lat::text, ''), true);
  perform set_config('telima.status_lng', coalesce(p_lng::text, ''), true);

  update telima.deliveries set status = 'handed_over', delivered_at = now(), proof_type = v_proof,
         receiver_name = nullif(trim(p_receiver_name), ''), proof_photo_path = p_photo_path,
         proof_signature_path = p_signature_path
   where id = p_delivery_id;
  update telima.deliveries set status = 'completed', completed_at = now()
   where id = p_delivery_id returning * into v_del;

  -- Règlement
  if v_del.payment_method in ('cash', 'cash_on_delivery') then
    update telima.payments set status = 'paid', paid_at = now(), provider = 'cash'
     where delivery_id = v_del.id and status = 'pending';
    update telima.deliveries set payment_status = 'paid' where id = v_del.id returning * into v_del;
    if v_del.commission_amount > 0 and v_del.driver_id is not null then
      perform telima.wallet_apply(v_del.driver_id, 'commission', -v_del.commission_amount, v_del.id, null,
                                  'Commission plateforme ' || v_del.code || ' (espèces encaissées : ' || v_del.total_price || ' FCFA)', true);
    end if;
  elsif v_del.payment_status = 'paid' and v_del.driver_id is not null then
    perform telima.wallet_apply(v_del.driver_id, 'earning', v_del.driver_earning, v_del.id, null,
                                'Gain course ' || v_del.code);
  end if;

  update telima.drivers set total_deliveries = total_deliveries + 1 where user_id = v_del.driver_id;
  update telima.customers set total_deliveries = total_deliveries + 1 where user_id = v_del.customer_id;
  return v_del;
end $$;

-- Annulation (client avant récupération, personnel à tout moment avant clôture)
create or replace function telima.cancel_delivery(p_delivery_id uuid, p_reason text)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries; v_staff boolean := telima.is_staff();
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or (v_del.customer_id is distinct from v_uid and not v_staff) then
    raise exception 'Livraison introuvable' using errcode = 'P0002';
  end if;
  if v_del.status in ('completed', 'cancelled', 'handed_over') then
    raise exception 'Cette livraison ne peut plus être annulée' using errcode = 'P0001';
  end if;
  if not v_staff and v_del.status not in ('created', 'searching', 'assigned', 'to_pickup', 'at_pickup') then
    raise exception 'Le colis a déjà été récupéré : contactez le support pour annuler' using errcode = 'P0001';
  end if;

  perform set_config('telima.status_note', coalesce(p_reason, ''), true);
  update telima.deliveries set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid,
         cancel_reason = nullif(trim(p_reason), '')
   where id = p_delivery_id returning * into v_del;

  -- Remboursement des paiements anticipés vers le portefeuille interne
  if v_del.payment_status = 'paid' and v_del.customer_id is not null then
    perform telima.wallet_apply(v_del.customer_id, 'refund', v_del.total_price, v_del.id, null,
                                'Remboursement ' || v_del.code);
    update telima.payments set status = 'refunded' where delivery_id = v_del.id and status = 'paid';
    update telima.deliveries set payment_status = 'refunded' where id = v_del.id returning * into v_del;
  else
    update telima.payments set status = 'cancelled' where delivery_id = v_del.id and status = 'pending';
    update telima.deliveries set payment_status = 'cancelled' where id = v_del.id returning * into v_del;
  end if;

  if v_staff then
    perform telima.log_admin_action('cancel_delivery', 'deliveries', v_del.id::text, jsonb_build_object('code', v_del.code, 'reason', p_reason));
  end if;
  return v_del;
end $$;

-- ---------------------------------------------------------------------
-- Informations visibles par le client
-- ---------------------------------------------------------------------
create or replace function telima.can_access_delivery(p_delivery_id uuid)
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (
    select 1 from telima.deliveries d
     where d.id = p_delivery_id
       and (d.customer_id = auth.uid() or d.driver_id = auth.uid() or telima.is_staff()
            or (d.business_id is not null and exists (
                  select 1 from telima.business_members m where m.business_id = d.business_id and m.user_id = auth.uid())))
  )
$$;

create or replace function telima.get_delivery_driver(p_delivery_id uuid)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_res jsonb;
begin
  if not telima.can_access_delivery(p_delivery_id) then
    raise exception 'Livraison introuvable' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
           'driver_id', u.id,
           'first_name', split_part(u.full_name, ' ', 1),
           'full_name', u.full_name,
           'phone', u.phone,
           'avatar_url', u.avatar_url,
           'rating_avg', d.rating_avg,
           'rating_count', d.rating_count,
           'vehicle_type', v.type,
           'vehicle_label', concat_ws(' ', v.brand, v.model, v.color),
           'plate_number', v.plate_number,
           'lat', d.current_lat,
           'lng', d.current_lng,
           'last_location_at', d.last_location_at,
           'eta_minutes', del.eta_minutes)
    into v_res
    from telima.deliveries del
    join telima.users u on u.id = del.driver_id
    join telima.drivers d on d.user_id = del.driver_id
    left join telima.vehicles v on v.id = del.vehicle_id
   where del.id = p_delivery_id
     and del.status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff', 'handed_over', 'completed');
  return v_res;
end $$;

create or replace function telima.get_delivery_otp(p_delivery_id uuid)
returns text language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id;
  if v_del.id is null or v_del.driver_id = v_uid
     or not (v_del.customer_id = v_uid or telima.is_staff()
             or (v_del.business_id is not null and exists (select 1 from telima.business_members m
                   where m.business_id = v_del.business_id and m.user_id = v_uid))) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return (select otp_code from telima.delivery_secrets where delivery_id = p_delivery_id);
end $$;

-- ---------------------------------------------------------------------
-- Évaluations
-- ---------------------------------------------------------------------
create or replace function telima.rate_delivery(p_delivery_id uuid, p_stars int, p_comment text default null)
returns telima.ratings language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries; v_rating telima.ratings;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id;
  if v_del.id is null or v_del.customer_id is distinct from v_uid then
    raise exception 'Livraison introuvable' using errcode = 'P0002';
  end if;
  if v_del.status <> 'completed' or v_del.driver_id is null then
    raise exception 'Vous pourrez noter la livraison une fois terminée' using errcode = 'P0001';
  end if;
  if p_stars not between 1 and 5 then raise exception 'Note entre 1 et 5' using errcode = '22023'; end if;
  insert into telima.ratings(delivery_id, customer_id, driver_id, stars, comment)
  values (p_delivery_id, v_uid, v_del.driver_id, p_stars, nullif(trim(p_comment), ''))
  on conflict (delivery_id) do update set stars = excluded.stars, comment = excluded.comment
  returning * into v_rating;
  return v_rating;
end $$;

create or replace function telima.tg_ratings_refresh_driver()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_driver uuid := coalesce(new.driver_id, old.driver_id);
begin
  update telima.drivers d set
    rating_avg = coalesce((select round(avg(stars)::numeric, 2) from telima.ratings where driver_id = v_driver), 0),
    rating_count = (select count(*) from telima.ratings where driver_id = v_driver)
  where d.user_id = v_driver;
  return null;
end $$;
create trigger trg_ratings_refresh after insert or update or delete on telima.ratings
  for each row execute function telima.tg_ratings_refresh_driver();

-- ---------------------------------------------------------------------
-- Revenus et retraits du livreur
-- ---------------------------------------------------------------------
create or replace function telima.get_driver_earnings()
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_tz text := 'Africa/Ouagadougou';
  v_today timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_week timestamptz := date_trunc('week', now() at time zone v_tz) at time zone v_tz;
  v_month timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
begin
  return (
    select jsonb_build_object(
      'today', coalesce(sum(driver_earning) filter (where completed_at >= v_today), 0),
      'week', coalesce(sum(driver_earning) filter (where completed_at >= v_week), 0),
      'month', coalesce(sum(driver_earning) filter (where completed_at >= v_month), 0),
      'count_today', count(*) filter (where completed_at >= v_today),
      'count_week', count(*) filter (where completed_at >= v_week),
      'count_month', count(*) filter (where completed_at >= v_month),
      'count_total', count(*),
      'commission_month', coalesce(sum(commission_amount) filter (where completed_at >= v_month), 0),
      'commission_total', coalesce(sum(commission_amount), 0),
      'earning_total', coalesce(sum(driver_earning), 0),
      'balance', coalesce((select balance from telima.wallets where user_id = v_uid), 0),
      'pending_withdrawals', coalesce((select sum(amount) from telima.withdrawals where user_id = v_uid and status = 'pending'), 0)
    )
    from telima.deliveries where driver_id = v_uid and status = 'completed'
  );
end $$;

create or replace function telima.request_withdrawal(p_amount integer, p_method telima.payment_method, p_phone text)
returns telima.withdrawals language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_min int := coalesce((telima.get_setting('withdrawal_min', '1000'))::text::int, 1000);
  v_wallet uuid := telima.ensure_wallet(v_uid);
  v_wd telima.withdrawals;
begin
  if not exists (select 1 from telima.drivers where user_id = v_uid and status = 'approved') then
    raise exception 'Retraits réservés aux livreurs approuvés' using errcode = '42501';
  end if;
  if p_amount < v_min then raise exception 'Montant minimum : % FCFA', v_min using errcode = '22023'; end if;
  if p_method not in ('orange_money', 'moov_money', 'cash') then
    raise exception 'Moyen de retrait invalide' using errcode = '22023';
  end if;
  insert into telima.withdrawals(wallet_id, user_id, amount, method, phone)
  values (v_wallet, v_uid, p_amount, p_method, telima.normalize_phone(p_phone)) returning * into v_wd;
  perform telima.wallet_apply(v_uid, 'withdrawal', -p_amount, null, v_wd.id, 'Demande de retrait ' || p_method::text);
  perform telima.notify_staff('withdrawal', 'Demande de retrait', p_amount || ' FCFA', jsonb_build_object('withdrawal_id', v_wd.id));
  return v_wd;
end $$;

-- ---------------------------------------------------------------------
-- Comptes professionnels
-- ---------------------------------------------------------------------
create or replace function telima.create_business_account(p jsonb)
returns telima.business_accounts language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_b telima.business_accounts;
begin
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'Nom obligatoire' using errcode = '22023'; end if;
  insert into telima.business_accounts(name, type, owner_id, phone, address, lat, lng, city_id)
  values (trim(p->>'name'), coalesce(nullif(p->>'type', ''), 'boutique')::telima.business_type, v_uid,
          case when coalesce(p->>'phone', '') <> '' then telima.normalize_phone(p->>'phone') end,
          nullif(p->>'address', ''), nullif(p->>'lat', '')::float8, nullif(p->>'lng', '')::float8,
          nullif(p->>'city_id', '')::uuid)
  returning * into v_b;
  insert into telima.business_members(business_id, user_id, role) values (v_b.id, v_uid, 'owner');
  return v_b;
end $$;

create or replace function telima.add_business_member(p_business_id uuid, p_phone text, p_role telima.member_role default 'member')
returns telima.business_members language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_user uuid; v_m telima.business_members;
begin
  if not exists (select 1 from telima.business_members where business_id = p_business_id and user_id = v_uid and role in ('owner', 'manager')) then
    raise exception 'Seul le propriétaire ou un gérant peut ajouter des membres' using errcode = '42501';
  end if;
  if p_role = 'owner' then raise exception 'Rôle invalide' using errcode = '22023'; end if;
  select id into v_user from telima.users where phone = telima.normalize_phone(p_phone) and is_active;
  if v_user is null then raise exception 'Aucun compte avec ce numéro' using errcode = 'P0002'; end if;
  insert into telima.business_members(business_id, user_id, role) values (p_business_id, v_user, p_role)
  on conflict (business_id, user_id) do update set role = excluded.role returning * into v_m;
  return v_m;
end $$;

create or replace function telima.get_business_summary(p_business_id uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if not exists (select 1 from telima.business_members where business_id = p_business_id and user_id = v_uid) and not telima.is_staff() then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return (select jsonb_build_object(
            'count', count(*),
            'completed', count(*) filter (where status = 'completed'),
            'cancelled', count(*) filter (where status = 'cancelled'),
            'active', count(*) filter (where status not in ('completed', 'cancelled')),
            'spent', coalesce(sum(total_price) filter (where status = 'completed'), 0))
          from telima.deliveries
         where business_id = p_business_id and created_at >= p_from and created_at < p_to);
end $$;

-- ---------------------------------------------------------------------
-- Récupération de compte (code par SMS — simulation tant qu'aucun fournisseur SMS)
-- ---------------------------------------------------------------------
create or replace function telima.request_password_reset(p_phone text)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare
  v_phone text := telima.normalize_phone(p_phone);
  v_user telima.users;
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_sim boolean := coalesce(telima.get_setting('sms_mode', '"simulation"') #>> '{}', 'simulation') = 'simulation';
begin
  select * into v_user from telima.users where phone = v_phone;
  -- réponse identique que le compte existe ou non (pas de fuite d'information)
  if v_user.id is not null and v_user.is_active then
    if (select count(*) from telima.password_reset_requests
         where user_id = v_user.id and created_at > now() - interval '1 hour') >= 3 then
      raise exception 'Trop de demandes. Réessayez dans une heure.' using errcode = 'P0001';
    end if;
    insert into telima.password_reset_requests(user_id, phone, code_hash, code_plain, expires_at)
    values (v_user.id, v_phone, extensions.crypt(v_code, extensions.gen_salt('bf')), case when v_sim then v_code end, now() + interval '30 minutes');
    if v_sim then
      perform telima.notify_staff('password_reset', 'Demande de récupération de compte',
        v_user.full_name || ' (' || v_phone || ') — code : ' || v_code, jsonb_build_object('user_id', v_user.id));
    end if;
  end if;
  return jsonb_build_object('sent', true, 'simulation', v_sim);
end $$;

-- Utilisée UNIQUEMENT par la fonction Edge reset-password (service_role)
create or replace function telima.consume_password_reset(p_phone text, p_code text)
returns uuid language plpgsql security definer set search_path = telima, public as $$
declare v_req telima.password_reset_requests;
begin
  select * into v_req from telima.password_reset_requests
   where phone = telima.normalize_phone(p_phone) and used_at is null and expires_at > now()
   order by created_at desc limit 1 for update;
  if v_req.id is null then raise exception 'Code expiré ou invalide' using errcode = 'P0001'; end if;
  if v_req.attempts >= 5 then raise exception 'Trop d''essais' using errcode = 'P0001'; end if;
  if v_req.code_hash <> extensions.crypt(trim(p_code), v_req.code_hash) then
    update telima.password_reset_requests set attempts = attempts + 1 where id = v_req.id;
    return null;
  end if;
  update telima.password_reset_requests set used_at = now(), code_plain = null where id = v_req.id;
  return v_req.user_id;
end $$;

-- ---------------------------------------------------------------------
-- Administration
-- ---------------------------------------------------------------------
create or replace function telima.admin_create_delivery(p jsonb)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_staff();
  v_phone text := telima.normalize_phone(p->>'customer_phone');
  v_name text := coalesce(nullif(trim(p->>'customer_name'), ''), 'Client');
  v_customer uuid;
  v_row telima.deliveries;
begin
  select id into v_customer from telima.users where phone = v_phone and is_active;
  if (p->>'payment_method') = 'wallet' and v_customer is null then
    raise exception 'Ce client n''a pas de portefeuille' using errcode = 'P0001';
  end if;
  v_row := telima._insert_delivery(p, v_customer, v_name, v_phone, v_uid, 'admin', null, 1, false, null, null,
                                   nullif(p->>'price_override', '')::int);
  -- commande téléphonique : paiement Mobile Money encaissé hors application
  if v_row.status = 'created' then
    update telima.deliveries set status = 'searching', searching_at = now() where id = v_row.id returning * into v_row;
  end if;
  perform telima.log_admin_action('create_delivery', 'deliveries', v_row.id::text,
                                  jsonb_build_object('code', v_row.code, 'customer_phone', v_phone));
  if nullif(p->>'driver_id', '') is not null then
    v_row := telima.admin_assign_delivery(v_row.id, (p->>'driver_id')::uuid);
  else
    perform telima.notify_nearby_drivers(v_row);
  end if;
  return v_row;
end $$;

create or replace function telima.admin_assign_delivery(p_delivery_id uuid, p_driver_id uuid)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_staff();
  v_del telima.deliveries;
  v_vehicle telima.vehicles;
  v_old uuid;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null then raise exception 'Livraison introuvable' using errcode = 'P0002'; end if;
  if v_del.status not in ('created', 'searching', 'assigned', 'to_pickup', 'at_pickup') then
    raise exception 'Attribution impossible à l''étape %', v_del.status using errcode = 'P0001';
  end if;
  if not exists (select 1 from telima.drivers where user_id = p_driver_id and status = 'approved') then
    raise exception 'Livreur non approuvé' using errcode = 'P0001';
  end if;
  select * into v_vehicle from telima.vehicles where driver_id = p_driver_id and is_active;
  if v_vehicle.id is null then raise exception 'Ce livreur n''a pas de véhicule actif' using errcode = 'P0001'; end if;
  v_old := v_del.driver_id;

  update telima.deliveries set driver_id = p_driver_id, vehicle_id = v_vehicle.id, status = 'assigned',
         assigned_at = now(), near_notified = false, searching_at = coalesce(searching_at, now())
   where (id = p_delivery_id or (v_del.batch_id is not null and batch_id = v_del.batch_id
                                  and status in ('created', 'searching', 'assigned', 'to_pickup', 'at_pickup')))
  ;
  select * into v_del from telima.deliveries where id = p_delivery_id;
  if v_del.batch_id is not null then
    update telima.delivery_batches set driver_id = p_driver_id where id = v_del.batch_id;
  end if;

  perform telima.notify_user(p_driver_id, 'assigned_by_admin', 'Nouvelle course attribuée',
                             v_del.code || ' : ' || v_del.pickup_address || ' → ' || v_del.dropoff_address,
                             jsonb_build_object('delivery_id', v_del.id));
  if v_old is not null and v_old <> p_driver_id then
    perform telima.notify_user(v_old, 'unassigned', 'Course réattribuée', v_del.code || ' a été confiée à un autre livreur.',
                               jsonb_build_object('delivery_id', v_del.id));
  end if;
  perform telima.log_admin_action('assign_delivery', 'deliveries', v_del.id::text,
                                  jsonb_build_object('code', v_del.code, 'driver_id', p_driver_id, 'previous_driver_id', v_old));
  return v_del;
end $$;

create or replace function telima.admin_set_driver_status(p_driver_id uuid, p_status telima.driver_status, p_note text default null)
returns telima.drivers language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff(); v_drv telima.drivers;
begin
  update telima.drivers set status = p_status, status_note = p_note,
         is_online = case when p_status = 'approved' then is_online else false end,
         approved_at = case when p_status = 'approved' then now() else approved_at end,
         approved_by = case when p_status = 'approved' then v_uid else approved_by end
   where user_id = p_driver_id returning * into v_drv;
  if v_drv.user_id is null then raise exception 'Livreur introuvable' using errcode = 'P0002'; end if;
  update telima.users set role = 'driver' where id = p_driver_id and role = 'client';
  perform telima.notify_user(p_driver_id, 'driver_status',
    case p_status when 'approved' then 'Compte livreur approuvé'
                  when 'suspended' then 'Compte livreur suspendu'
                  when 'rejected' then 'Inscription livreur refusée'
                  else 'Compte livreur en attente' end,
    coalesce(p_note, case p_status when 'approved' then 'Vous pouvez passer EN LIGNE et recevoir des courses.' else '' end));
  perform telima.log_admin_action('set_driver_status', 'drivers', p_driver_id::text,
                                  jsonb_build_object('status', p_status, 'note', p_note));
  return v_drv;
end $$;

create or replace function telima.admin_set_user_active(p_user_id uuid, p_active boolean)
returns telima.users language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_u telima.users;
begin
  if p_user_id = v_uid then raise exception 'Vous ne pouvez pas désactiver votre propre compte' using errcode = 'P0001'; end if;
  update telima.users set is_active = p_active, deactivated_at = case when p_active then null else now() end
   where id = p_user_id returning * into v_u;
  if not p_active then update telima.drivers set is_online = false where user_id = p_user_id; end if;
  perform telima.log_admin_action(case when p_active then 'activate_user' else 'deactivate_user' end, 'users', p_user_id::text);
  return v_u;
end $$;

create or replace function telima.admin_set_user_role(p_user_id uuid, p_role telima.user_role)
returns telima.users language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_u telima.users;
begin
  if p_user_id = v_uid and p_role <> 'admin' then
    raise exception 'Vous ne pouvez pas retirer votre propre rôle administrateur' using errcode = 'P0001';
  end if;
  update telima.users set role = p_role where id = p_user_id returning * into v_u;
  if p_role = 'driver' then insert into telima.drivers(user_id, city_id) values (p_user_id, v_u.city_id) on conflict do nothing; end if;
  perform telima.log_admin_action('set_user_role', 'users', p_user_id::text, jsonb_build_object('role', p_role));
  return v_u;
end $$;

create or replace function telima.admin_process_withdrawal(p_withdrawal_id uuid, p_approve boolean,
                                                           p_provider_ref text default null, p_note text default null)
returns telima.withdrawals language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_wd telima.withdrawals;
begin
  select * into v_wd from telima.withdrawals where id = p_withdrawal_id for update;
  if v_wd.id is null then raise exception 'Retrait introuvable' using errcode = 'P0002'; end if;
  if v_wd.status <> 'pending' then raise exception 'Retrait déjà traité' using errcode = 'P0001'; end if;
  update telima.withdrawals set status = case when p_approve then 'paid' else 'rejected' end::telima.withdrawal_status,
         provider_ref = p_provider_ref, note = p_note, processed_by = v_uid, processed_at = now()
   where id = p_withdrawal_id returning * into v_wd;
  if not p_approve then
    perform telima.wallet_apply(v_wd.user_id, 'withdrawal_refund', v_wd.amount, null, v_wd.id, 'Retrait refusé : ' || coalesce(p_note, ''));
  end if;
  perform telima.notify_user(v_wd.user_id, 'withdrawal',
    case when p_approve then 'Retrait effectué' else 'Retrait refusé' end,
    v_wd.amount || ' FCFA' || coalesce(' — ' || p_note, ''), jsonb_build_object('withdrawal_id', v_wd.id));
  perform telima.log_admin_action(case when p_approve then 'withdrawal_paid' else 'withdrawal_rejected' end,
                                  'withdrawals', v_wd.id::text, jsonb_build_object('amount', v_wd.amount, 'ref', p_provider_ref));
  return v_wd;
end $$;

create or replace function telima.admin_wallet_adjust(p_user_id uuid, p_amount integer, p_description text)
returns integer language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_balance int;
begin
  if coalesce(trim(p_description), '') = '' then raise exception 'Motif obligatoire' using errcode = '22023'; end if;
  v_balance := telima.wallet_apply(p_user_id, case when p_amount > 0 then 'topup' else 'adjustment' end::telima.wallet_tx_type,
                                   p_amount, null, null, 'Ajustement admin : ' || p_description, true);
  perform telima.log_admin_action('wallet_adjust', 'wallets', p_user_id::text,
                                  jsonb_build_object('amount', p_amount, 'description', p_description));
  return v_balance;
end $$;

create or replace function telima.admin_confirm_payment(p_payment_id uuid, p_provider_ref text)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_pay telima.payments;
begin
  v_pay := telima._confirm_payment(p_payment_id, p_provider_ref);
  perform telima.log_admin_action('confirm_payment', 'payments', p_payment_id::text, jsonb_build_object('ref', p_provider_ref));
  return v_pay;
end $$;

create or replace function telima.admin_dashboard_stats(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff();
begin
  return jsonb_build_object(
    'clients', (select count(*) from telima.users where role = 'client' and is_active),
    'drivers', (select count(*) from telima.drivers d join telima.users u on u.id = d.user_id where u.is_active and d.status = 'approved'),
    'drivers_pending', (select count(*) from telima.drivers where status = 'pending'),
    'drivers_online', (select count(*) from telima.drivers where is_online and status = 'approved'),
    'orders', (select count(*) from telima.deliveries where created_at >= p_from and created_at < p_to),
    'orders_active', (select count(*) from telima.deliveries where status not in ('completed', 'cancelled')),
    'orders_searching', (select count(*) from telima.deliveries where status in ('created', 'searching')),
    'completed', (select count(*) from telima.deliveries where status = 'completed' and completed_at >= p_from and completed_at < p_to),
    'cancelled', (select count(*) from telima.deliveries where status = 'cancelled' and cancelled_at >= p_from and cancelled_at < p_to),
    'revenue', (select coalesce(sum(total_price), 0) from telima.deliveries where status = 'completed' and completed_at >= p_from and completed_at < p_to),
    'commissions', (select coalesce(sum(commission_amount), 0) from telima.deliveries where status = 'completed' and completed_at >= p_from and completed_at < p_to),
    'payments', (select coalesce(sum(amount), 0) from telima.payments where status = 'paid' and paid_at >= p_from and paid_at < p_to),
    'payments_by_method', (select coalesce(jsonb_object_agg(method, total), '{}'::jsonb) from (
        select method::text, sum(amount) total from telima.payments where status = 'paid' and paid_at >= p_from and paid_at < p_to group by method) s),
    'withdrawals_paid', (select coalesce(sum(amount), 0) from telima.withdrawals where status = 'paid' and processed_at >= p_from and processed_at < p_to),
    'withdrawals_pending', (select coalesce(sum(amount), 0) from telima.withdrawals where status = 'pending'),
    'withdrawals_pending_count', (select count(*) from telima.withdrawals where status = 'pending'),
    'support_open', (select count(*) from telima.support_requests where status <> 'closed')
  );
end $$;

create or replace function telima.admin_daily_stats(p_days int default 14)
returns table(day date, orders bigint, completed bigint, cancelled bigint, revenue bigint, commissions bigint)
language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff();
begin
  return query
  with days as (
    select generate_series((now() at time zone 'Africa/Ouagadougou')::date - (greatest(p_days, 1) - 1),
                           (now() at time zone 'Africa/Ouagadougou')::date, interval '1 day')::date as day
  )
  select d.day,
         (select count(*) from telima.deliveries x where (x.created_at at time zone 'Africa/Ouagadougou')::date = d.day),
         (select count(*) from telima.deliveries x where x.status = 'completed' and (x.completed_at at time zone 'Africa/Ouagadougou')::date = d.day),
         (select count(*) from telima.deliveries x where x.status = 'cancelled' and (x.cancelled_at at time zone 'Africa/Ouagadougou')::date = d.day),
         (select coalesce(sum(x.total_price), 0)::bigint from telima.deliveries x where x.status = 'completed' and (x.completed_at at time zone 'Africa/Ouagadougou')::date = d.day),
         (select coalesce(sum(x.commission_amount), 0)::bigint from telima.deliveries x where x.status = 'completed' and (x.completed_at at time zone 'Africa/Ouagadougou')::date = d.day)
    from days d order by d.day;
end $$;

-- Livreurs pour l'écran d'attribution manuelle (avec distance au point de récupération)
create or replace function telima.admin_list_assignable_drivers(p_delivery_id uuid)
returns table(driver_id uuid, full_name text, phone text, is_online boolean, vehicle_type telima.vehicle_type,
              plate_number text, rating_avg numeric, distance_km numeric, busy boolean)
language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id;
  return query
    select d.user_id, u.full_name, u.phone, d.is_online, v.type, v.plate_number, d.rating_avg,
           case when d.current_lat is null then null
                else round(telima.haversine_km(d.current_lat, d.current_lng, v_del.pickup_lat, v_del.pickup_lng)::numeric, 2) end,
           exists (select 1 from telima.deliveries x where x.driver_id = d.user_id and x.id <> p_delivery_id
                     and x.status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff')
                     and (v_del.batch_id is null or x.batch_id is distinct from v_del.batch_id))
      from telima.drivers d
      join telima.users u on u.id = d.user_id and u.is_active
      join telima.vehicles v on v.driver_id = d.user_id and v.is_active
     where d.status = 'approved'
     order by d.is_online desc, 8 asc nulls last, u.full_name;
end $$;

-- Journalisation automatique des modifications de configuration
create or replace function telima.tg_admin_config_log()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if auth.uid() is not null then
    insert into telima.admin_logs(admin_id, action, entity, entity_id, details)
    values (auth.uid(), lower(tg_op), tg_table_name,
            coalesce((case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'id',
                     (case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'key'),
            case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end);
  end if;
  return null;
end $$;
create trigger trg_log_pricing after insert or update or delete on telima.pricing_rules
  for each row execute function telima.tg_admin_config_log();
create trigger trg_log_cities after insert or update or delete on telima.cities
  for each row execute function telima.tg_admin_config_log();
create trigger trg_log_zones after insert or update or delete on telima.delivery_zones
  for each row execute function telima.tg_admin_config_log();
create trigger trg_log_settings after insert or update or delete on telima.app_settings
  for each row execute function telima.tg_admin_config_log();

-- ---------------------------------------------------------------------
-- Historique des statuts + notifications au client (déclencheurs)
-- ---------------------------------------------------------------------
create or replace function telima.tg_delivery_status_change()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare
  v_lat float8 := nullif(current_setting('telima.status_lat', true), '')::float8;
  v_lng float8 := nullif(current_setting('telima.status_lng', true), '')::float8;
  v_note text := nullif(current_setting('telima.status_note', true), '');
  v_body text;
begin
  if tg_op = 'INSERT' then
    insert into telima.delivery_status_history(delivery_id, status, changed_by, note)
    values (new.id, 'created', auth.uid(), null);
    if new.status <> 'created' then
      insert into telima.delivery_status_history(delivery_id, status, changed_by)
      values (new.id, new.status, auth.uid());
    end if;
    return null;
  end if;

  if new.status is distinct from old.status then
    insert into telima.delivery_status_history(delivery_id, status, changed_by, note, lat, lng)
    values (new.id, new.status, auth.uid(), v_note, v_lat, v_lng);

    v_body := case new.status
      when 'searching'   then case when old.status in ('assigned', 'to_pickup', 'at_pickup')
                                   then 'Le livreur s''est désisté. Nous recherchons un autre livreur.'
                                   else 'Recherche d''un livreur disponible…' end
      when 'assigned'    then 'Un livreur a accepté votre commande.'
      when 'to_pickup'   then 'Votre livreur est en route vers le point de récupération.'
      when 'at_pickup'   then 'Votre livreur est arrivé au point de récupération.'
      when 'picked_up'   then 'Votre colis a été récupéré.'
      when 'in_transit'  then 'Votre colis est en route.'
      when 'at_dropoff'  then 'Le livreur est arrivé à destination.'
      when 'completed'   then 'Livraison terminée.'
      when 'cancelled'   then 'Votre livraison a été annulée.'
      else null end;
    if v_body is not null and new.customer_id is not null
       and not (new.batch_id is not null and new.stop_order > 1 and new.status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up')) then
      perform telima.notify_user(new.customer_id, 'delivery_status', new.code, v_body,
                                 jsonb_build_object('delivery_id', new.id, 'status', new.status));
    end if;
    if new.status = 'cancelled' and new.driver_id is not null and new.cancelled_by is distinct from new.driver_id then
      perform telima.notify_user(new.driver_id, 'delivery_cancelled', new.code, 'La course a été annulée.',
                                 jsonb_build_object('delivery_id', new.id));
    end if;
  end if;
  return null;
end $$;
create trigger trg_delivery_status after insert or update of status on telima.deliveries
  for each row execute function telima.tg_delivery_status_change();

-- Notification au correspondant lors d'un nouveau message
create or replace function telima.tg_message_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_del telima.deliveries; v_target uuid;
begin
  select * into v_del from telima.deliveries where id = new.delivery_id;
  v_target := case when new.sender_id = v_del.driver_id then v_del.customer_id else v_del.driver_id end;
  if v_target is not null and v_target <> new.sender_id then
    perform telima.notify_user(v_target, 'message', 'Nouveau message · ' || v_del.code, left(new.body, 140),
                               jsonb_build_object('delivery_id', new.delivery_id));
  end if;
  return null;
end $$;
create trigger trg_message_notify after insert on telima.messages
  for each row execute function telima.tg_message_notify();
