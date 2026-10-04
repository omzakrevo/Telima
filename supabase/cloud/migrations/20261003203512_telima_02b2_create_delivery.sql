-- Migration appliquée sur le projet Supabase cloud : telima_02b2_create_delivery

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
