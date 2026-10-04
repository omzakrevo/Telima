-- Migration appliquée sur le projet Supabase cloud : telima_02b4_driver

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
    return;
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
  if v_del.status = p_status then return v_del; end if;
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

  if v_del.batch_id is not null and p_status in ('to_pickup', 'at_pickup', 'picked_up') then
    update telima.deliveries set status = p_status,
           picked_up_at = case when p_status = 'picked_up' then now() else picked_up_at end
     where batch_id = v_del.batch_id and id <> v_del.id and driver_id = v_uid
       and telima.next_driver_status(status) = p_status;
  end if;
  return v_del;
end $$;

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
