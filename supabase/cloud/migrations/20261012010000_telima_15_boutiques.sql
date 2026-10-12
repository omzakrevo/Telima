-- Module « Boutiques » (vêtements, chaussures, accessoires…) : un commerçant crée sa boutique et son catalogue,
-- obtient un lien public à partager (https://…/b/<slug>), et les clients commandent directement chez lui.
-- Même principe que le module Restaurants, avec des articles à tailles et couleurs et un stock.
-- La livraison réutilise telima.deliveries : une commande livrée = une livraison ordinaire (livreur Telima).
-- Paiement : espèces à la remise (le livreur encaisse le montant des articles pour la boutique).

create type telima.shop_order_status as enum
  ('sent', 'accepted', 'preparing', 'ready', 'out_for_delivery', 'delivered', 'rejected', 'cancelled');

-- ---------------------------------------------------------------------
-- Boutiques
-- ---------------------------------------------------------------------
create table telima.shops (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references telima.users(id) on delete cascade,
  slug             text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 2 and 50),
  name             text not null check (char_length(name) between 2 and 80),
  description      text check (description is null or char_length(description) <= 500),
  shop_type          text,                                     -- « Vêtements femme, Chaussures, Accessoires… »
  phone            text,
  city_id          uuid references telima.cities(id) on delete set null,
  neighborhood     text,
  address          text,
  lat              double precision not null check (lat between -90 and 90),
  lng              double precision not null check (lng between -180 and 180),
  logo_path        text,                                     -- compartiment public telima-boutiques
  cover_path       text,
  opening_hours    text,
  accepting_orders boolean not null default true,            -- bouton « Ouvert / Fermé » du commerçant
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
create index idx_shops_owner on telima.shops(owner_id);
create index idx_shops_status on telima.shops(status);
create index idx_shops_geo on telima.shops(lat, lng);
create trigger trg_shops_updated before update on telima.shops
  for each row execute function telima.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Catalogue : catégories et articles
-- ---------------------------------------------------------------------
create table telima.shop_categories (
  id            uuid primary key default gen_random_uuid(),
  shop_id uuid not null references telima.shops(id) on delete cascade,
  name          text not null check (char_length(name) between 1 and 60),
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);
create index idx_shop_categories_shop on telima.shop_categories(shop_id, sort_order);

create table telima.shop_products (
  id            uuid primary key default gen_random_uuid(),
  shop_id uuid not null references telima.shops(id) on delete cascade,
  category_id   uuid references telima.shop_categories(id) on delete set null,
  name          text not null check (char_length(name) between 1 and 100),
  description   text check (description is null or char_length(description) <= 300),
  price         integer not null check (price >= 0),
  photo_path    text,
  is_available  boolean not null default true,               -- « indisponible » (masqué à la vente)
  sizes         text[] not null default '{}',                -- tailles proposées (S, M, L, 42…) ; vide = pas de choix
  colors        text[] not null default '{}',                -- couleurs proposées ; vide = pas de choix
  stock         integer check (stock is null or stock >= 0), -- null = quantité non suivie
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (cardinality(sizes) <= 20 and cardinality(colors) <= 20)
);
create index idx_shop_products_shop on telima.shop_products(shop_id, sort_order);
create index idx_shop_products_category on telima.shop_products(category_id);
create trigger trg_shop_products_updated before update on telima.shop_products
  for each row execute function telima.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Commandes
-- ---------------------------------------------------------------------
create table telima.shop_orders (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,
  customer_id     uuid not null references telima.users(id) on delete restrict,
  shop_id   uuid not null references telima.shops(id) on delete restrict,
  mode            text not null check (mode in ('pickup', 'delivery')),
  status          telima.shop_order_status not null default 'sent',
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
create index idx_shop_orders_customer on telima.shop_orders(customer_id, created_at desc);
create index idx_shop_orders_shop on telima.shop_orders(shop_id, created_at desc);
create index idx_shop_orders_delivery on telima.shop_orders(delivery_id);
create trigger trg_shop_orders_updated before update on telima.shop_orders
  for each row execute function telima.tg_set_updated_at();

create table telima.shop_order_items (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references telima.shop_orders(id) on delete cascade,
  item_id    uuid references telima.shop_products(id) on delete set null,
  name       text not null,
  qty        integer not null check (qty between 1 and 50),
  unit_price integer not null check (unit_price >= 0),
  size       text,
  color      text,
  note       text
);
create index idx_shop_order_items_order on telima.shop_order_items(order_id);

-- ---------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------
create or replace function telima.is_shop_owner(p_shop uuid)
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (select 1 from telima.shops where id = p_shop and owner_id = auth.uid());
$$;

-- Lien lisible : « Chez Awa » -> chez-awa ; ajoute un suffixe si déjà pris.
create or replace function telima.make_shop_slug(p_name text)
returns text language plpgsql volatile set search_path = telima, public as $$
declare v_base text; v_slug text; v_try int := 0;
begin
  v_base := lower(translate(coalesce(p_name, ''), 'àâäÀÂÄéèêëÉÈÊËîïÎÏôöÔÖùûüÙÛÜçÇ', 'aaaaaaeeeeeeeeiiiioooouuuuuucc'));
  v_base := regexp_replace(v_base, '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  v_base := left(v_base, 40);
  v_base := trim(both '-' from v_base);
  if char_length(v_base) < 2 then v_base := 'boutique'; end if;
  v_slug := v_base;
  while exists (select 1 from telima.shops where slug = v_slug) loop
    v_try := v_try + 1;
    v_slug := v_base || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, case when v_try < 4 then 3 else 6 end);
  end loop;
  return v_slug;
end $$;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table telima.shops enable row level security;
alter table telima.shop_categories enable row level security;
alter table telima.shop_products enable row level security;
alter table telima.shop_orders enable row level security;
alter table telima.shop_order_items enable row level security;

create policy shops_read on telima.shops for select
  using (status = 'approved' or owner_id = auth.uid() or telima.is_staff());
create policy shops_admin on telima.shops for all using (telima.is_staff()) with check (telima.is_staff());
create policy shops_owner_update on telima.shops for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy shops_owner_delete on telima.shops for delete using (owner_id = auth.uid());

create policy shop_categories_read on telima.shop_categories for select
  using (exists (select 1 from telima.shops r where r.id = shop_id
                 and (r.status = 'approved' or r.owner_id = auth.uid() or telima.is_staff())));
create policy shop_categories_owner on telima.shop_categories for all
  using (telima.is_shop_owner(shop_id) or telima.is_staff())
  with check (telima.is_shop_owner(shop_id) or telima.is_staff());

create policy shop_products_read on telima.shop_products for select
  using (exists (select 1 from telima.shops r where r.id = shop_id
                 and (r.status = 'approved' or r.owner_id = auth.uid() or telima.is_staff())));
create policy shop_products_owner on telima.shop_products for all
  using (telima.is_shop_owner(shop_id) or telima.is_staff())
  with check (telima.is_shop_owner(shop_id) or telima.is_staff());

create policy shop_orders_read on telima.shop_orders for select
  using (customer_id = auth.uid() or telima.is_shop_owner(shop_id) or telima.is_staff());
create policy shop_order_items_read on telima.shop_order_items for select
  using (exists (select 1 from telima.shop_orders o where o.id = order_id
                 and (o.customer_id = auth.uid() or telima.is_shop_owner(o.shop_id) or telima.is_staff())));

grant select on telima.shops, telima.shop_categories, telima.shop_products to authenticated;
grant select on telima.shop_orders, telima.shop_order_items to authenticated;
grant update, delete on telima.shops to authenticated;
grant insert, update, delete on telima.shop_categories, telima.shop_products to authenticated;

-- Le commerçant ne peut ni se valider lui-même, ni changer de propriétaire, ni casser le lien déjà partagé
create or replace function telima.tg_shops_guard()
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
create trigger trg_shops_guard before update on telima.shops
  for each row execute function telima.tg_shops_guard();

-- Une catégorie et un article doivent appartenir à la même boutique
create or replace function telima.tg_shop_product_category()
returns trigger language plpgsql as $$
begin
  if new.category_id is not null and not exists (
       select 1 from telima.shop_categories c where c.id = new.category_id and c.shop_id = new.shop_id) then
    raise exception 'Catégorie invalide' using errcode = '22023';
  end if;
  return new;
end $$;
create trigger trg_shop_product_category before insert or update on telima.shop_products
  for each row execute function telima.tg_shop_product_category();

-- ---------------------------------------------------------------------
-- Photos : compartiment public (logos, couvertures, articles) ; chacun écrit dans son dossier
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('telima-boutiques', 'telima-boutiques', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy telima_shops_upload_own on storage.objects for insert to authenticated
  with check (bucket_id = 'telima-boutiques' and (storage.foldername(name))[1] = auth.uid()::text);
create policy telima_shops_read on storage.objects for select using (bucket_id = 'telima-boutiques');
create policy telima_shops_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'telima-boutiques' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- Créer sa boutique : actif tout de suite, le lien est renvoyé dans « slug »
-- p = { name, description?, shop_type?, phone?, neighborhood?, address, lat, lng, opening_hours?,
--       accepts_pickup?, delivers?, delivery_radius_km?, min_order?, prep_minutes?, logo_path?, cover_path? }
-- ---------------------------------------------------------------------
create or replace function telima.register_shop(p jsonb)
returns telima.shops language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_row telima.shops;
  v_pickup boolean := coalesce((p->>'accepts_pickup')::boolean, true);
  v_delivers boolean := coalesce((p->>'delivers')::boolean, true);
begin
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'Le nom de la boutique est obligatoire' using errcode = '22023'; end if;
  if p->>'lat' is null or p->>'lng' is null then raise exception 'Placez votre boutique sur la carte' using errcode = '22023'; end if;
  if not (v_pickup or v_delivers) then raise exception 'Choisissez au moins le retrait ou la livraison' using errcode = '22023'; end if;
  if (select count(*) from telima.shops where owner_id = v_uid) >= 5 then
    raise exception 'Vous avez atteint le maximum de 5 boutiques' using errcode = 'P0001';
  end if;

  insert into telima.shops(owner_id, slug, name, description, shop_type, phone, city_id, neighborhood, address, lat, lng,
                                 opening_hours, accepts_pickup, delivers, delivery_radius_km, min_order, prep_minutes, logo_path, cover_path)
  values (v_uid, telima.make_shop_slug(p->>'name'), trim(p->>'name'), nullif(trim(p->>'description'), ''),
          nullif(trim(p->>'shop_type'), ''), case when coalesce(trim(p->>'phone'), '') <> '' then telima.normalize_phone(p->>'phone') end,
          telima.find_city((p->>'lat')::float8, (p->>'lng')::float8),
          nullif(trim(p->>'neighborhood'), ''), nullif(trim(p->>'address'), ''),
          (p->>'lat')::float8, (p->>'lng')::float8, nullif(trim(p->>'opening_hours'), ''),
          v_pickup, v_delivers, coalesce((p->>'delivery_radius_km')::numeric, 5),
          coalesce((p->>'min_order')::int, 0), coalesce((p->>'prep_minutes')::int, 20),
          nullif(p->>'logo_path', ''), nullif(p->>'cover_path', ''))
  returning * into v_row;
  perform telima.notify_staff('shop_new', 'Nouvelle boutique', v_row.name, jsonb_build_object('shop_id', v_row.id));
  return v_row;
end $$;

-- ---------------------------------------------------------------------
-- Page publique d'une boutique, lisible SANS compte (lien partagé)
-- ---------------------------------------------------------------------
create or replace function telima.shop_by_slug(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_r telima.shops;
begin
  select * into v_r from telima.shops where slug = lower(trim(p_slug)) and status = 'approved';
  if not found then return null; end if;
  return jsonb_build_object(
    'id', v_r.id, 'slug', v_r.slug, 'name', v_r.name, 'description', v_r.description, 'shop_type', v_r.shop_type,
    'phone', v_r.phone, 'neighborhood', v_r.neighborhood, 'address', v_r.address, 'lat', v_r.lat, 'lng', v_r.lng,
    'logo_path', v_r.logo_path, 'cover_path', v_r.cover_path, 'opening_hours', v_r.opening_hours,
    'accepting_orders', v_r.accepting_orders, 'accepts_pickup', v_r.accepts_pickup, 'delivers', v_r.delivers,
    'delivery_radius_km', v_r.delivery_radius_km, 'min_order', v_r.min_order, 'prep_minutes', v_r.prep_minutes,
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.sort_order, c.created_at)
                              from telima.shop_categories c where c.shop_id = v_r.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'category_id', i.category_id, 'name', i.name, 'description', i.description,
                          'price', i.price, 'photo_path', i.photo_path, 'is_available', i.is_available,
                          'sizes', i.sizes, 'colors', i.colors, 'stock', i.stock)
                        order by i.sort_order, i.created_at)
                         from telima.shop_products i where i.shop_id = v_r.id), '[]'::jsonb));
end $$;

-- Boutiques autour de moi (liste dans l'application, lecture publique)
create or replace function telima.find_shops(
  p_lat double precision, p_lng double precision, p_max_km numeric default 15,
  p_query text default null, p_delivers boolean default false, p_limit integer default 60)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_res jsonb;
begin
  select coalesce(jsonb_agg(r order by (r->>'distance_km')::numeric), '[]'::jsonb) into v_res from (
    select jsonb_build_object(
      'id', x.id, 'slug', x.slug, 'name', x.name, 'shop_type', x.shop_type, 'neighborhood', x.neighborhood,
      'address', x.address, 'lat', x.lat, 'lng', x.lng, 'logo_path', x.logo_path, 'cover_path', x.cover_path,
      'opening_hours', x.opening_hours, 'accepting_orders', x.accepting_orders, 'accepts_pickup', x.accepts_pickup,
      'delivers', x.delivers, 'delivery_radius_km', x.delivery_radius_km, 'min_order', x.min_order,
      'prep_minutes', x.prep_minutes, 'phone', x.phone,
      'distance_km', round(telima.haversine_km(p_lat, p_lng, x.lat, x.lng)::numeric, 2)) as r
    from telima.shops x
    where x.status = 'approved'
      and (not p_delivers or x.delivers)
      and (p_query is null or x.name ilike '%' || p_query || '%' or x.shop_type ilike '%' || p_query || '%'
           or x.neighborhood ilike '%' || p_query || '%'
           or exists (select 1 from telima.shop_products i where i.shop_id = x.id and i.name ilike '%' || p_query || '%'))
      and telima.haversine_km(p_lat, p_lng, x.lat, x.lng) <= p_max_km
    order by telima.haversine_km(p_lat, p_lng, x.lat, x.lng)
    limit greatest(1, least(coalesce(p_limit, 60), 200))
  ) t;
  return v_res;
end $$;

-- ---------------------------------------------------------------------
-- Frais de livraison : grille des tarifs de livraison de Telima (moto), comme pour le gaz
-- ---------------------------------------------------------------------
create or replace function telima.shop_delivery_fee(p_shop_id uuid, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_r telima.shops; v_q jsonb; v_km numeric;
begin
  select * into v_r from telima.shops where id = p_shop_id and status = 'approved';
  if not found then raise exception 'Boutique introuvable' using errcode = 'P0002'; end if;
  if not v_r.delivers then raise exception 'Cette boutique ne livre pas' using errcode = 'P0001'; end if;
  v_km := telima.haversine_km(v_r.lat, v_r.lng, p_lat, p_lng);
  if v_km > v_r.delivery_radius_km then
    raise exception 'Adresse trop éloignée (rayon de livraison : % km)', v_r.delivery_radius_km using errcode = 'P0001';
  end if;
  v_q := telima.quote_delivery(v_r.lat, v_r.lng, p_lat, p_lng, 'moto', 'petit', false, 3, 'petit_colis', null, false);
  return jsonb_build_object('fee', (v_q->>'total_price')::int, 'distance_km', (v_q->>'distance_km')::numeric);
end $$;

-- ---------------------------------------------------------------------
-- Commande : les prix sont relus côté serveur (jamais ceux envoyés par l'application)
-- p = { shop_id, mode:'pickup'|'delivery', items:[{item_id, qty, size?, color?, note?}], note?, customer_name?, customer_phone?,
--       dropoff:{address,lat,lng,note}, payment_method }
-- ---------------------------------------------------------------------
create or replace function telima.create_shop_order(p jsonb)
returns telima.shop_orders language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_user telima.users;
  v_r telima.shops;
  v_mode text := coalesce(p->>'mode', 'pickup');
  v_item jsonb;
  v_menu telima.shop_products;
  v_size text;
  v_color text;
  v_qty int;
  v_items_total int := 0;
  v_fee int := 0;
  v_km numeric;
  v_drop jsonb := p->'dropoff';
  v_method telima.payment_method := coalesce(p->>'payment_method', 'cash_on_delivery')::telima.payment_method;
  v_row telima.shop_orders;
begin
  select * into v_user from telima.users where id = v_uid;
  select * into v_r from telima.shops where id = (p->>'shop_id')::uuid and status = 'approved';
  if not found then raise exception 'Boutique introuvable' using errcode = 'P0002'; end if;
  if not v_r.accepting_orders then raise exception 'Cette boutique ne prend pas de commande pour le moment' using errcode = 'P0001'; end if;
  if v_mode not in ('pickup', 'delivery') then raise exception 'Mode invalide' using errcode = '22023'; end if;
  if v_mode = 'pickup' and not v_r.accepts_pickup then raise exception 'Cette boutique ne propose pas le retrait' using errcode = 'P0001'; end if;
  if v_mode = 'delivery' and not v_r.delivers then raise exception 'Cette boutique ne livre pas' using errcode = 'P0001'; end if;
  if v_method not in ('cash', 'cash_on_delivery') then
    raise exception 'Pour le moment, les articles se règlent en espèces' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') = 0 then
    raise exception 'Choisissez au moins un article' using errcode = '22023';
  end if;
  if jsonb_array_length(p->'items') > 60 then raise exception 'Trop de lignes dans la commande' using errcode = '22023'; end if;
  if v_mode = 'delivery' then
    if v_drop is null or coalesce(trim(v_drop->>'address'), '') = '' then
      raise exception 'Adresse de livraison obligatoire' using errcode = '22023';
    end if;
    select (f->>'fee')::int, (f->>'distance_km')::numeric into v_fee, v_km
      from (select telima.shop_delivery_fee(v_r.id, (v_drop->>'lat')::float8, (v_drop->>'lng')::float8) f) x;
  end if;

  insert into telima.shop_orders(code, customer_id, shop_id, mode, customer_name, customer_phone, note,
      dropoff_address, dropoff_lat, dropoff_lng, dropoff_note, items_total, delivery_fee, total, distance_km, payment_method)
  values (telima.next_code('shop_order', 'BOU'), v_uid, v_r.id, v_mode,
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
    select * into v_menu from telima.shop_products where id = (v_item->>'item_id')::uuid and shop_id = v_r.id for update;
    if not found then raise exception 'Article introuvable' using errcode = 'P0002'; end if;
    if not v_menu.is_available then raise exception '« % » n''est plus disponible', v_menu.name using errcode = 'P0001'; end if;
    v_size := nullif(trim(coalesce(v_item->>'size', '')), '');
    v_color := nullif(trim(coalesce(v_item->>'color', '')), '');
    if cardinality(v_menu.sizes) > 0 and (v_size is null or not (v_size = any (v_menu.sizes))) then
      raise exception 'Choisissez une taille pour « % »', v_menu.name using errcode = '22023';
    end if;
    if cardinality(v_menu.colors) > 0 and (v_color is null or not (v_color = any (v_menu.colors))) then
      raise exception 'Choisissez une couleur pour « % »', v_menu.name using errcode = '22023';
    end if;
    if cardinality(v_menu.sizes) = 0 then v_size := null; end if;
    if cardinality(v_menu.colors) = 0 then v_color := null; end if;
    -- Stock : retiré tout de suite (remis si la commande est refusée ou annulée)
    if v_menu.stock is not null then
      update telima.shop_products set stock = stock - v_qty where id = v_menu.id and stock >= v_qty;
      if not found then
        raise exception 'Stock insuffisant pour « % » (reste : %)', v_menu.name, v_menu.stock using errcode = 'P0001';
      end if;
    end if;
    insert into telima.shop_order_items(order_id, item_id, name, qty, unit_price, size, color, note)
    values (v_row.id, v_menu.id, v_menu.name, v_qty, v_menu.price, v_size, v_color, nullif(left(trim(coalesce(v_item->>'note', '')), 200), ''));
    v_items_total := v_items_total + v_menu.price * v_qty;
  end loop;

  if v_items_total < v_r.min_order then
    raise exception 'Commande minimum : % FCFA', v_r.min_order using errcode = 'P0001';
  end if;

  update telima.shop_orders set items_total = v_items_total, total = v_items_total + v_fee
   where id = v_row.id returning * into v_row;

  perform telima.notify_user(v_r.owner_id, 'shop_order_new', 'Nouvelle commande',
    v_row.code || ' · ' || v_row.total || ' FCFA', jsonb_build_object('shop_order_id', v_row.id, 'shop_id', v_r.id));
  return v_row;
end $$;

-- Remet en stock les articles d'une commande refusée ou annulée (somme par article).
create or replace function telima._shop_restock(p_order uuid)
returns void language sql security definer set search_path = telima, public as $$
  update telima.shop_products p set stock = p.stock + t.q
    from (select item_id, sum(qty)::int as q from telima.shop_order_items
           where order_id = p_order and item_id is not null group by item_id) t
   where p.id = t.item_id and p.stock is not null;
$$;

-- ---------------------------------------------------------------------
-- Commerçant / administrateur : faire avancer une commande
-- p_action : accept | reject | preparing | ready | handed (retrait remis) | paid
-- ---------------------------------------------------------------------
create or replace function telima.shop_order_action(p_order_id uuid, p_action text, p_reason text default null)
returns telima.shop_orders language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_o telima.shop_orders;
  v_r telima.shops;
  v_del telima.deliveries;
  v_desc text;
begin
  select * into v_o from telima.shop_orders where id = p_order_id for update;
  if not found then raise exception 'Commande introuvable' using errcode = 'P0002'; end if;
  select * into v_r from telima.shops where id = v_o.shop_id;
  if v_r.owner_id is distinct from v_uid and not telima.is_staff() then
    raise exception 'Cette commande ne concerne pas votre boutique' using errcode = '42501';
  end if;

  if p_action = 'accept' and v_o.status = 'sent' then
    update telima.shop_orders set status = 'accepted' where id = v_o.id returning * into v_o;
    perform telima.notify_user(v_o.customer_id, 'shop_order_accepted', 'Commande acceptée',
      v_r.name || ' prépare votre commande (environ ' || v_r.prep_minutes || ' min).',
      jsonb_build_object('shop_order_id', v_o.id));
  elsif p_action = 'reject' and v_o.status in ('sent', 'accepted', 'preparing') then
    update telima.shop_orders set status = 'rejected', reject_reason = nullif(trim(p_reason), '') where id = v_o.id returning * into v_o;
    perform telima._shop_restock(v_o.id);
    perform telima.notify_user(v_o.customer_id, 'shop_order_rejected', 'Commande refusée',
      v_r.name || coalesce(' : ' || v_o.reject_reason, ''), jsonb_build_object('shop_order_id', v_o.id));
  elsif p_action = 'preparing' and v_o.status in ('sent', 'accepted') then
    update telima.shop_orders set status = 'preparing' where id = v_o.id returning * into v_o;
    perform telima.notify_user(v_o.customer_id, 'shop_order_preparing', 'En préparation',
      v_r.name || ' prépare votre commande.', jsonb_build_object('shop_order_id', v_o.id));
  elsif p_action = 'ready' and v_o.status in ('sent', 'accepted', 'preparing') then
    if v_o.mode = 'delivery' then
      select string_agg(i.qty || ' × ' || i.name || coalesce(' (' || concat_ws(', ', i.size, i.color) || ')', ''), ', ') into v_desc
        from telima.shop_order_items i where i.order_id = v_o.id;
      v_del := telima._insert_delivery(
        jsonb_build_object(
          'pickup', jsonb_build_object('address', coalesce(v_r.address, v_r.name), 'lat', v_r.lat, 'lng', v_r.lng,
                                       'contact_name', v_r.name, 'contact_phone', coalesce(v_r.phone, v_o.customer_phone)),
          'dropoff', jsonb_build_object('address', v_o.dropoff_address, 'lat', v_o.dropoff_lat, 'lng', v_o.dropoff_lng,
                                        'contact_name', v_o.customer_name, 'contact_phone', v_o.customer_phone,
                                        'instructions', v_o.dropoff_note),
          'package', jsonb_build_object('category', 'petit_colis', 'size', 'petit', 'weight_kg', 3,
                       'description', 'Commande boutique ' || v_r.name || ' : ' || v_desc || ' — à encaisser auprès du client : ' || v_o.items_total || ' FCFA'),
          'vehicle_type', 'moto', 'payment_method', 'cash'),
        v_o.customer_id, v_o.customer_name, v_o.customer_phone, v_uid, 'app', null, 1, false, null, null, v_o.delivery_fee);
      perform telima.notify_nearby_drivers(v_del);
      update telima.shop_orders set status = 'ready', delivery_id = v_del.id where id = v_o.id returning * into v_o;
      perform telima.notify_user(v_o.customer_id, 'shop_order_ready', 'Commande prête',
        'Un livreur est recherché pour vous livrer.', jsonb_build_object('shop_order_id', v_o.id, 'delivery_id', v_del.id));
    else
      update telima.shop_orders set status = 'ready' where id = v_o.id returning * into v_o;
      perform telima.notify_user(v_o.customer_id, 'shop_order_ready', 'Commande prête',
        'Vous pouvez passer la retirer chez ' || v_r.name || '.', jsonb_build_object('shop_order_id', v_o.id));
    end if;
  elsif p_action = 'handed' and v_o.mode = 'pickup' and v_o.status in ('ready', 'accepted', 'preparing') then
    update telima.shop_orders set status = 'delivered', payment_status = 'paid' where id = v_o.id returning * into v_o;
  elsif p_action = 'paid' and v_o.status <> 'cancelled' then
    update telima.shop_orders set payment_status = 'paid' where id = v_o.id returning * into v_o;
  else
    raise exception 'Action impossible pour une commande « % »', v_o.status using errcode = 'P0001';
  end if;
  return v_o;
end $$;

-- Client : annuler tant que la boutique n'a pas accepté
create or replace function telima.cancel_shop_order(p_order_id uuid)
returns telima.shop_orders language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_o telima.shop_orders;
begin
  select * into v_o from telima.shop_orders where id = p_order_id and customer_id = v_uid for update;
  if not found then raise exception 'Commande introuvable' using errcode = 'P0002'; end if;
  if v_o.status <> 'sent' then raise exception 'La boutique a déjà accepté : appelez-la pour annuler' using errcode = 'P0001'; end if;
  update telima.shop_orders set status = 'cancelled' where id = v_o.id returning * into v_o;
  perform telima._shop_restock(v_o.id);
  perform telima.notify_user((select owner_id from telima.shops where id = v_o.shop_id), 'shop_order_cancelled',
    'Commande annulée', v_o.code, jsonb_build_object('shop_order_id', v_o.id));
  return v_o;
end $$;

-- La commande suit sa livraison
create or replace function telima.tg_shop_follow_delivery()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_o telima.shop_orders;
begin
  select * into v_o from telima.shop_orders where delivery_id = new.id for update;
  if not found or v_o.status in ('delivered', 'cancelled', 'rejected') then return new; end if;
  if new.status in ('picked_up', 'in_transit', 'at_dropoff') and v_o.status <> 'out_for_delivery' then
    update telima.shop_orders set status = 'out_for_delivery' where id = v_o.id;
  elsif new.status in ('handed_over', 'completed') then
    update telima.shop_orders set status = 'delivered', payment_status = 'paid' where id = v_o.id;
  elsif new.status = 'cancelled' then
    update telima.shop_orders set status = 'cancelled' where id = v_o.id;
    perform telima._shop_restock(v_o.id);
    perform telima.notify_user(v_o.customer_id, 'shop_order_cancelled', 'Livraison annulée', v_o.code,
                               jsonb_build_object('shop_order_id', v_o.id));
  end if;
  return new;
end $$;
create trigger trg_shop_follow_delivery after update of status on telima.deliveries
  for each row when (old.status is distinct from new.status) execute function telima.tg_shop_follow_delivery();

-- Statistiques du commerçant
create or replace function telima.shop_dashboard(p_shop_id uuid)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if not telima.is_shop_owner(p_shop_id) and not telima.is_staff() then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'orders_today', (select count(*) from telima.shop_orders where shop_id = p_shop_id and created_at >= date_trunc('day', now())),
    'sales_today', coalesce((select sum(items_total) from telima.shop_orders where shop_id = p_shop_id
                              and status = 'delivered' and updated_at >= date_trunc('day', now())), 0),
    'pending', (select count(*) from telima.shop_orders where shop_id = p_shop_id and status in ('sent', 'accepted', 'preparing')),
    'in_delivery', (select count(*) from telima.shop_orders where shop_id = p_shop_id and status in ('ready', 'out_for_delivery') and mode = 'delivery'),
    'items', (select count(*) from telima.shop_products where shop_id = p_shop_id),
    'unavailable', (select count(*) from telima.shop_products where shop_id = p_shop_id and (not is_available or stock = 0)),
    'low_stock', (select count(*) from telima.shop_products where shop_id = p_shop_id and stock is not null and stock between 1 and 3));
end $$;

-- Administrateur : suspendre ou rétablir une boutique
create or replace function telima.admin_set_shop_status(p_shop_id uuid, p_status telima.place_status)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_r telima.shops;
begin
  perform telima.require_staff();
  update telima.shops set status = p_status where id = p_shop_id returning * into v_r;
  if not found then raise exception 'Boutique introuvable' using errcode = 'P0002'; end if;
  perform telima.log_admin_action('shop_status', 'boutique', p_shop_id::text, jsonb_build_object('status', p_status));
  perform telima.notify_user(v_r.owner_id, 'shop_status',
    case when p_status = 'approved' then 'Boutique rétablie' else 'Boutique suspendue' end,
    v_r.name, jsonb_build_object('shop_id', p_shop_id));
end $$;

-- ---------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function telima.shop_by_slug(text),
  telima.find_shops(double precision, double precision, numeric, text, boolean, integer),
  telima.register_shop(jsonb), telima.shop_delivery_fee(uuid, double precision, double precision),
  telima.create_shop_order(jsonb), telima.shop_order_action(uuid, text, text),
  telima.cancel_shop_order(uuid), telima.shop_dashboard(uuid),
  telima.admin_set_shop_status(uuid, telima.place_status), telima.is_shop_owner(uuid),
  telima.make_shop_slug(text), telima._shop_restock(uuid) from public, anon, authenticated;
-- Lecture publique (lien partagé, sans compte)
grant execute on function telima.shop_by_slug(text),
  telima.find_shops(double precision, double precision, numeric, text, boolean, integer) to anon, authenticated, service_role;
grant execute on function telima.register_shop(jsonb), telima.shop_delivery_fee(uuid, double precision, double precision),
  telima.create_shop_order(jsonb), telima.shop_order_action(uuid, text, text),
  telima.cancel_shop_order(uuid), telima.shop_dashboard(uuid),
  telima.admin_set_shop_status(uuid, telima.place_status), telima.is_shop_owner(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- La suppression d'un utilisateur tient compte des boutiques et de leurs commandes
-- ---------------------------------------------------------------------
create or replace function telima.admin_delete_user_check(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_u telima.users;
  v_balance integer := 0;
  v_active_deliveries integer;
  v_pending_withdrawals integer;
  v_active_orders integer;
begin
  perform telima.require_admin();
  select * into v_u from telima.users where id = p_user_id;
  if not found then raise exception 'Utilisateur introuvable' using errcode = 'P0001'; end if;

  select coalesce(balance, 0) into v_balance from telima.wallets where user_id = p_user_id;
  v_balance := coalesce(v_balance, 0);

  select count(*) into v_active_deliveries from telima.deliveries d
   where d.status not in ('completed', 'cancelled')
     and (d.customer_id = p_user_id
          or d.driver_id in (select id from telima.drivers where user_id = p_user_id));

  select count(*) into v_pending_withdrawals from telima.withdrawals
   where user_id = p_user_id and status = 'pending';

  select (select count(*) from telima.restaurant_orders o
            where o.status in ('sent','accepted','preparing','ready','out_for_delivery')
              and (o.customer_id = p_user_id
                   or o.restaurant_id in (select id from telima.restaurants where owner_id = p_user_id)))
       + (select count(*) from telima.shop_orders o
            where o.status in ('sent','accepted','preparing','ready','out_for_delivery')
              and (o.customer_id = p_user_id
                   or o.shop_id in (select id from telima.shops where owner_id = p_user_id)))
       + (select count(*) from telima.gas_orders o
            where o.status in ('sent','accepted','preparing','ready','out_for_delivery')
              and (o.customer_id = p_user_id
                   or o.place_id in (select id from telima.places where owner_id = p_user_id)))
    into v_active_orders;

  return jsonb_build_object(
    'id', v_u.id, 'name', v_u.full_name, 'phone', v_u.phone, 'role', v_u.role,
    'is_self', p_user_id = auth.uid(),
    'is_admin', v_u.role = 'admin',
    'wallet_balance', v_balance,
    'active_deliveries', v_active_deliveries,
    'pending_withdrawals', v_pending_withdrawals,
    'active_orders', v_active_orders,
    'restaurants', (select count(*) from telima.restaurants where owner_id = p_user_id),
    'shops', (select count(*) from telima.shops where owner_id = p_user_id),
    'places', (select count(*) from telima.places where owner_id = p_user_id),
    'deliveries_total', (select count(*) from telima.deliveries where customer_id = p_user_id),
    'can_delete', p_user_id <> auth.uid() and v_u.role <> 'admin'
                  and v_active_deliveries = 0 and v_pending_withdrawals = 0 and v_active_orders = 0);
end $$;

create or replace function telima.admin_delete_user(p_user_id uuid, p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare
  v_admin uuid := telima.require_admin();
  v_chk jsonb;
  v_u telima.users;
begin
  if p_user_id = v_admin then
    raise exception 'Vous ne pouvez pas supprimer votre propre compte' using errcode = 'P0001';
  end if;
  select * into v_u from telima.users where id = p_user_id;
  if not found then raise exception 'Utilisateur introuvable' using errcode = 'P0001'; end if;
  if v_u.role = 'admin' then
    raise exception 'Retirez d''abord le rôle administrateur de ce compte avant de le supprimer' using errcode = 'P0001';
  end if;

  v_chk := telima.admin_delete_user_check(p_user_id);
  if (v_chk->>'active_deliveries')::int > 0 then
    raise exception 'Suppression impossible : % livraison(s) en cours pour ce compte', v_chk->>'active_deliveries' using errcode = 'P0001';
  end if;
  if (v_chk->>'active_orders')::int > 0 then
    raise exception 'Suppression impossible : % commande(s) de restaurant, de boutique ou de gaz en cours', v_chk->>'active_orders' using errcode = 'P0001';
  end if;
  if (v_chk->>'pending_withdrawals')::int > 0 then
    raise exception 'Suppression impossible : un retrait est en attente de paiement' using errcode = 'P0001';
  end if;
  if (v_chk->>'wallet_balance')::int <> 0 and not p_force then
    raise exception 'Le portefeuille contient % FCFA. Réglez-le d''abord, ou confirmez la suppression malgré le solde.', v_chk->>'wallet_balance' using errcode = 'P0001';
  end if;

  -- Trace dans le journal AVANT la suppression
  perform telima.log_admin_action('delete_user', 'users', p_user_id::text,
    jsonb_build_object('name', v_u.full_name, 'phone', v_u.phone, 'role', v_u.role,
                       'wallet_balance', v_chk->'wallet_balance', 'forced', p_force));

  -- Liens qui empêcheraient la suppression
  delete from telima.restaurant_orders
   where customer_id = p_user_id
      or restaurant_id in (select id from telima.restaurants where owner_id = p_user_id);
  delete from telima.shop_orders
   where customer_id = p_user_id
      or shop_id in (select id from telima.shops where owner_id = p_user_id);
  delete from telima.gas_orders
   where customer_id = p_user_id
      or place_id in (select id from telima.places where owner_id = p_user_id);
  delete from telima.food_orders
   where customer_id = p_user_id
      or business_id in (select id from telima.business_accounts where owner_id = p_user_id);
  delete from telima.business_accounts where owner_id = p_user_id;
  delete from telima.places where owner_id = p_user_id;
  update telima.app_releases set created_by = null where created_by = p_user_id;
  update public.businessbook_announcements set created_by = null where created_by = p_user_id;

  -- Suppression du compte : tout le reste suit en cascade (profil, livreur, portefeuille, notifications, etc.)
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('deleted', true, 'name', v_u.full_name, 'phone', v_u.phone);
end $$;
