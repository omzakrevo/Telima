-- Module « Gaz & carburant » : points de vente de gaz, stations-service, disponibilités,
-- signalements des utilisateurs, commandes de gaz (retrait ou livraison par un livreur Telima).
-- La livraison réutilise telima.deliveries : une commande de gaz livrée = une livraison ordinaire.

create type telima.availability as enum ('available', 'low', 'out', 'unknown');
create type telima.place_kind as enum ('gas_point', 'fuel_station');
create type telima.place_status as enum ('pending', 'approved', 'rejected', 'suspended');
create type telima.gas_order_status as enum
  ('sent', 'accepted', 'preparing', 'ready', 'out_for_delivery', 'delivered', 'rejected', 'cancelled');
create type telima.gas_payment_status as enum ('unpaid', 'pending', 'paid', 'failed', 'refunded');

-- ---------------------------------------------------------------------
-- Marques de gaz
-- ---------------------------------------------------------------------
create table telima.gas_brands (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique check (char_length(name) between 2 and 60),
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Points de vente de gaz et stations-service (une seule table, le type les distingue)
-- ---------------------------------------------------------------------
create table telima.places (
  id               uuid primary key default gen_random_uuid(),
  kind             telima.place_kind not null,
  name             text not null check (char_length(name) between 2 and 120),
  brand_label      text,                                       -- enseigne (Total, Oryx…)
  owner_id         uuid references telima.users(id) on delete set null,
  city_id          uuid references telima.cities(id) on delete set null,
  neighborhood     text,
  address          text,
  lat              double precision not null check (lat between -90 and 90),
  lng              double precision not null check (lng between -180 and 180),
  phone            text,
  opening_hours    text,
  services         text[] not null default '{}',               -- autres services (boutique, lavage…)
  delivers         boolean not null default false,
  delivery_radius_km numeric(5,1) not null default 5 check (delivery_radius_km >= 0),
  status           telima.place_status not null default 'pending',
  source           text not null default 'admin' check (source in ('admin', 'vendor', 'osm', 'community')),
  osm_id           text unique,
  last_confirmed_at timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index idx_places_kind_status on telima.places(kind, status);
create index idx_places_city on telima.places(city_id);
create index idx_places_owner on telima.places(owner_id);
create index idx_places_geo on telima.places(lat, lng);
create trigger trg_places_updated before update on telima.places
  for each row execute function telima.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Gaz : produits d'un point de vente, avec stock disponible / réservé / vendu
-- ---------------------------------------------------------------------
create table telima.place_products (
  id               uuid primary key default gen_random_uuid(),
  place_id         uuid not null references telima.places(id) on delete cascade,
  brand_id         uuid references telima.gas_brands(id) on delete set null,
  size_kg          numeric(5,1) not null check (size_kg > 0),
  price            integer not null check (price >= 0),
  availability     telima.availability not null default 'unknown',
  stock_available  integer not null default 0 check (stock_available >= 0),
  stock_reserved   integer not null default 0 check (stock_reserved >= 0),
  stock_sold       integer not null default 0 check (stock_sold >= 0),
  track_stock      boolean not null default false,   -- sinon la disponibilité se règle à la main
  confirmed_at     timestamptz,
  updated_at       timestamptz not null default now(),
  unique (place_id, brand_id, size_kg)
);
create index idx_place_products_place on telima.place_products(place_id);
create trigger trg_place_products_updated before update on telima.place_products
  for each row execute function telima.tg_set_updated_at();

-- Carburants d'une station (essence, gasoil)
create table telima.place_fuels (
  place_id     uuid not null references telima.places(id) on delete cascade,
  fuel         text not null check (fuel in ('essence', 'gasoil')),
  availability telima.availability not null default 'unknown',
  price        integer check (price is null or price >= 0),
  confirmed_at timestamptz,
  updated_at   timestamptz not null default now(),
  primary key (place_id, fuel)
);

-- ---------------------------------------------------------------------
-- Signalements des utilisateurs
-- ---------------------------------------------------------------------
create table telima.place_reports (
  id         uuid primary key default gen_random_uuid(),
  place_id   uuid not null references telima.places(id) on delete cascade,
  user_id    uuid not null references telima.users(id) on delete cascade,
  target     text not null check (target in ('gas', 'essence', 'gasoil', 'closed', 'price')),
  product_id uuid references telima.place_products(id) on delete set null,
  value      telima.availability,
  note       text,
  created_at timestamptz not null default now()
);
create index idx_place_reports_recent on telima.place_reports(place_id, target, created_at desc);
create index idx_place_reports_user on telima.place_reports(user_id, created_at desc);

create table telima.place_favorites (
  user_id    uuid not null references telima.users(id) on delete cascade,
  place_id   uuid not null references telima.places(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, place_id)
);

-- ---------------------------------------------------------------------
-- Commandes de gaz
-- ---------------------------------------------------------------------
create table telima.gas_orders (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,
  customer_id     uuid not null references telima.users(id) on delete restrict,
  place_id        uuid not null references telima.places(id) on delete restrict,
  mode            text not null check (mode in ('pickup', 'delivery')),
  status          telima.gas_order_status not null default 'sent',
  customer_name   text not null,
  customer_phone  text not null,
  dropoff_address text,
  dropoff_lat     double precision,
  dropoff_lng     double precision,
  dropoff_note    text,
  items_total     integer not null check (items_total >= 0),
  delivery_fee    integer not null default 0 check (delivery_fee >= 0),
  total           integer not null check (total >= 0),
  distance_km     numeric(7,2),
  payment_method  telima.payment_method not null default 'cash_on_delivery',
  payment_status  telima.gas_payment_status not null default 'unpaid',
  delivery_id     uuid references telima.deliveries(id) on delete set null,
  reject_reason   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (mode = 'pickup' or (dropoff_lat is not null and dropoff_lng is not null and dropoff_address is not null))
);
create index idx_gas_orders_customer on telima.gas_orders(customer_id, created_at desc);
create index idx_gas_orders_place on telima.gas_orders(place_id, created_at desc);
create index idx_gas_orders_delivery on telima.gas_orders(delivery_id);
create trigger trg_gas_orders_updated before update on telima.gas_orders
  for each row execute function telima.tg_set_updated_at();

create table telima.gas_order_items (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references telima.gas_orders(id) on delete cascade,
  product_id uuid references telima.place_products(id) on delete set null,
  label      text not null,
  size_kg    numeric(5,1) not null,
  qty        integer not null check (qty between 1 and 20),
  unit_price integer not null check (unit_price >= 0)
);
create index idx_gas_order_items_order on telima.gas_order_items(order_id);

-- ---------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------
create or replace function telima.is_place_owner(p_place uuid)
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (select 1 from telima.places where id = p_place and owner_id = auth.uid());
$$;

-- Un point reste « frais » 6 h ; au-delà, l'information est affichée comme ancienne.
create or replace function telima.availability_age_minutes(p_at timestamptz)
returns integer language sql stable as $$
  select case when p_at is null then null else (extract(epoch from (now() - p_at)) / 60)::int end;
$$;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table telima.gas_brands enable row level security;
alter table telima.places enable row level security;
alter table telima.place_products enable row level security;
alter table telima.place_fuels enable row level security;
alter table telima.place_reports enable row level security;
alter table telima.place_favorites enable row level security;
alter table telima.gas_orders enable row level security;
alter table telima.gas_order_items enable row level security;

create policy gas_brands_read on telima.gas_brands for select using (is_active or telima.is_staff());
create policy gas_brands_admin on telima.gas_brands for all using (telima.is_admin()) with check (telima.is_admin());

-- Lecture publique des points validés ; le propriétaire voit aussi les siens
create policy places_read on telima.places for select
  using (status = 'approved' or owner_id = auth.uid() or telima.is_staff());
create policy places_admin on telima.places for all using (telima.is_staff()) with check (telima.is_staff());
-- Le vendeur modifie son établissement (le statut et le propriétaire restent réservés à l'administration)
create policy places_owner_update on telima.places for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy place_products_read on telima.place_products for select
  using (exists (select 1 from telima.places p where p.id = place_id
                 and (p.status = 'approved' or p.owner_id = auth.uid() or telima.is_staff())));
create policy place_products_owner on telima.place_products for all
  using (telima.is_place_owner(place_id) or telima.is_staff())
  with check (telima.is_place_owner(place_id) or telima.is_staff());

create policy place_fuels_read on telima.place_fuels for select
  using (exists (select 1 from telima.places p where p.id = place_id
                 and (p.status = 'approved' or p.owner_id = auth.uid() or telima.is_staff())));
create policy place_fuels_owner on telima.place_fuels for all
  using (telima.is_place_owner(place_id) or telima.is_staff())
  with check (telima.is_place_owner(place_id) or telima.is_staff());

create policy place_reports_staff on telima.place_reports for select using (telima.is_staff());
create policy place_reports_mine on telima.place_reports for select using (user_id = auth.uid());

create policy place_favorites_mine on telima.place_favorites for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy gas_orders_read on telima.gas_orders for select
  using (customer_id = auth.uid() or telima.is_place_owner(place_id) or telima.is_staff());
create policy gas_order_items_read on telima.gas_order_items for select
  using (exists (select 1 from telima.gas_orders o where o.id = order_id
                 and (o.customer_id = auth.uid() or telima.is_place_owner(o.place_id) or telima.is_staff())));

grant select on telima.gas_brands, telima.places, telima.place_products, telima.place_fuels to anon, authenticated;
grant select on telima.place_reports, telima.gas_orders, telima.gas_order_items to authenticated;
grant select, insert, delete on telima.place_favorites to authenticated;
grant insert, update, delete on telima.gas_brands to authenticated;
grant insert, update, delete on telima.places, telima.place_products, telima.place_fuels to authenticated;

-- Le propriétaire ne doit pas pouvoir se valider lui-même ni changer de propriétaire
create or replace function telima.tg_places_guard()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if not telima.is_staff() then
    if tg_op = 'UPDATE' then
      new.status := old.status; new.owner_id := old.owner_id; new.kind := old.kind;
      new.source := old.source; new.osm_id := old.osm_id;
    end if;
  end if;
  return new;
end $$;
create trigger trg_places_guard before update on telima.places
  for each row execute function telima.tg_places_guard();

-- Garde la disponibilité cohérente avec le stock quand le vendeur le suit
create or replace function telima.tg_product_availability()
returns trigger language plpgsql as $$
begin
  if new.track_stock then
    new.availability := case when new.stock_available <= 0 then 'out'
                             when new.stock_available <= 3 then 'low' else 'available' end;
  end if;
  if tg_op = 'INSERT' or new.availability is distinct from old.availability
     or new.stock_available is distinct from old.stock_available then
    new.confirmed_at := now();
  end if;
  return new;
end $$;
create trigger trg_product_availability before insert or update on telima.place_products
  for each row execute function telima.tg_product_availability();

-- ---------------------------------------------------------------------
-- Recherche autour de moi (lecture publique, sans compte)
-- ---------------------------------------------------------------------
create or replace function telima.search_places(
  p_lat double precision, p_lng double precision,
  p_kind telima.place_kind default null, p_max_km numeric default 15,
  p_brand uuid default null, p_size numeric default null,
  p_only_available boolean default false, p_delivers boolean default false,
  p_query text default null, p_limit integer default 60)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_res jsonb;
begin
  select coalesce(jsonb_agg(r order by (r->>'distance_km')::numeric), '[]'::jsonb) into v_res from (
    select jsonb_build_object(
      'id', p.id, 'kind', p.kind, 'name', p.name, 'brand_label', p.brand_label,
      'city_id', p.city_id, 'neighborhood', p.neighborhood, 'address', p.address,
      'lat', p.lat, 'lng', p.lng, 'phone', p.phone, 'opening_hours', p.opening_hours,
      'services', p.services, 'delivers', p.delivers, 'delivery_radius_km', p.delivery_radius_km,
      'last_confirmed_at', p.last_confirmed_at,
      'distance_km', round(telima.haversine_km(p_lat, p_lng, p.lat, p.lng)::numeric, 2),
      'products', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', pr.id, 'brand_id', pr.brand_id, 'brand', b.name, 'size_kg', pr.size_kg, 'price', pr.price,
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
    order by telima.haversine_km(p_lat, p_lng, p.lat, p.lng)
    limit greatest(1, least(coalesce(p_limit, 60), 200))
  ) t;
  return v_res;
end $$;

-- ---------------------------------------------------------------------
-- Signalement communautaire
-- Règles : un utilisateur ne signale la même chose qu'une fois toutes les 30 minutes ;
-- la disponibilité change si le propriétaire/l'administration signale, ou si deux personnes
-- différentes disent la même chose en 3 heures. Un seul utilisateur ne peut donc pas modifier seul.
-- ---------------------------------------------------------------------
create or replace function telima.report_place(
  p_place_id uuid, p_target text, p_value telima.availability default null,
  p_product_id uuid default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_place telima.places;
  v_trusted boolean;
  v_agree integer;
  v_applied boolean := false;
begin
  select * into v_place from telima.places where id = p_place_id and status = 'approved';
  if not found then raise exception 'Point introuvable' using errcode = 'P0002'; end if;
  if p_target not in ('gas', 'essence', 'gasoil', 'closed', 'price') then
    raise exception 'Signalement invalide' using errcode = '22023';
  end if;
  if p_target in ('gas', 'essence', 'gasoil') and p_value is null then
    raise exception 'Indiquez disponible, stock faible ou rupture' using errcode = '22023';
  end if;
  if p_target = 'gas' and v_place.kind <> 'gas_point' then
    raise exception 'Ce point ne vend pas de gaz' using errcode = '22023';
  end if;
  if p_target in ('essence', 'gasoil') and v_place.kind <> 'fuel_station' then
    raise exception 'Ce point n''est pas une station-service' using errcode = '22023';
  end if;
  if exists (select 1 from telima.place_reports
             where user_id = v_uid and place_id = p_place_id and target = p_target
               and coalesce(product_id, '00000000-0000-0000-0000-000000000000') = coalesce(p_product_id, '00000000-0000-0000-0000-000000000000')
               and created_at > now() - interval '30 minutes') then
    raise exception 'Vous avez déjà signalé cela il y a moins de 30 minutes' using errcode = 'P0001';
  end if;

  insert into telima.place_reports(place_id, user_id, target, product_id, value, note)
  values (p_place_id, v_uid, p_target, p_product_id, p_value, nullif(trim(p_note), ''));

  v_trusted := v_place.owner_id = v_uid or telima.is_staff();
  if p_target in ('gas', 'essence', 'gasoil') then
    select count(distinct user_id) into v_agree from telima.place_reports
     where place_id = p_place_id and target = p_target and value = p_value
       and coalesce(product_id, '00000000-0000-0000-0000-000000000000') = coalesce(p_product_id, '00000000-0000-0000-0000-000000000000')
       and created_at > now() - interval '3 hours';
    if v_trusted or v_agree >= 2 then
      if p_target = 'gas' then
        update telima.place_products set availability = p_value, confirmed_at = now(), track_stock = false
         where place_id = p_place_id and (p_product_id is null or id = p_product_id);
      else
        insert into telima.place_fuels(place_id, fuel, availability, confirmed_at)
        values (p_place_id, p_target, p_value, now())
        on conflict (place_id, fuel) do update set availability = excluded.availability, confirmed_at = now(), updated_at = now();
      end if;
      update telima.places set last_confirmed_at = now() where id = p_place_id;
      v_applied := true;
    end if;
  elsif p_target = 'closed' then
    select count(distinct user_id) into v_agree from telima.place_reports
     where place_id = p_place_id and target = 'closed' and created_at > now() - interval '3 hours';
    if v_agree >= 3 then
      perform telima.notify_staff('place_closed', 'Point signalé fermé', v_place.name || ' a été signalé fermé par plusieurs personnes.',
                                  jsonb_build_object('place_id', p_place_id));
    end if;
  elsif p_target = 'price' then
    perform telima.notify_staff('place_price', 'Prix signalé incorrect', v_place.name || ' : ' || coalesce(p_note, ''),
                                jsonb_build_object('place_id', p_place_id));
  end if;

  if v_place.owner_id is not null and v_place.owner_id <> v_uid and p_value = 'out' then
    perform telima.notify_user(v_place.owner_id, 'stock_out', 'Rupture signalée', v_place.name || ' : une rupture a été signalée.',
                               jsonb_build_object('place_id', p_place_id));
  end if;
  return jsonb_build_object('applied', v_applied, 'reports', coalesce(v_agree, 1));
end $$;

-- ---------------------------------------------------------------------
-- Vendeur : enregistrer son point de vente (validé ensuite par l'administration)
-- ---------------------------------------------------------------------
create or replace function telima.vendor_register_place(p jsonb)
returns telima.places language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_row telima.places;
  v_city uuid;
begin
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'Le nom est obligatoire' using errcode = '22023'; end if;
  v_city := telima.find_city((p->>'lat')::float8, (p->>'lng')::float8);
  insert into telima.places(kind, name, brand_label, owner_id, city_id, neighborhood, address, lat, lng, phone,
                            opening_hours, delivers, delivery_radius_km, status, source)
  values (coalesce(p->>'kind', 'gas_point')::telima.place_kind, trim(p->>'name'), nullif(trim(p->>'brand_label'), ''),
          v_uid, v_city, nullif(trim(p->>'neighborhood'), ''), nullif(trim(p->>'address'), ''),
          (p->>'lat')::float8, (p->>'lng')::float8,
          nullif(telima.normalize_phone(coalesce(p->>'phone', '')), ''), nullif(trim(p->>'opening_hours'), ''),
          coalesce((p->>'delivers')::boolean, false), coalesce((p->>'delivery_radius_km')::numeric, 5),
          'pending', 'vendor')
  returning * into v_row;
  perform telima.notify_staff('place_pending', 'Nouveau point de vente à valider', v_row.name,
                              jsonb_build_object('place_id', v_row.id));
  return v_row;
end $$;

-- Administrateur : valider ou refuser un point
create or replace function telima.admin_set_place_status(p_place_id uuid, p_status telima.place_status)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_place telima.places;
begin
  perform telima.require_staff();
  update telima.places set status = p_status, last_confirmed_at = coalesce(last_confirmed_at, now())
   where id = p_place_id returning * into v_place;
  if not found then raise exception 'Point introuvable' using errcode = 'P0002'; end if;
  perform telima.log_admin_action('place_status', 'place', p_place_id::text, jsonb_build_object('status', p_status));
  perform telima.notify_user(v_place.owner_id, 'place_status',
    case when p_status = 'approved' then 'Point de vente validé' else 'Point de vente non validé' end,
    v_place.name, jsonb_build_object('place_id', p_place_id));
end $$;

-- ---------------------------------------------------------------------
-- Frais de livraison d'une commande de gaz : grille des tarifs de livraison de Telima (moto)
-- ---------------------------------------------------------------------
create or replace function telima.gas_delivery_fee(p_place_id uuid, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_place telima.places; v_q jsonb; v_km numeric;
begin
  select * into v_place from telima.places where id = p_place_id and status = 'approved' and kind = 'gas_point';
  if not found then raise exception 'Point introuvable' using errcode = 'P0002'; end if;
  if not v_place.delivers then raise exception 'Ce point ne livre pas' using errcode = 'P0001'; end if;
  v_km := telima.haversine_km(v_place.lat, v_place.lng, p_lat, p_lng);
  if v_km > v_place.delivery_radius_km then
    raise exception 'Adresse trop éloignée (rayon de livraison : % km)', v_place.delivery_radius_km using errcode = 'P0001';
  end if;
  v_q := telima.quote_delivery(v_place.lat, v_place.lng, p_lat, p_lng, 'moto', 'moyen', false, 13, 'colis_moyen', null, false);
  return jsonb_build_object('fee', (v_q->>'total_price')::int, 'distance_km', (v_q->>'distance_km')::numeric);
end $$;

-- ---------------------------------------------------------------------
-- Commande de gaz : verrouille et réserve le stock dans une seule transaction
-- p = { place_id, mode:'pickup'|'delivery', items:[{product_id, qty}], customer_name?, customer_phone?,
--       dropoff:{address,lat,lng,note}, payment_method }
-- ---------------------------------------------------------------------
create or replace function telima.create_gas_order(p jsonb)
returns telima.gas_orders language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_user telima.users;
  v_place telima.places;
  v_mode text := coalesce(p->>'mode', 'pickup');
  v_item jsonb;
  v_prod telima.place_products;
  v_brand text;
  v_qty int;
  v_items_total int := 0;
  v_fee int := 0;
  v_km numeric;
  v_drop jsonb := p->'dropoff';
  v_method telima.payment_method := coalesce(p->>'payment_method', 'cash_on_delivery')::telima.payment_method;
  v_row telima.gas_orders;
begin
  select * into v_user from telima.users where id = v_uid;
  select * into v_place from telima.places where id = (p->>'place_id')::uuid and status = 'approved' and kind = 'gas_point';
  if not found then raise exception 'Point de vente introuvable' using errcode = 'P0002'; end if;
  if v_mode not in ('pickup', 'delivery') then raise exception 'Mode invalide' using errcode = '22023'; end if;
  if v_method not in ('cash', 'cash_on_delivery') then
    raise exception 'Pour le moment, le gaz se règle en espèces' using errcode = 'P0001';
  end if;
  if jsonb_array_length(coalesce(p->'items', '[]'::jsonb)) = 0 then
    raise exception 'Choisissez au moins une bouteille' using errcode = '22023';
  end if;
  if v_mode = 'delivery' then
    if v_drop is null or coalesce(trim(v_drop->>'address'), '') = '' then
      raise exception 'Adresse de livraison obligatoire' using errcode = '22023';
    end if;
    select (f->>'fee')::int, (f->>'distance_km')::numeric into v_fee, v_km
      from (select telima.gas_delivery_fee(v_place.id, (v_drop->>'lat')::float8, (v_drop->>'lng')::float8) f) x;
  end if;

  insert into telima.gas_orders(code, customer_id, place_id, mode, customer_name, customer_phone,
      dropoff_address, dropoff_lat, dropoff_lng, dropoff_note, items_total, delivery_fee, total, distance_km, payment_method)
  values (telima.next_code('gas_order', 'GAZ'), v_uid, v_place.id, v_mode,
      coalesce(nullif(trim(p->>'customer_name'), ''), v_user.full_name),
      telima.normalize_phone(coalesce(nullif(p->>'customer_phone', ''), v_user.phone)),
      case when v_mode = 'delivery' then trim(v_drop->>'address') end,
      case when v_mode = 'delivery' then (v_drop->>'lat')::float8 end,
      case when v_mode = 'delivery' then (v_drop->>'lng')::float8 end,
      case when v_mode = 'delivery' then nullif(trim(v_drop->>'note'), '') end,
      0, v_fee, v_fee, v_km, v_method)
  returning * into v_row;

  for v_item in select * from jsonb_array_elements(p->'items') loop
    v_qty := (v_item->>'qty')::int;
    if v_qty is null or v_qty < 1 or v_qty > 20 then raise exception 'Quantité invalide' using errcode = '22023'; end if;
    select * into v_prod from telima.place_products
     where id = (v_item->>'product_id')::uuid and place_id = v_place.id for update;
    if not found then raise exception 'Produit introuvable' using errcode = 'P0002'; end if;
    if v_prod.availability = 'out' then raise exception 'Produit en rupture' using errcode = 'P0001'; end if;
    if v_prod.track_stock then
      if v_prod.stock_available < v_qty then
        raise exception 'Stock insuffisant (% disponible)', v_prod.stock_available using errcode = 'P0001';
      end if;
      update telima.place_products
         set stock_available = stock_available - v_qty, stock_reserved = stock_reserved + v_qty
       where id = v_prod.id;
    end if;
    select name into v_brand from telima.gas_brands where id = v_prod.brand_id;
    insert into telima.gas_order_items(order_id, product_id, label, size_kg, qty, unit_price)
    values (v_row.id, v_prod.id, coalesce(v_brand, 'Gaz'), v_prod.size_kg, v_qty, v_prod.price);
    v_items_total := v_items_total + v_prod.price * v_qty;
  end loop;

  update telima.gas_orders set items_total = v_items_total, total = v_items_total + v_fee
   where id = v_row.id returning * into v_row;

  perform telima.notify_user(v_place.owner_id, 'gas_order_new', 'Nouvelle commande de gaz',
    v_row.code || ' · ' || v_row.total || ' FCFA', jsonb_build_object('gas_order_id', v_row.id));
  return v_row;
end $$;

-- Remet le stock réservé en disponible (annulation / refus)
create or replace function telima._gas_release_stock(p_order_id uuid)
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  update telima.place_products pr
     set stock_available = pr.stock_available + i.qty, stock_reserved = greatest(0, pr.stock_reserved - i.qty)
    from telima.gas_order_items i
   where i.order_id = p_order_id and i.product_id = pr.id and pr.track_stock;
end $$;

-- Marque le stock réservé comme vendu (commande remise)
create or replace function telima._gas_sell_stock(p_order_id uuid)
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  update telima.place_products pr
     set stock_reserved = greatest(0, pr.stock_reserved - i.qty), stock_sold = pr.stock_sold + i.qty
    from telima.gas_order_items i
   where i.order_id = p_order_id and i.product_id = pr.id and pr.track_stock;
end $$;

-- ---------------------------------------------------------------------
-- Vendeur / administrateur : faire avancer une commande
-- p_action : accept | reject | preparing | ready | handed (retrait remis) | paid
-- ---------------------------------------------------------------------
create or replace function telima.gas_order_action(p_order_id uuid, p_action text, p_reason text default null)
returns telima.gas_orders language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_o telima.gas_orders;
  v_place telima.places;
  v_del telima.deliveries;
  v_desc text;
begin
  select * into v_o from telima.gas_orders where id = p_order_id for update;
  if not found then raise exception 'Commande introuvable' using errcode = 'P0002'; end if;
  select * into v_place from telima.places where id = v_o.place_id;
  if v_place.owner_id is distinct from v_uid and not telima.is_staff() then
    raise exception 'Cette commande ne concerne pas votre point de vente' using errcode = '42501';
  end if;

  if p_action = 'accept' and v_o.status = 'sent' then
    update telima.gas_orders set status = 'accepted' where id = v_o.id returning * into v_o;
    perform telima.notify_user(v_o.customer_id, 'gas_order_accepted', 'Commande acceptée', v_place.name || ' prépare votre gaz.',
                               jsonb_build_object('gas_order_id', v_o.id));
  elsif p_action = 'reject' and v_o.status in ('sent', 'accepted', 'preparing') then
    perform telima._gas_release_stock(v_o.id);
    update telima.gas_orders set status = 'rejected', reject_reason = nullif(trim(p_reason), '') where id = v_o.id returning * into v_o;
    perform telima.notify_user(v_o.customer_id, 'gas_order_rejected', 'Commande refusée', v_place.name || coalesce(' : ' || v_o.reject_reason, ''),
                               jsonb_build_object('gas_order_id', v_o.id));
  elsif p_action = 'preparing' and v_o.status in ('sent', 'accepted') then
    update telima.gas_orders set status = 'preparing' where id = v_o.id returning * into v_o;
  elsif p_action = 'ready' and v_o.status in ('sent', 'accepted', 'preparing') then
    if v_o.mode = 'delivery' then
      select string_agg(i.qty || ' × ' || i.label || ' ' || i.size_kg || ' kg', ', ') into v_desc
        from telima.gas_order_items i where i.order_id = v_o.id;
      v_del := telima._insert_delivery(
        jsonb_build_object(
          'pickup', jsonb_build_object('address', coalesce(v_place.address, v_place.name), 'lat', v_place.lat, 'lng', v_place.lng,
                                       'contact_name', v_place.name, 'contact_phone', coalesce(v_place.phone, v_o.customer_phone)),
          'dropoff', jsonb_build_object('address', v_o.dropoff_address, 'lat', v_o.dropoff_lat, 'lng', v_o.dropoff_lng,
                                        'contact_name', v_o.customer_name, 'contact_phone', v_o.customer_phone,
                                        'instructions', v_o.dropoff_note),
          'package', jsonb_build_object('category', 'colis_moyen', 'size', 'moyen', 'weight_kg', 13,
                       'description', 'Gaz : ' || v_desc || ' — à encaisser auprès du client : ' || v_o.items_total || ' FCFA'),
          'vehicle_type', 'moto', 'payment_method', 'cash'),
        v_o.customer_id, v_o.customer_name, v_o.customer_phone, v_uid, 'app', null, 1, false, null, null, v_o.delivery_fee);
      perform telima.notify_nearby_drivers(v_del);
      update telima.gas_orders set status = 'ready', delivery_id = v_del.id where id = v_o.id returning * into v_o;
      perform telima.notify_user(v_o.customer_id, 'gas_order_ready', 'Commande prête', 'Un livreur est recherché pour vous livrer.',
                                 jsonb_build_object('gas_order_id', v_o.id, 'delivery_id', v_del.id));
    else
      update telima.gas_orders set status = 'ready' where id = v_o.id returning * into v_o;
      perform telima.notify_user(v_o.customer_id, 'gas_order_ready', 'Commande prête', 'Vous pouvez passer la retirer chez ' || v_place.name || '.',
                                 jsonb_build_object('gas_order_id', v_o.id));
    end if;
  elsif p_action = 'handed' and v_o.mode = 'pickup' and v_o.status in ('ready', 'accepted', 'preparing') then
    perform telima._gas_sell_stock(v_o.id);
    update telima.gas_orders set status = 'delivered', payment_status = 'paid' where id = v_o.id returning * into v_o;
  elsif p_action = 'paid' and v_o.status <> 'cancelled' then
    update telima.gas_orders set payment_status = 'paid' where id = v_o.id returning * into v_o;
  else
    raise exception 'Action impossible pour une commande « % »', v_o.status using errcode = 'P0001';
  end if;
  return v_o;
end $$;

-- Client : annuler tant que le vendeur n'a pas accepté
create or replace function telima.cancel_gas_order(p_order_id uuid)
returns telima.gas_orders language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_o telima.gas_orders;
begin
  select * into v_o from telima.gas_orders where id = p_order_id and customer_id = v_uid for update;
  if not found then raise exception 'Commande introuvable' using errcode = 'P0002'; end if;
  if v_o.status <> 'sent' then raise exception 'Le vendeur a déjà accepté : appelez-le pour annuler' using errcode = 'P0001'; end if;
  perform telima._gas_release_stock(v_o.id);
  update telima.gas_orders set status = 'cancelled' where id = v_o.id returning * into v_o;
  perform telima.notify_user((select owner_id from telima.places where id = v_o.place_id), 'gas_order_cancelled',
    'Commande annulée', v_o.code, jsonb_build_object('gas_order_id', v_o.id));
  return v_o;
end $$;

-- La commande suit sa livraison
create or replace function telima.tg_gas_follow_delivery()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_o telima.gas_orders;
begin
  select * into v_o from telima.gas_orders where delivery_id = new.id for update;
  if not found or v_o.status in ('delivered', 'cancelled', 'rejected') then return new; end if;
  if new.status in ('picked_up', 'in_transit', 'at_dropoff') and v_o.status <> 'out_for_delivery' then
    update telima.gas_orders set status = 'out_for_delivery' where id = v_o.id;
  elsif new.status in ('handed_over', 'completed') then
    perform telima._gas_sell_stock(v_o.id);
    update telima.gas_orders set status = 'delivered', payment_status = 'paid' where id = v_o.id;
  elsif new.status = 'cancelled' then
    perform telima._gas_release_stock(v_o.id);
    update telima.gas_orders set status = 'cancelled' where id = v_o.id;
    perform telima.notify_user(v_o.customer_id, 'gas_order_cancelled', 'Livraison annulée', v_o.code,
                               jsonb_build_object('gas_order_id', v_o.id));
  end if;
  return new;
end $$;
create trigger trg_gas_follow_delivery after update of status on telima.deliveries
  for each row when (old.status is distinct from new.status) execute function telima.tg_gas_follow_delivery();

-- Statistiques du vendeur
create or replace function telima.vendor_dashboard(p_place_id uuid)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if not telima.is_place_owner(p_place_id) and not telima.is_staff() then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'orders_today', (select count(*) from telima.gas_orders where place_id = p_place_id and created_at >= date_trunc('day', now())),
    'sales_today', coalesce((select sum(items_total) from telima.gas_orders where place_id = p_place_id
                              and status = 'delivered' and updated_at >= date_trunc('day', now())), 0),
    'pending', (select count(*) from telima.gas_orders where place_id = p_place_id and status in ('sent', 'accepted', 'preparing')),
    'in_delivery', (select count(*) from telima.gas_orders where place_id = p_place_id and status in ('ready', 'out_for_delivery') and mode = 'delivery'),
    'stock', coalesce((select sum(stock_available) from telima.place_products where place_id = p_place_id and track_stock), 0),
    'out_of_stock', (select count(*) from telima.place_products where place_id = p_place_id and availability = 'out'));
end $$;

-- Favoris
create or replace function telima.toggle_favorite_place(p_place_id uuid)
returns boolean language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if exists (select 1 from telima.place_favorites where user_id = v_uid and place_id = p_place_id) then
    delete from telima.place_favorites where user_id = v_uid and place_id = p_place_id; return false;
  end if;
  insert into telima.place_favorites(user_id, place_id) values (v_uid, p_place_id); return true;
end $$;

-- ---------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function telima.search_places(double precision, double precision, telima.place_kind, numeric, uuid, numeric, boolean, boolean, text, integer),
  telima.report_place(uuid, text, telima.availability, uuid, text), telima.vendor_register_place(jsonb),
  telima.admin_set_place_status(uuid, telima.place_status), telima.gas_delivery_fee(uuid, double precision, double precision),
  telima.create_gas_order(jsonb), telima.gas_order_action(uuid, text, text), telima.cancel_gas_order(uuid),
  telima.vendor_dashboard(uuid), telima.toggle_favorite_place(uuid), telima.is_place_owner(uuid),
  telima._gas_release_stock(uuid), telima._gas_sell_stock(uuid), telima.availability_age_minutes(timestamptz) from public, anon, authenticated;
grant execute on function telima.search_places(double precision, double precision, telima.place_kind, numeric, uuid, numeric, boolean, boolean, text, integer),
  telima.availability_age_minutes(timestamptz) to anon, authenticated, service_role;
grant execute on function telima.report_place(uuid, text, telima.availability, uuid, text), telima.vendor_register_place(jsonb),
  telima.admin_set_place_status(uuid, telima.place_status), telima.gas_delivery_fee(uuid, double precision, double precision),
  telima.create_gas_order(jsonb), telima.gas_order_action(uuid, text, text), telima.cancel_gas_order(uuid),
  telima.vendor_dashboard(uuid), telima.toggle_favorite_place(uuid), telima.is_place_owner(uuid) to authenticated, service_role;

-- Marques courantes (modifiables dans l'administration)
insert into telima.gas_brands(name) values ('Total'), ('Oryx'), ('Sodigaz'), ('Autre') on conflict do nothing;
