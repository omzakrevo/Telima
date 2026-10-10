-- (Appliquée en production sous le nom telima_13_restaurants ; les noms rmenu_* évitent les collisions avec l'ancien module food_orders.)
-- Module « Restaurants » : un restaurateur crée son restaurant et son menu, obtient un lien public
-- à partager (https://…/r/<slug>), et les clients commandent directement chez lui.
-- La livraison réutilise telima.deliveries : une commande livrée = une livraison ordinaire (livreur Telima).
-- Paiement : espèces à la remise (le livreur encaisse le montant des plats pour le restaurant).

create type telima.restaurant_order_status as enum
  ('sent', 'accepted', 'preparing', 'ready', 'out_for_delivery', 'delivered', 'rejected', 'cancelled');

-- ---------------------------------------------------------------------
-- Restaurants
-- ---------------------------------------------------------------------
create table telima.restaurants (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references telima.users(id) on delete cascade,
  slug             text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 2 and 50),
  name             text not null check (char_length(name) between 2 and 80),
  description      text check (description is null or char_length(description) <= 500),
  cuisine          text,                                     -- « Poulet braisé, Riz sauce… »
  phone            text,
  city_id          uuid references telima.cities(id) on delete set null,
  neighborhood     text,
  address          text,
  lat              double precision not null check (lat between -90 and 90),
  lng              double precision not null check (lng between -180 and 180),
  logo_path        text,                                     -- compartiment public telima-restaurants
  cover_path       text,
  opening_hours    text,
  accepting_orders boolean not null default true,            -- bouton « Ouvert / Fermé » du restaurateur
  accepts_pickup   boolean not null default true,
  delivers         boolean not null default true,
  delivery_radius_km numeric(5,1) not null default 5 check (delivery_radius_km >= 0),
  min_order        integer not null default 0 check (min_order >= 0),
  prep_minutes     integer not null default 20 check (prep_minutes between 0 and 240),
  status           telima.place_status not null default 'approved',  -- l'administration peut suspendre
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (accepts_pickup or delivers)
);
create index idx_restaurants_owner on telima.restaurants(owner_id);
create index idx_restaurants_status on telima.restaurants(status);
create index idx_restaurants_geo on telima.restaurants(lat, lng);
create trigger trg_restaurants_updated before update on telima.restaurants
  for each row execute function telima.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Menu : catégories et plats
-- ---------------------------------------------------------------------
create table telima.restaurant_menu_categories (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references telima.restaurants(id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 60),
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);
create index idx_rmenu_categories_restaurant on telima.restaurant_menu_categories(restaurant_id, sort_order);

create table telima.restaurant_menu_items (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references telima.restaurants(id) on delete cascade,
  category_id   uuid references telima.restaurant_menu_categories(id) on delete set null,
  name          text not null check (char_length(name) between 1 and 100),
  description   text check (description is null or char_length(description) <= 300),
  price         integer not null check (price >= 0),
  photo_path    text,
  is_available  boolean not null default true,               -- « épuisé aujourd'hui »
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index idx_rmenu_items_restaurant on telima.restaurant_menu_items(restaurant_id, sort_order);
create index idx_rmenu_items_category on telima.restaurant_menu_items(category_id);
create trigger trg_rmenu_items_updated before update on telima.restaurant_menu_items
  for each row execute function telima.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------
create table telima.restaurant_orders (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,
  customer_id     uuid not null references telima.users(id) on delete restrict,
  restaurant_id   uuid not null references telima.restaurants(id) on delete restrict,
  mode            text not null check (mode in ('pickup', 'delivery')),
  status          telima.restaurant_order_status not null default 'sent',
  customer_name   text not null,
  customer_phone  text not null,
  note            text,
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
create index idx_restaurant_orders_customer on telima.restaurant_orders(customer_id, created_at desc);
create index idx_restaurant_orders_restaurant on telima.restaurant_orders(restaurant_id, created_at desc);
create index idx_restaurant_orders_delivery on telima.restaurant_orders(delivery_id);
create trigger trg_restaurant_orders_updated before update on telima.restaurant_orders
  for each row execute function telima.tg_set_updated_at();

create table telima.restaurant_order_items (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references telima.restaurant_orders(id) on delete cascade,
  item_id    uuid references telima.restaurant_menu_items(id) on delete set null,
  name       text not null,
  qty        integer not null check (qty between 1 and 50),
  unit_price integer not null check (unit_price >= 0),
  note       text
);
create index idx_restaurant_order_items_order on telima.restaurant_order_items(order_id);

-- ---------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------
create or replace function telima.is_restaurant_owner(p_restaurant uuid)
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (select 1 from telima.restaurants where id = p_restaurant and owner_id = auth.uid());
$$;

-- Lien lisible : « Chez Awa » -> chez-awa ; ajoute un suffixe si déjà pris.
create or replace function telima.make_restaurant_slug(p_name text)
returns text language plpgsql volatile set search_path = telima, public as $$
declare v_base text; v_slug text; v_try int := 0;
begin
  v_base := lower(translate(coalesce(p_name, ''), 'àâäÀÂÄéèêëÉÈÊËîïÎÏôöÔÖùûüÙÛÜçÇ', 'aaaaaaeeeeeeeeiiiioooouuuuuucc'));
  v_base := regexp_replace(v_base, '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  v_base := left(v_base, 40);
  v_base := trim(both '-' from v_base);
  if char_length(v_base) < 2 then v_base := 'restaurant'; end if;
  v_slug := v_base;
  while exists (select 1 from telima.restaurants where slug = v_slug) loop
    v_try := v_try + 1;
    v_slug := v_base || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, case when v_try < 4 then 3 else 6 end);
  end loop;
  return v_slug;
end $$;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table telima.restaurants enable row level security;
alter table telima.restaurant_menu_categories enable row level security;
alter table telima.restaurant_menu_items enable row level security;
alter table telima.restaurant_orders enable row level security;
alter table telima.restaurant_order_items enable row level security;

create policy restaurants_read on telima.restaurants for select
  using (status = 'approved' or owner_id = auth.uid() or telima.is_staff());
create policy restaurants_admin on telima.restaurants for all using (telima.is_staff()) with check (telima.is_staff());
create policy restaurants_owner_update on telima.restaurants for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy restaurants_owner_delete on telima.restaurants for delete using (owner_id = auth.uid());

create policy rmenu_categories_read on telima.restaurant_menu_categories for select
  using (exists (select 1 from telima.restaurants r where r.id = restaurant_id
                 and (r.status = 'approved' or r.owner_id = auth.uid() or telima.is_staff())));
create policy rmenu_categories_owner on telima.restaurant_menu_categories for all
  using (telima.is_restaurant_owner(restaurant_id) or telima.is_staff())
  with check (telima.is_restaurant_owner(restaurant_id) or telima.is_staff());

create policy rmenu_items_read on telima.restaurant_menu_items for select
  using (exists (select 1 from telima.restaurants r where r.id = restaurant_id
                 and (r.status = 'approved' or r.owner_id = auth.uid() or telima.is_staff())));
create policy rmenu_items_owner on telima.restaurant_menu_items for all
  using (telima.is_restaurant_owner(restaurant_id) or telima.is_staff())
  with check (telima.is_restaurant_owner(restaurant_id) or telima.is_staff());

create policy restaurant_orders_read on telima.restaurant_orders for select
  using (customer_id = auth.uid() or telima.is_restaurant_owner(restaurant_id) or telima.is_staff());
create policy restaurant_order_items_read on telima.restaurant_order_items for select
  using (exists (select 1 from telima.restaurant_orders o where o.id = order_id
                 and (o.customer_id = auth.uid() or telima.is_restaurant_owner(o.restaurant_id) or telima.is_staff())));

grant select on telima.restaurants, telima.restaurant_menu_categories, telima.restaurant_menu_items to authenticated;
grant select on telima.restaurant_orders, telima.restaurant_order_items to authenticated;
grant update, delete on telima.restaurants to authenticated;
grant insert, update, delete on telima.restaurant_menu_categories, telima.restaurant_menu_items to authenticated;

-- Le restaurateur ne peut ni se valider lui-même, ni changer de propriétaire, ni casser le lien déjà partagé
create or replace function telima.tg_restaurants_guard()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if not telima.is_staff() then
    new.status := old.status; new.owner_id := old.owner_id; new.slug := old.slug;
  end if;
  if new.lat is distinct from old.lat or new.lng is distinct from old.lng then
    new.city_id := telima.find_city(new.lat, new.lng);
  end if;
  return new;
end $$;
create trigger trg_restaurants_guard before update on telima.restaurants
  for each row execute function telima.tg_restaurants_guard();

-- Une catégorie et un plat doivent appartenir au même restaurant
create or replace function telima.tg_restaurant_menu_item_category()
returns trigger language plpgsql as $$
begin
  if new.category_id is not null and not exists (
       select 1 from telima.restaurant_menu_categories c where c.id = new.category_id and c.restaurant_id = new.restaurant_id) then
    raise exception 'Catégorie invalide' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger trg_rmenu_item_category before insert or update on telima.restaurant_menu_items
  for each row execute function telima.tg_restaurant_menu_item_category();

-- ---------------------------------------------------------------------
-- Photos : compartiment public (logos, couvertures, plats) ; chacun écrit dans son dossier
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('telima-restaurants', 'telima-restaurants', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy telima_restaurants_upload_own on storage.objects for insert to authenticated
  with check (bucket_id = 'telima-restaurants' and (storage.foldername(name))[1] = auth.uid()::text);
-- (la lecture publique du compartiment existe déjà : policy telima_restaurants_read)
create policy telima_restaurants_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'telima-restaurants' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- Créer son restaurant : actif tout de suite, le lien est renvoyé dans « slug »
-- p = { name, description?, cuisine?, phone?, neighborhood?, address, lat, lng, opening_hours?,
--       accepts_pickup?, delivers?, delivery_radius_km?, min_order?, prep_minutes?, logo_path?, cover_path? }
-- ---------------------------------------------------------------------
create or replace function telima.register_restaurant(p jsonb)
returns telima.restaurants language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_row telima.restaurants;
  v_pickup boolean := coalesce((p->>'accepts_pickup')::boolean, true);
  v_delivers boolean := coalesce((p->>'delivers')::boolean, true);
begin
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'Le nom du restaurant est obligatoire' using errcode = '22023'; end if;
  if p->>'lat' is null or p->>'lng' is null then raise exception 'Placez votre restaurant sur la carte' using errcode = '22023'; end if;
  if not (v_pickup or v_delivers) then raise exception 'Choisissez au moins le retrait ou la livraison' using errcode = '22023'; end if;
  if (select count(*) from telima.restaurants where owner_id = v_uid) >= 5 then
    raise exception 'Vous avez atteint le maximum de 5 restaurants' using errcode = 'P0001';
  end if;

  insert into telima.restaurants(owner_id, slug, name, description, cuisine, phone, city_id, neighborhood, address, lat, lng,
                                 opening_hours, accepts_pickup, delivers, delivery_radius_km, min_order, prep_minutes, logo_path, cover_path)
  values (v_uid, telima.make_restaurant_slug(p->>'name'), trim(p->>'name'), nullif(trim(p->>'description'), ''),
          nullif(trim(p->>'cuisine'), ''), nullif(telima.normalize_phone(coalesce(p->>'phone', '')), ''),
          telima.find_city((p->>'lat')::float8, (p->>'lng')::float8),
          nullif(trim(p->>'neighborhood'), ''), nullif(trim(p->>'address'), ''),
          (p->>'lat')::float8, (p->>'lng')::float8, nullif(trim(p->>'opening_hours'), ''),
          v_pickup, v_delivers, coalesce((p->>'delivery_radius_km')::numeric, 5),
          coalesce((p->>'min_order')::int, 0), coalesce((p->>'prep_minutes')::int, 20),
          nullif(p->>'logo_path', ''), nullif(p->>'cover_path', ''))
  returning * into v_row;
  perform telima.notify_staff('restaurant_new', 'Nouveau restaurant', v_row.name, jsonb_build_object('restaurant_id', v_row.id));
  return v_row;
end $$;

-- ---------------------------------------------------------------------
-- Page publique d'un restaurant, lisible SANS compte (lien partagé)
-- ---------------------------------------------------------------------
create or replace function telima.restaurant_by_slug(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_r telima.restaurants;
begin
  select * into v_r from telima.restaurants where slug = lower(trim(p_slug)) and status = 'approved';
  if not found then return null; end if;
  return jsonb_build_object(
    'id', v_r.id, 'slug', v_r.slug, 'name', v_r.name, 'description', v_r.description, 'cuisine', v_r.cuisine,
    'phone', v_r.phone, 'neighborhood', v_r.neighborhood, 'address', v_r.address, 'lat', v_r.lat, 'lng', v_r.lng,
    'logo_path', v_r.logo_path, 'cover_path', v_r.cover_path, 'opening_hours', v_r.opening_hours,
    'accepting_orders', v_r.accepting_orders, 'accepts_pickup', v_r.accepts_pickup, 'delivers', v_r.delivers,
    'delivery_radius_km', v_r.delivery_radius_km, 'min_order', v_r.min_order, 'prep_minutes', v_r.prep_minutes,
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.sort_order, c.created_at)
                              from telima.restaurant_menu_categories c where c.restaurant_id = v_r.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'category_id', i.category_id, 'name', i.name, 'description', i.description,
                          'price', i.price, 'photo_path', i.photo_path, 'is_available', i.is_available)
                        order by i.sort_order, i.created_at)
                         from telima.restaurant_menu_items i where i.restaurant_id = v_r.id), '[]'::jsonb));
end $$;

-- Restaurants autour de moi (liste dans l'application, lecture publique)
create or replace function telima.find_restaurants(
  p_lat double precision, p_lng double precision, p_max_km numeric default 15,
  p_query text default null, p_delivers boolean default false, p_limit integer default 60)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_res jsonb;
begin
  select coalesce(jsonb_agg(r order by (r->>'distance_km')::numeric), '[]'::jsonb) into v_res from (
    select jsonb_build_object(
      'id', x.id, 'slug', x.slug, 'name', x.name, 'cuisine', x.cuisine, 'neighborhood', x.neighborhood,
      'address', x.address, 'lat', x.lat, 'lng', x.lng, 'logo_path', x.logo_path, 'cover_path', x.cover_path,
      'opening_hours', x.opening_hours, 'accepting_orders', x.accepting_orders, 'accepts_pickup', x.accepts_pickup,
      'delivers', x.delivers, 'delivery_radius_km', x.delivery_radius_km, 'min_order', x.min_order,
      'prep_minutes', x.prep_minutes, 'phone', x.phone,
      'distance_km', round(telima.haversine_km(p_lat, p_lng, x.lat, x.lng)::numeric, 2)) as r
    from telima.restaurants x
    where x.status = 'approved'
      and (not p_delivers or x.delivers)
      and (p_query is null or x.name ilike '%' || p_query || '%' or x.cuisine ilike '%' || p_query || '%'
           or x.neighborhood ilike '%' || p_query || '%'
           or exists (select 1 from telima.restaurant_menu_items i where i.restaurant_id = x.id and i.name ilike '%' || p_query || '%'))
      and telima.haversine_km(p_lat, p_lng, x.lat, x.lng) <= p_max_km
    order by telima.haversine_km(p_lat, p_lng, x.lat, x.lng)
    limit greatest(1, least(coalesce(p_limit, 60), 200))
  ) t;
  return v_res;
end $$;

-- ---------------------------------------------------------------------
-- Frais de livraison : grille des tarifs de livraison de Telima (moto), comme pour le gaz
-- ---------------------------------------------------------------------
create or replace function telima.restaurant_delivery_fee(p_restaurant_id uuid, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_r telima.restaurants; v_q jsonb; v_km numeric;
begin
  select * into v_r from telima.restaurants where id = p_restaurant_id and status = 'approved';
  if not found then raise exception 'Restaurant introuvable' using errcode = 'P0002'; end if;
  if not v_r.delivers then raise exception 'Ce restaurant ne livre pas' using errcode = 'P0001'; end if;
  v_km := telima.haversine_km(v_r.lat, v_r.lng, p_lat, p_lng);
  if v_km > v_r.delivery_radius_km then
    raise exception 'Adresse trop éloignée (rayon de livraison : % km)', v_r.delivery_radius_km using errcode = 'P0001';
  end if;
  v_q := telima.quote_delivery(v_r.lat, v_r.lng, p_lat, p_lng, 'moto', 'petit', false, 3, 'nourriture', null, false);
  return jsonb_build_object('fee', (v_q->>'total_price')::int, 'distance_km', (v_q->>'distance_km')::numeric);
end $$;

-- ---------------------------------------------------------------------
-- Commande : les prix sont relus côté serveur (jamais ceux envoyés par l'application)
-- p = { restaurant_id, mode:'pickup'|'delivery', items:[{item_id, qty, note?}], note?, customer_name?, customer_phone?,
--       dropoff:{address,lat,lng,note}, payment_method }
-- ---------------------------------------------------------------------
create or replace function telima.create_restaurant_order(p jsonb)
returns telima.restaurant_orders language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_user telima.users;
  v_r telima.restaurants;
  v_mode text := coalesce(p->>'mode', 'pickup');
  v_item jsonb;
  v_menu telima.restaurant_menu_items;
  v_qty int;
  v_items_total int := 0;
  v_fee int := 0;
  v_km numeric;
  v_drop jsonb := p->'dropoff';
  v_method telima.payment_method := coalesce(p->>'payment_method', 'cash_on_delivery')::telima.payment_method;
  v_row telima.restaurant_orders;
begin
  select * into v_user from telima.users where id = v_uid;
  select * into v_r from telima.restaurants where id = (p->>'restaurant_id')::uuid and status = 'approved';
  if not found then raise exception 'Restaurant introuvable' using errcode = 'P0002'; end if;
  if not v_r.accepting_orders then raise exception 'Ce restaurant ne prend pas de commande pour le moment' using errcode = 'P0001'; end if;
  if v_mode not in ('pickup', 'delivery') then raise exception 'Mode invalide' using errcode = '22023'; end if;
  if v_mode = 'pickup' and not v_r.accepts_pickup then raise exception 'Ce restaurant ne propose pas le retrait' using errcode = 'P0001'; end if;
  if v_mode = 'delivery' and not v_r.delivers then raise exception 'Ce restaurant ne livre pas' using errcode = 'P0001'; end if;
  if v_method not in ('cash', 'cash_on_delivery') then
    raise exception 'Pour le moment, les repas se règlent en espèces' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Choisissez au moins un plat' using errcode = '22023';
  end if;
  if jsonb_array_length(p->'items') > 60 then raise exception 'Trop de lignes dans la commande' using errcode = '22023'; end if;
  if v_mode = 'delivery' then
    if v_drop is null or coalesce(trim(v_drop->>'address'), '') = '' then
      raise exception 'Adresse de livraison obligatoire' using errcode = '22023';
    end if;
    select (f->>'fee')::int, (f->>'distance_km')::numeric into v_fee, v_km
      from (select telima.restaurant_delivery_fee(v_r.id, (v_drop->>'lat')::float8, (v_drop->>'lng')::float8) f) x;
  end if;

  insert into telima.restaurant_orders(code, customer_id, restaurant_id, mode, customer_name, customer_phone, note,
      dropoff_address, dropoff_lat, dropoff_lng, dropoff_note, items_total, delivery_fee, total, distance_km, payment_method)
  values (telima.next_code('restaurant_order', 'RES'), v_uid, v_r.id, v_mode,
      coalesce(nullif(trim(p->>'customer_name'), ''), v_user.full_name),
      telima.normalize_phone(coalesce(nullif(p->>'customer_phone', ''), v_user.phone)),
      nullif(trim(p->>'note'), ''),
      case when v_mode = 'delivery' then trim(v_drop->>'address') end,
      case when v_mode = 'delivery' then (v_drop->>'lat')::float8 end,
      case when v_mode = 'delivery' then (v_drop->>'lng')::float8 end,
      case when v_mode = 'delivery' then nullif(trim(v_drop->>'note'), '') end,
      0, v_fee, v_fee, v_km, v_method)
  returning * into v_row;

  for v_item in select * from jsonb_array_elements(p->'items') loop
    v_qty := (v_item->>'qty')::int;
    if v_qty is null or v_qty < 1 or v_qty > 50 then raise exception 'Quantité invalide' using errcode = '22023'; end if;
    select * into v_menu from telima.restaurant_menu_items where id = (v_item->>'item_id')::uuid and restaurant_id = v_r.id;
    if not found then raise exception 'Plat introuvable' using errcode = 'P0002'; end if;
    if not v_menu.is_available then raise exception '« % » n''est plus disponible', v_menu.name using errcode = 'P0001'; end if;
    insert into telima.restaurant_order_items(order_id, item_id, name, qty, unit_price, note)
    values (v_row.id, v_menu.id, v_menu.name, v_qty, v_menu.price, nullif(left(trim(coalesce(v_item->>'note', '')), 200), ''));
    v_items_total := v_items_total + v_menu.price * v_qty;
  end loop;

  if v_items_total < v_r.min_order then
    raise exception 'Commande minimum : % FCFA', v_r.min_order using errcode = 'P0001';
  end if;

  update telima.restaurant_orders set items_total = v_items_total, total = v_items_total + v_fee
   where id = v_row.id returning * into v_row;

  perform telima.notify_user(v_r.owner_id, 'restaurant_order_new', 'Nouvelle commande',
    v_row.code || ' · ' || v_row.total || ' FCFA', jsonb_build_object('restaurant_order_id', v_row.id, 'restaurant_id', v_r.id));
  return v_row;
end $$;

-- ---------------------------------------------------------------------
-- Restaurateur / administrateur : faire avancer une commande
-- p_action : accept | reject | preparing | ready | handed (retrait remis) | paid
-- ---------------------------------------------------------------------
create or replace function telima.restaurant_order_action(p_order_id uuid, p_action text, p_reason text default null)
returns telima.restaurant_orders language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_o telima.restaurant_orders;
  v_r telima.restaurants;
  v_del telima.deliveries;
  v_desc text;
begin
  select * into v_o from telima.restaurant_orders where id = p_order_id for update;
  if not found then raise exception 'Commande introuvable' using errcode = 'P0002'; end if;
  select * into v_r from telima.restaurants where id = v_o.restaurant_id;
  if v_r.owner_id is distinct from v_uid and not telima.is_staff() then
    raise exception 'Cette commande ne concerne pas votre restaurant' using errcode = '42501';
  end if;

  if p_action = 'accept' and v_o.status = 'sent' then
    update telima.restaurant_orders set status = 'accepted' where id = v_o.id returning * into v_o;
    perform telima.notify_user(v_o.customer_id, 'restaurant_order_accepted', 'Commande acceptée',
      v_r.name || ' prépare votre commande (environ ' || v_r.prep_minutes || ' min).',
      jsonb_build_object('restaurant_order_id', v_o.id));
  elsif p_action = 'reject' and v_o.status in ('sent', 'accepted', 'preparing') then
    update telima.restaurant_orders set status = 'rejected', reject_reason = nullif(trim(p_reason), '') where id = v_o.id returning * into v_o;
    perform telima.notify_user(v_o.customer_id, 'restaurant_order_rejected', 'Commande refusée',
      v_r.name || coalesce(' : ' || v_o.reject_reason, ''), jsonb_build_object('restaurant_order_id', v_o.id));
  elsif p_action = 'preparing' and v_o.status in ('sent', 'accepted') then
    update telima.restaurant_orders set status = 'preparing' where id = v_o.id returning * into v_o;
    perform telima.notify_user(v_o.customer_id, 'restaurant_order_preparing', 'En préparation',
      v_r.name || ' prépare votre commande.', jsonb_build_object('restaurant_order_id', v_o.id));
  elsif p_action = 'ready' and v_o.status in ('sent', 'accepted', 'preparing') then
    if v_o.mode = 'delivery' then
      select string_agg(i.qty || ' × ' || i.name, ', ') into v_desc
        from telima.restaurant_order_items i where i.order_id = v_o.id;
      v_del := telima._insert_delivery(
        jsonb_build_object(
          'pickup', jsonb_build_object('address', coalesce(v_r.address, v_r.name), 'lat', v_r.lat, 'lng', v_r.lng,
                                       'contact_name', v_r.name, 'contact_phone', coalesce(v_r.phone, v_o.customer_phone)),
          'dropoff', jsonb_build_object('address', v_o.dropoff_address, 'lat', v_o.dropoff_lat, 'lng', v_o.dropoff_lng,
                                        'contact_name', v_o.customer_name, 'contact_phone', v_o.customer_phone,
                                        'instructions', v_o.dropoff_note),
          'package', jsonb_build_object('category', 'nourriture', 'size', 'petit', 'weight_kg', 3,
                       'description', 'Repas ' || v_r.name || ' : ' || v_desc || ' — à encaisser auprès du client : ' || v_o.items_total || ' FCFA'),
          'vehicle_type', 'moto', 'payment_method', 'cash'),
        v_o.customer_id, v_o.customer_name, v_o.customer_phone, v_uid, 'app', null, 1, false, null, null, v_o.delivery_fee);
      perform telima.notify_nearby_drivers(v_del);
      update telima.restaurant_orders set status = 'ready', delivery_id = v_del.id where id = v_o.id returning * into v_o;
      perform telima.notify_user(v_o.customer_id, 'restaurant_order_ready', 'Commande prête',
        'Un livreur est recherché pour vous livrer.', jsonb_build_object('restaurant_order_id', v_o.id, 'delivery_id', v_del.id));
    else
      update telima.restaurant_orders set status = 'ready' where id = v_o.id returning * into v_o;
      perform telima.notify_user(v_o.customer_id, 'restaurant_order_ready', 'Commande prête',
        'Vous pouvez passer la retirer chez ' || v_r.name || '.', jsonb_build_object('restaurant_order_id', v_o.id));
    end if;
  elsif p_action = 'handed' and v_o.mode = 'pickup' and v_o.status in ('ready', 'accepted', 'preparing') then
    update telima.restaurant_orders set status = 'delivered', payment_status = 'paid' where id = v_o.id returning * into v_o;
  elsif p_action = 'paid' and v_o.status <> 'cancelled' then
    update telima.restaurant_orders set payment_status = 'paid' where id = v_o.id returning * into v_o;
  else
    raise exception 'Action impossible pour une commande « % »', v_o.status using errcode = 'P0001';
  end if;
  return v_o;
end $$;

-- Client : annuler tant que le restaurant n'a pas accepté
create or replace function telima.cancel_restaurant_order(p_order_id uuid)
returns telima.restaurant_orders language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_o telima.restaurant_orders;
begin
  select * into v_o from telima.restaurant_orders where id = p_order_id and customer_id = v_uid for update;
  if not found then raise exception 'Commande introuvable' using errcode = 'P0002'; end if;
  if v_o.status <> 'sent' then raise exception 'Le restaurant a déjà accepté : appelez-le pour annuler' using errcode = 'P0001'; end if;
  update telima.restaurant_orders set status = 'cancelled' where id = v_o.id returning * into v_o;
  perform telima.notify_user((select owner_id from telima.restaurants where id = v_o.restaurant_id), 'restaurant_order_cancelled',
    'Commande annulée', v_o.code, jsonb_build_object('restaurant_order_id', v_o.id));
  return v_o;
end $$;

-- La commande suit sa livraison
create or replace function telima.tg_restaurant_follow_delivery()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_o telima.restaurant_orders;
begin
  select * into v_o from telima.restaurant_orders where delivery_id = new.id for update;
  if not found or v_o.status in ('delivered', 'cancelled', 'rejected') then return new; end if;
  if new.status in ('picked_up', 'in_transit', 'at_dropoff') and v_o.status <> 'out_for_delivery' then
    update telima.restaurant_orders set status = 'out_for_delivery' where id = v_o.id;
  elsif new.status in ('handed_over', 'completed') then
    update telima.restaurant_orders set status = 'delivered', payment_status = 'paid' where id = v_o.id;
  elsif new.status = 'cancelled' then
    update telima.restaurant_orders set status = 'cancelled' where id = v_o.id;
    perform telima.notify_user(v_o.customer_id, 'restaurant_order_cancelled', 'Livraison annulée', v_o.code,
                               jsonb_build_object('restaurant_order_id', v_o.id));
  end if;
  return new;
end $$;
create trigger trg_restaurant_follow_delivery after update of status on telima.deliveries
  for each row when (old.status is distinct from new.status) execute function telima.tg_restaurant_follow_delivery();

-- Statistiques du restaurateur
create or replace function telima.restaurant_dashboard(p_restaurant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if not telima.is_restaurant_owner(p_restaurant_id) and not telima.is_staff() then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'orders_today', (select count(*) from telima.restaurant_orders where restaurant_id = p_restaurant_id and created_at >= date_trunc('day', now())),
    'sales_today', coalesce((select sum(items_total) from telima.restaurant_orders where restaurant_id = p_restaurant_id
                              and status = 'delivered' and updated_at >= date_trunc('day', now())), 0),
    'pending', (select count(*) from telima.restaurant_orders where restaurant_id = p_restaurant_id and status in ('sent', 'accepted', 'preparing')),
    'in_delivery', (select count(*) from telima.restaurant_orders where restaurant_id = p_restaurant_id and status in ('ready', 'out_for_delivery') and mode = 'delivery'),
    'items', (select count(*) from telima.restaurant_menu_items where restaurant_id = p_restaurant_id),
    'unavailable', (select count(*) from telima.restaurant_menu_items where restaurant_id = p_restaurant_id and not is_available));
end $$;

-- Administrateur : suspendre ou rétablir un restaurant
create or replace function telima.admin_set_restaurant_status(p_restaurant_id uuid, p_status telima.place_status)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_r telima.restaurants;
begin
  perform telima.require_staff();
  update telima.restaurants set status = p_status where id = p_restaurant_id returning * into v_r;
  if not found then raise exception 'Restaurant introuvable' using errcode = 'P0002'; end if;
  perform telima.log_admin_action('restaurant_status', 'restaurant', p_restaurant_id::text, jsonb_build_object('status', p_status));
  perform telima.notify_user(v_r.owner_id, 'restaurant_status',
    case when p_status = 'approved' then 'Restaurant rétabli' else 'Restaurant suspendu' end,
    v_r.name, jsonb_build_object('restaurant_id', p_restaurant_id));
end $$;

-- ---------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function telima.restaurant_by_slug(text),
  telima.find_restaurants(double precision, double precision, numeric, text, boolean, integer),
  telima.register_restaurant(jsonb), telima.restaurant_delivery_fee(uuid, double precision, double precision),
  telima.create_restaurant_order(jsonb), telima.restaurant_order_action(uuid, text, text),
  telima.cancel_restaurant_order(uuid), telima.restaurant_dashboard(uuid),
  telima.admin_set_restaurant_status(uuid, telima.place_status), telima.is_restaurant_owner(uuid),
  telima.make_restaurant_slug(text) from public, anon, authenticated;
-- Lecture publique (lien partagé, sans compte)
grant execute on function telima.restaurant_by_slug(text),
  telima.find_restaurants(double precision, double precision, numeric, text, boolean, integer) to anon, authenticated, service_role;
grant execute on function telima.register_restaurant(jsonb), telima.restaurant_delivery_fee(uuid, double precision, double precision),
  telima.create_restaurant_order(jsonb), telima.restaurant_order_action(uuid, text, text),
  telima.cancel_restaurant_order(uuid), telima.restaurant_dashboard(uuid),
  telima.admin_set_restaurant_status(uuid, telima.place_status), telima.is_restaurant_owner(uuid) to authenticated, service_role;
