-- Migration appliquée sur le projet Supabase cloud : telima_08k_dispatch

create or replace function telima.notify_nearby_drivers(p_delivery telima.deliveries)
returns integer language plpgsql security definer set search_path = telima, public as $$
declare
  v_radius numeric := coalesce((telima.get_setting('dispatch_radius_km', '7'))::text::numeric, 7);
  v_count int;
begin
  insert into telima.notifications(user_id, type, title, body, data)
  select d.user_id, 'new_request',
         case p_delivery.kind when 'ride' then 'Nouveau passager 🚖' when 'errand' then 'Nouvelle course à faire 🛍️'
                              else 'Nouvelle demande de livraison' end,
         case p_delivery.kind
           when 'errand' then format('%s · livrer à %s · %s FCFA', left(coalesce(p_delivery.errand_items, ''), 80),
                                     p_delivery.dropoff_address, p_delivery.driver_earning)
           else format('%s → %s · %s FCFA', p_delivery.pickup_address, p_delivery.dropoff_address, p_delivery.driver_earning) end,
         jsonb_build_object('delivery_id', p_delivery.id)
    from telima.drivers d
    join telima.vehicles v on v.driver_id = d.user_id and v.is_active
    join telima.users u on u.id = d.user_id and u.is_active
   where d.is_online and d.status = 'approved'
     and telima.driver_can_take(d.services, v.type, p_delivery.kind, p_delivery.vehicle_type)
     and d.current_lat is not null
     and telima.haversine_km(d.current_lat, d.current_lng, p_delivery.pickup_lat, p_delivery.pickup_lng) <= v_radius;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

create or replace function telima.get_available_requests_v2()
returns table (
  id uuid, code text, kind text, vehicle_type telima.vehicle_type,
  pickup_address text, pickup_lat double precision, pickup_lng double precision,
  dropoff_address text, dropoff_lat double precision, dropoff_lng double precision,
  package_category telima.package_category, package_size telima.package_size, package_fragile boolean,
  package_quantity integer, distance_km numeric, total_price integer, driver_earning integer,
  payment_method telima.payment_method, distance_to_pickup_km numeric, stops_count integer,
  batch_total_earning integer, created_at timestamptz,
  errand_items text, errand_category text, errand_budget integer, ride_passengers integer)
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
    select d.id, d.code, d.kind, d.vehicle_type, d.pickup_address, d.pickup_lat, d.pickup_lng,
           d.dropoff_address, d.dropoff_lat, d.dropoff_lng, d.package_category, d.package_size, d.package_fragile,
           d.package_quantity, d.distance_km, d.total_price, d.driver_earning, d.payment_method,
           round(telima.haversine_km(v_drv.current_lat, v_drv.current_lng, d.pickup_lat, d.pickup_lng)::numeric, 2),
           coalesce(b.stops_count, 1),
           coalesce((select sum(x.driver_earning)::int from telima.deliveries x where x.batch_id = d.batch_id), d.driver_earning),
           d.created_at, d.errand_items, d.errand_category, d.errand_budget, d.ride_passengers
      from telima.deliveries d
      left join telima.delivery_batches b on b.id = d.batch_id
     where d.status = 'searching' and d.driver_id is null and d.stop_order = 1
       and telima.driver_can_take(v_drv.services, v_vehicle, d.kind, d.vehicle_type)
       and telima.haversine_km(v_drv.current_lat, v_drv.current_lng, d.pickup_lat, d.pickup_lng) <= v_radius
       and not exists (select 1 from telima.delivery_declines x where x.delivery_id = d.id and x.driver_id = v_uid)
     order by 19 asc, d.created_at asc
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
  if not telima.driver_can_take(v_drv.services, v_vehicle.type, v_del.kind, v_del.vehicle_type) then
    raise exception '%', case when v_del.kind = 'ride' then 'Activez le transport de personnes avec le bon véhicule pour accepter ce trajet'
                              else 'Votre véhicule ou vos services ne conviennent pas à cette demande' end using errcode = 'P0001';
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
