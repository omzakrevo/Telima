-- « Je suis sur place » : signalement vérifié par la position (moins de 300 m) de la file d'attente
-- et de la disponibilité, appliqué tout de suite et daté.
alter table telima.places add column queue_level text check (queue_level in ('none', 'short', 'medium', 'long')),
  add column queue_people integer, add column queue_wait_min integer, add column queue_at timestamptz;

create table telima.place_presence (
  id         uuid primary key default gen_random_uuid(),
  place_id   uuid not null references telima.places(id) on delete cascade,
  user_id    uuid not null references telima.users(id) on delete cascade,
  distance_m integer not null,
  queue      text check (queue in ('none', 'short', 'medium', 'long')),
  people     integer check (people between 0 and 500),
  wait_min   integer,
  fuels      jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index idx_place_presence_place on telima.place_presence(place_id, created_at desc);
alter table telima.place_presence enable row level security;
create policy place_presence_staff on telima.place_presence for select using (telima.is_staff() or user_id = auth.uid());
grant select on telima.place_presence to authenticated;

create or replace function telima.report_on_site(p_place_id uuid, p_lat double precision, p_lng double precision,
    p_queue text default null, p_people integer default null, p_fuels jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_place telima.places;
  v_dist numeric;
  v_wait integer;
  v_key text;
  v_val text;
  v_n integer := 0;
begin
  select * into v_place from telima.places where id = p_place_id and status = 'approved';
  if not found then raise exception 'Point introuvable' using errcode = 'P0002'; end if;
  if p_lat is null or p_lng is null then raise exception 'Activez la localisation pour signaler sur place' using errcode = '22023'; end if;
  v_dist := telima.haversine_km(p_lat, p_lng, v_place.lat, v_place.lng) * 1000;
  if v_dist > 300 then
    raise exception 'Vous êtes à % m : approchez-vous à moins de 300 m pour signaler sur place.', round(v_dist) using errcode = 'P0001';
  end if;
  if p_queue is not null and p_queue not in ('none', 'short', 'medium', 'long') then raise exception 'File invalide' using errcode = '22023'; end if;
  if p_people is not null and (p_people < 0 or p_people > 500) then raise exception 'Nombre de personnes invalide' using errcode = '22023'; end if;
  if exists (select 1 from telima.place_presence where user_id = v_uid and place_id = p_place_id and created_at > now() - interval '10 minutes') then
    raise exception 'Vous avez déjà signalé ce point il y a moins de 10 minutes' using errcode = 'P0001';
  end if;

  -- Attente estimée : environ 1,5 min par personne (station) ou 2 min (gaz), sinon selon la file
  v_wait := case
    when p_people is not null then ceil(p_people * case when v_place.kind = 'fuel_station' then 1.5 else 2 end)::int
    when p_queue = 'none' then 0 when p_queue = 'short' then 5 when p_queue = 'medium' then 15 when p_queue = 'long' then 35 end;
  if p_people is not null and p_queue is null then
    p_queue := case when p_people = 0 then 'none' when p_people <= 5 then 'short' when p_people <= 20 then 'medium' else 'long' end;
  end if;

  insert into telima.place_presence(place_id, user_id, distance_m, queue, people, wait_min, fuels)
  values (p_place_id, v_uid, round(v_dist), p_queue, p_people, v_wait, coalesce(p_fuels, '{}'::jsonb));

  if p_queue is not null then
    update telima.places set queue_level = p_queue, queue_people = p_people, queue_wait_min = v_wait, queue_at = now(), last_confirmed_at = now()
     where id = p_place_id;
  end if;

  -- Disponibilités : la présence sur place est vérifiée, l'information s'applique tout de suite
  for v_key, v_val in select key, value #>> '{}' from jsonb_each(coalesce(p_fuels, '{}'::jsonb)) loop
    continue when v_val not in ('available', 'low', 'out');
    if v_key in ('essence', 'gasoil') and v_place.kind = 'fuel_station' then
      insert into telima.place_fuels(place_id, fuel, availability, confirmed_at)
      values (p_place_id, v_key, v_val::telima.availability, now())
      on conflict (place_id, fuel) do update set availability = excluded.availability, confirmed_at = now(), updated_at = now();
    elsif v_key = 'gas' and v_place.kind = 'gas_point' then
      update telima.place_products set availability = v_val::telima.availability, confirmed_at = now(), track_stock = false where place_id = p_place_id;
    else
      continue;
    end if;
    insert into telima.place_reports(place_id, user_id, target, value, note) values (p_place_id, v_uid, v_key, v_val::telima.availability, 'sur place');
    v_n := v_n + 1;
  end loop;
  if v_n > 0 then update telima.places set last_confirmed_at = now() where id = p_place_id; end if;

  if v_place.owner_id is not null and v_place.owner_id <> v_uid and p_fuels ? 'gas' and p_fuels->>'gas' = 'out' then
    perform telima.notify_user(v_place.owner_id, 'stock_out', 'Rupture signalée', v_place.name || ' : une rupture a été signalée sur place.',
                               jsonb_build_object('place_id', p_place_id));
  end if;
  return jsonb_build_object('ok', true, 'distance_m', round(v_dist), 'wait_min', v_wait, 'queue', p_queue, 'updated', v_n);
end $$;
revoke all on function telima.report_on_site(uuid, double precision, double precision, text, integer, jsonb) from public, anon;
grant execute on function telima.report_on_site(uuid, double precision, double precision, text, integer, jsonb) to authenticated, service_role;

create or replace function telima.search_places(
  p_lat double precision, p_lng double precision,
  p_kind telima.place_kind default null, p_max_km numeric default 15,
  p_brand uuid default null, p_size numeric default null,
  p_only_available boolean default false, p_delivers boolean default false,
  p_query text default null, p_limit integer default 60)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_res jsonb;
begin
  select coalesce(jsonb_agg(r order by (r->>'distance_km')::numeric - 2 * coalesce((r->>'boost')::numeric, 0)), '[]'::jsonb) into v_res from (
    select jsonb_build_object(
      'id', p.id, 'kind', p.kind, 'name', p.name, 'brand_label', p.brand_label,
      'city_id', p.city_id, 'neighborhood', p.neighborhood, 'address', p.address,
      'lat', p.lat, 'lng', p.lng, 'phone', p.phone, 'opening_hours', p.opening_hours,
      'services', p.services, 'delivers', p.delivers, 'delivery_radius_km', p.delivery_radius_km,
      'last_confirmed_at', p.last_confirmed_at, 'rating_avg', p.rating_avg, 'rating_count', p.rating_count,
      'boost', telima.place_boost(p.id), 'promo_title', telima.place_promo_title(p.id), 'source', p.source,
      'queue_level', case when p.queue_at > now() - interval '2 hours' then p.queue_level end,
      'queue_people', case when p.queue_at > now() - interval '2 hours' then p.queue_people end,
      'queue_wait_min', case when p.queue_at > now() - interval '2 hours' then p.queue_wait_min end,
      'queue_at', case when p.queue_at > now() - interval '2 hours' then p.queue_at end,
      'distance_km', round(telima.haversine_km(p_lat, p_lng, p.lat, p.lng)::numeric, 2),
      'products', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', pr.id, 'brand_id', pr.brand_id, 'brand', b.name, 'size_kg', pr.size_kg, 'price', pr.price,
          'promo_price', telima.promo_price(pr.id), 'promo_title', telima.promo_title(pr.id),
          'availability', pr.availability, 'confirmed_at', pr.confirmed_at) order by pr.size_kg)
        from telima.place_products pr left join telima.gas_brands b on b.id = pr.brand_id
        where pr.place_id = p.id
          and (p_brand is null or pr.brand_id = p_brand)
          and (p_size is null or pr.size_kg = p_size)
          and (not p_only_available or pr.availability in ('available', 'low'))), '[]'::jsonb),
      'fuels', coalesce((
        select jsonb_agg(jsonb_build_object('fuel', f.fuel, 'availability', f.availability,
                                            'price', f.price, 'confirmed_at', f.confirmed_at))
        from telima.place_fuels f where f.place_id = p.id), '[]'::jsonb)
    ) as r
    from telima.places p
    where p.status = 'approved'
      and (p_kind is null or p.kind = p_kind)
      and (not p_delivers or p.delivers)
      and (p_query is null or p.name ilike '%' || p_query || '%' or p.neighborhood ilike '%' || p_query || '%'
           or p.address ilike '%' || p_query || '%' or p.brand_label ilike '%' || p_query || '%')
      and telima.haversine_km(p_lat, p_lng, p.lat, p.lng) <= p_max_km
      and (p.kind <> 'gas_point' or not (p_brand is not null or p_size is not null or p_only_available)
           or exists (select 1 from telima.place_products pr where pr.place_id = p.id
                      and (p_brand is null or pr.brand_id = p_brand)
                      and (p_size is null or pr.size_kg = p_size)
                      and (not p_only_available or pr.availability in ('available', 'low'))))
      and (p.kind <> 'fuel_station' or not (p_brand is not null or p_size is not null))
    order by telima.haversine_km(p_lat, p_lng, p.lat, p.lng) - 2 * telima.place_boost(p.id)
    limit greatest(1, least(coalesce(p_limit, 60), 200))
  ) t;
  return v_res;
end $$;
