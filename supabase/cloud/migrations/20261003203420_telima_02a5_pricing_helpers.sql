-- Migration appliquée sur le projet Supabase cloud : telima_02a5_pricing_helpers

create or replace function telima.vehicle_rank(p telima.vehicle_type)
returns int language sql immutable as $$
  select case p when 'moto' then 1 when 'tricycle' then 2 when 'voiture' then 2 when 'utilitaire' then 3 end
$$;

create or replace function telima.suggest_vehicle(p_size telima.package_size, p_weight numeric, p_category telima.package_category)
returns telima.vehicle_type language sql immutable as $$
  select case
    when p_size = 'tres_grand' or coalesce(p_weight, 0) > 300 then 'utilitaire'::telima.vehicle_type
    when p_size = 'grand' or p_category = 'gros_colis' or coalesce(p_weight, 0) > 30 then 'tricycle'::telima.vehicle_type
    else 'moto'::telima.vehicle_type
  end
$$;

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

create trigger telima_on_auth_user_created after insert on auth.users
  for each row when (new.email like '%@telima.app')
  execute function telima.handle_new_auth_user();
