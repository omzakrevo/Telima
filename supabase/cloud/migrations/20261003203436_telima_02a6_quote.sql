-- Migration appliquée sur le projet Supabase cloud : telima_02a6_quote

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
  v_zone_fee := v_zone_fee + round(v_subtotal - (v_base + v_dist_price + v_extras))::int;
  v_total := telima.round_up_to(greatest(v_subtotal + coalesce(v_zone.extra_fee, 0),
                                         case when p_is_extra_stop then 0 else v_rule.min_price end), v_rounding);
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
