-- Module « Gaz & carburant » (suite) : avis, promotions, abonnements vendeur, favoris, import OSM.

-- ---------------------------------------------------------------------
-- Avis
-- ---------------------------------------------------------------------
alter table telima.places add column rating_avg numeric(3,2), add column rating_count integer not null default 0;
alter table telima.gas_order_items add column original_price integer;

create table telima.place_reviews (
  id         uuid primary key default gen_random_uuid(),
  place_id   uuid not null references telima.places(id) on delete cascade,
  user_id    uuid not null references telima.users(id) on delete cascade,
  rating     smallint not null check (rating between 1 and 5),
  comment    text check (char_length(comment) <= 500),
  verified   boolean not null default false,       -- a commandé et reçu du gaz dans ce point
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (place_id, user_id)
);
create index idx_place_reviews_place on telima.place_reviews(place_id, created_at desc);
alter table telima.place_reviews enable row level security;
create policy place_reviews_staff on telima.place_reviews for all using (telima.is_staff()) with check (telima.is_staff());
grant select, delete on telima.place_reviews to authenticated;

create or replace function telima.tg_review_sync() returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_place uuid := coalesce(new.place_id, old.place_id);
begin
  perform set_config('telima.rating_sync', '1', true);
  update telima.places p set
    rating_avg = (select round(avg(rating)::numeric, 2) from telima.place_reviews where place_id = v_place),
    rating_count = (select count(*) from telima.place_reviews where place_id = v_place)
   where p.id = v_place;
  perform set_config('telima.rating_sync', '0', true);
  return null;
end $$;
create trigger trg_review_sync after insert or update or delete on telima.place_reviews
  for each row execute function telima.tg_review_sync();

create or replace function telima.tg_places_guard()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if not telima.is_staff() then
    if tg_op = 'UPDATE' then
      new.status := old.status; new.owner_id := old.owner_id; new.kind := old.kind;
      new.source := old.source; new.osm_id := old.osm_id;
      if coalesce(current_setting('telima.rating_sync', true), '0') <> '1' then
        new.rating_avg := old.rating_avg; new.rating_count := old.rating_count;
      end if;
    end if;
  end if;
  return new;
end $$;

create or replace function telima.review_place(p_place_id uuid, p_rating integer, p_comment text default null)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_place telima.places; v_ver boolean;
begin
  select * into v_place from telima.places where id = p_place_id and status = 'approved';
  if not found then raise exception 'Point introuvable' using errcode = 'P0002'; end if;
  if v_place.owner_id = v_uid then raise exception 'Vous ne pouvez pas noter votre propre point' using errcode = 'P0001'; end if;
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'Note entre 1 et 5' using errcode = '22023'; end if;
  v_ver := exists (select 1 from telima.gas_orders where place_id = p_place_id and customer_id = v_uid and status = 'delivered');
  insert into telima.place_reviews(place_id, user_id, rating, comment, verified)
  values (p_place_id, v_uid, p_rating, nullif(left(trim(coalesce(p_comment, '')), 500), ''), v_ver)
  on conflict (place_id, user_id) do update set rating = excluded.rating, comment = excluded.comment,
      verified = excluded.verified, updated_at = now();
  if v_place.owner_id is not null then
    perform telima.notify_user(v_place.owner_id, 'place_review', 'Nouvel avis ' || p_rating || '/5', v_place.name, jsonb_build_object('place_id', p_place_id));
  end if;
end $$;

create or replace function telima.delete_my_review(p_place_id uuid) returns void language plpgsql security definer set search_path = telima, public as $$
begin
  delete from telima.place_reviews where place_id = p_place_id and user_id = auth.uid();
end $$;

-- Avis publics d'un point (prénom seulement, jamais de téléphone)
create or replace function telima.place_reviews_list(p_place_id uuid, p_limit integer default 30)
returns jsonb language sql stable security definer set search_path = telima, public as $$
  select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb) from (
    select jsonb_build_object('id', r.id, 'rating', r.rating, 'comment', r.comment, 'verified', r.verified,
      'author', coalesce(nullif(split_part(u.full_name, ' ', 1), ''), 'Client'), 'mine', r.user_id = auth.uid(),
      'created_at', r.created_at) as x
    from telima.place_reviews r join telima.users u on u.id = r.user_id
    where r.place_id = p_place_id order by r.created_at desc limit greatest(1, least(coalesce(p_limit, 30), 100))) t;
$$;

-- ---------------------------------------------------------------------
-- Abonnements vendeur
-- ---------------------------------------------------------------------
create table telima.vendor_plans (
  code           text primary key,
  name           text not null,
  price_monthly  integer not null default 0 check (price_monthly >= 0),
  max_products   integer,                  -- null = illimité
  max_promotions integer,
  boost          integer not null default 0 check (boost between 0 and 5),   -- remonte dans les résultats
  features       text[] not null default '{}',
  sort_order     integer not null default 0,
  is_active      boolean not null default true
);
alter table telima.vendor_plans enable row level security;
create policy vendor_plans_read on telima.vendor_plans for select using (is_active or telima.is_staff());
create policy vendor_plans_admin on telima.vendor_plans for all using (telima.is_admin()) with check (telima.is_admin());
grant select on telima.vendor_plans to anon, authenticated;
grant insert, update, delete on telima.vendor_plans to authenticated;
insert into telima.vendor_plans(code, name, price_monthly, max_products, max_promotions, boost, features, sort_order) values
  ('free', 'Gratuit', 0, 6, 1, 0, '{"Fiche visible sur la carte","1 promotion à la fois","6 produits"}', 1),
  ('pro', 'Pro', 5000, 20, 5, 1, '{"Remonte dans les résultats","5 promotions à la fois","20 produits","Badge Recommandé"}', 2),
  ('premium', 'Premium', 10000, null, null, 2, '{"En tête des résultats","Promotions et produits illimités","Badge Sponsorisé","Priorité de validation"}', 3);

create table telima.vendor_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  place_id    uuid not null references telima.places(id) on delete cascade,
  plan_code   text not null references telima.vendor_plans(code),
  months      integer not null default 1 check (months between 1 and 12),
  amount      integer not null check (amount >= 0),
  status      text not null default 'pending' check (status in ('pending', 'active', 'rejected', 'ended')),
  payment_ref text,
  starts_at   timestamptz,
  ends_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index idx_vendor_subs_place on telima.vendor_subscriptions(place_id, created_at desc);
alter table telima.vendor_subscriptions enable row level security;
create policy vendor_subs_read on telima.vendor_subscriptions for select using (telima.is_place_owner(place_id) or telima.is_staff());
grant select on telima.vendor_subscriptions to authenticated;

-- Forfait en cours d'un point (Gratuit si aucun abonnement actif)
create or replace function telima.place_plan(p_place uuid) returns telima.vendor_plans language sql stable security definer set search_path = telima, public as $$
  select coalesce(
    (select vp from telima.vendor_subscriptions s join telima.vendor_plans vp on vp.code = s.plan_code
      where s.place_id = p_place and s.status = 'active' and s.ends_at > now() order by vp.price_monthly desc limit 1),
    (select vp from telima.vendor_plans vp where vp.code = 'free'));
$$;
create or replace function telima.place_boost(p_place uuid) returns integer language sql stable security definer set search_path = telima, public as $$
  select coalesce((telima.place_plan(p_place)).boost, 0);
$$;

create or replace function telima.vendor_request_subscription(p_place_id uuid, p_plan text, p_months integer, p_payment_ref text)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_plan telima.vendor_plans; v_place telima.places;
begin
  if not telima.is_place_owner(p_place_id) then raise exception 'Accès refusé' using errcode = '42501'; end if;
  select * into v_place from telima.places where id = p_place_id;
  select * into v_plan from telima.vendor_plans where code = p_plan and is_active and price_monthly > 0;
  if not found then raise exception 'Forfait introuvable' using errcode = 'P0002'; end if;
  if p_months is null or p_months not between 1 and 12 then raise exception 'Durée invalide' using errcode = '22023'; end if;
  if coalesce(trim(p_payment_ref), '') = '' then raise exception 'Indiquez la référence du paiement Orange Money' using errcode = '22023'; end if;
  if exists (select 1 from telima.vendor_subscriptions where place_id = p_place_id and status = 'pending') then
    raise exception 'Une demande est déjà en attente de validation' using errcode = 'P0001';
  end if;
  insert into telima.vendor_subscriptions(place_id, plan_code, months, amount, payment_ref)
  values (p_place_id, p_plan, p_months, v_plan.price_monthly * p_months, left(trim(p_payment_ref), 80));
  perform telima.notify_staff('vendor_subscription', 'Demande d''abonnement vendeur',
    v_place.name || ' · ' || v_plan.name || ' · ' || p_months || ' mois · ' || v_plan.price_monthly * p_months || ' FCFA', jsonb_build_object('place_id', p_place_id));
end $$;

create or replace function telima.admin_decide_subscription(p_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = telima, public as $$
declare s telima.vendor_subscriptions; v_owner uuid; v_name text;
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  select * into s from telima.vendor_subscriptions where id = p_id and status = 'pending' for update;
  if not found then raise exception 'Demande introuvable' using errcode = 'P0002'; end if;
  select owner_id, name into v_owner, v_name from telima.places where id = s.place_id;
  if p_approve then
    update telima.vendor_subscriptions set status = 'ended' where place_id = s.place_id and status = 'active';
    update telima.vendor_subscriptions set status = 'active', starts_at = now(), ends_at = now() + make_interval(months => s.months) where id = p_id;
  else
    update telima.vendor_subscriptions set status = 'rejected' where id = p_id;
  end if;
  if v_owner is not null then
    perform telima.notify_user(v_owner, 'vendor_subscription',
      case when p_approve then 'Abonnement activé' else 'Abonnement refusé' end,
      v_name || case when p_approve then ' : votre forfait est actif.' else ' : paiement non retrouvé, contactez le support.' end,
      jsonb_build_object('place_id', s.place_id));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Promotions
-- ---------------------------------------------------------------------
create table telima.place_promotions (
  id             uuid primary key default gen_random_uuid(),
  place_id       uuid not null references telima.places(id) on delete cascade,
  product_id     uuid references telima.place_products(id) on delete cascade,   -- null = tous les produits du point
  title          text not null check (char_length(title) between 2 and 80),
  discount_type  text not null check (discount_type in ('percent', 'amount')),
  discount_value integer not null check (discount_value > 0),
  starts_at      timestamptz not null default now(),
  ends_at        timestamptz not null,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  check (ends_at > starts_at),
  check (discount_type <> 'percent' or discount_value <= 90)
);
create index idx_place_promos_place on telima.place_promotions(place_id, ends_at desc);
alter table telima.place_promotions enable row level security;
create policy place_promos_read on telima.place_promotions for select
  using (exists (select 1 from telima.places p where p.id = place_id and (p.status = 'approved' or p.owner_id = auth.uid() or telima.is_staff())));
create policy place_promos_owner on telima.place_promotions for all
  using (telima.is_place_owner(place_id) or telima.is_staff()) with check (telima.is_place_owner(place_id) or telima.is_staff());
grant select on telima.place_promotions to anon, authenticated;
grant insert, update, delete on telima.place_promotions to authenticated;

create or replace function telima.promo_best(p_product uuid) returns table(title text, price integer)
language sql stable security definer set search_path = telima, public as $$
  select pm.title, greatest(0, case pm.discount_type when 'percent' then round(pr.price * (100 - pm.discount_value) / 100.0)::int
                                                      else pr.price - pm.discount_value end)
    from telima.place_products pr join telima.place_promotions pm on pm.place_id = pr.place_id
   where pr.id = p_product and pm.is_active and now() between pm.starts_at and pm.ends_at
     and (pm.product_id is null or pm.product_id = pr.id)
   order by 2 asc limit 1;
$$;
create or replace function telima.promo_price(p_product uuid) returns integer language sql stable security definer set search_path = telima, public as $$
  select price from telima.promo_best(p_product);
$$;
create or replace function telima.promo_title(p_product uuid) returns text language sql stable security definer set search_path = telima, public as $$
  select title from telima.promo_best(p_product);
$$;
create or replace function telima.effective_price(p_product uuid) returns integer language sql stable security definer set search_path = telima, public as $$
  select coalesce(telima.promo_price(p_product), (select price from telima.place_products where id = p_product));
$$;
create or replace function telima.place_promo_title(p_place uuid) returns text language sql stable security definer set search_path = telima, public as $$
  select title from telima.place_promotions where place_id = p_place and is_active and now() between starts_at and ends_at
   order by discount_value desc limit 1;
$$;

-- Limites du forfait (produits et promotions actives)
create or replace function telima.tg_plan_limits() returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_plan telima.vendor_plans; v_n integer;
begin
  if telima.is_staff() then return new; end if;
  v_plan := telima.place_plan(new.place_id);
  if tg_table_name = 'place_products' and v_plan.max_products is not null then
    select count(*) into v_n from telima.place_products where place_id = new.place_id;
    if v_n >= v_plan.max_products then
      raise exception 'Forfait % : % produit(s) maximum. Passez à un forfait supérieur.', v_plan.name, v_plan.max_products using errcode = 'P0001';
    end if;
  elsif tg_table_name = 'place_promotions' and v_plan.max_promotions is not null and new.is_active then
    select count(*) into v_n from telima.place_promotions where place_id = new.place_id and is_active and ends_at > now() and id <> new.id;
    if v_n >= v_plan.max_promotions then
      raise exception 'Forfait % : % promotion(s) active(s) maximum. Passez à un forfait supérieur.', v_plan.name, v_plan.max_promotions using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
create trigger trg_plan_limit_products before insert on telima.place_products for each row execute function telima.tg_plan_limits();
create trigger trg_plan_limit_promos before insert or update of is_active, ends_at on telima.place_promotions for each row execute function telima.tg_plan_limits();

-- ---------------------------------------------------------------------
-- Favoris : points de gaz ET stations, avec la même forme que la recherche
-- ---------------------------------------------------------------------
create or replace function telima.favorite_places(p_lat double precision, p_lng double precision)
returns jsonb language sql stable security definer set search_path = telima, public as $$
  select coalesce(jsonb_agg(e order by (e->>'distance_km')::numeric), '[]'::jsonb)
    from jsonb_array_elements(telima.search_places(p_lat, p_lng, null, 100000, null, null, false, false, null, 200)) e
   where (e->>'id')::uuid in (select place_id from telima.place_favorites where user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------
-- Import OSM (stations-service) : à partir d'une réponse Overpass reçue par pg_net
-- ---------------------------------------------------------------------
create or replace function telima._import_osm_fuel(p_request bigint, p_city uuid) returns integer language plpgsql security definer set search_path = telima, public as $$
declare j jsonb; e jsonb; n int := 0; t jsonb; v_lat float8; v_lng float8; v_name text; v_brand text; v_ph text;
begin
  select content::jsonb into j from net._http_response where id = p_request and status_code = 200;
  if j is null then raise exception 'Réponse Overpass indisponible' using errcode = 'P0001'; end if;
  for e in select * from jsonb_array_elements(j->'elements') loop
    t := coalesce(e->'tags', '{}'::jsonb);
    v_lat := coalesce((e->>'lat')::float8, (e->'center'->>'lat')::float8);
    v_lng := coalesce((e->>'lon')::float8, (e->'center'->>'lon')::float8);
    continue when v_lat is null or v_lng is null;
    v_brand := nullif(coalesce(t->>'brand', t->>'operator'), '');
    v_name := coalesce(nullif(t->>'name', ''), case when v_brand is not null then 'Station ' || v_brand end, 'Station-service');
    v_ph := nullif(coalesce(t->>'phone', t->>'contact:phone'), '');
    insert into telima.places(kind, name, brand_label, city_id, neighborhood, address, lat, lng, phone, opening_hours, status, source, osm_id)
    values ('fuel_station', left(v_name, 120), v_brand, p_city, nullif(t->>'addr:suburb', ''),
            nullif(concat_ws(' ', t->>'addr:street', t->>'addr:city'), ''), v_lat, v_lng, v_ph, nullif(t->>'opening_hours', ''),
            'approved', 'osm', (e->>'type') || '/' || (e->>'id'))
    on conflict (osm_id) do update set name = excluded.name, brand_label = excluded.brand_label, lat = excluded.lat, lng = excluded.lng,
        phone = coalesce(excluded.phone, telima.places.phone), opening_hours = coalesce(excluded.opening_hours, telima.places.opening_hours);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function telima.review_place(uuid, integer, text), telima.delete_my_review(uuid), telima.place_reviews_list(uuid, integer),
  telima.place_plan(uuid), telima.place_boost(uuid), telima.vendor_request_subscription(uuid, text, integer, text),
  telima.admin_decide_subscription(uuid, boolean), telima.promo_best(uuid), telima.promo_price(uuid), telima.promo_title(uuid),
  telima.effective_price(uuid), telima.place_promo_title(uuid), telima.favorite_places(double precision, double precision),
  telima._import_osm_fuel(bigint, uuid), telima.tg_plan_limits(), telima.tg_review_sync() from public, anon, authenticated;
grant execute on function telima.place_reviews_list(uuid, integer), telima.promo_price(uuid), telima.promo_title(uuid),
  telima.place_promo_title(uuid), telima.place_boost(uuid), telima.place_plan(uuid), telima.effective_price(uuid), telima.promo_best(uuid)
  to anon, authenticated, service_role;
grant execute on function telima.review_place(uuid, integer, text), telima.delete_my_review(uuid), telima.vendor_request_subscription(uuid, text, integer, text),
  telima.admin_decide_subscription(uuid, boolean), telima.favorite_places(double precision, double precision) to authenticated, service_role;

-- Recherche et commande mises à jour (note, promotions, mise en avant)

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
  v_price int;
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
    v_price := telima.effective_price(v_prod.id);
    select name into v_brand from telima.gas_brands where id = v_prod.brand_id;
    insert into telima.gas_order_items(order_id, product_id, label, size_kg, qty, unit_price, original_price)
    values (v_row.id, v_prod.id, coalesce(v_brand, 'Gaz'), v_prod.size_kg, v_qty, v_price, v_prod.price);
    v_items_total := v_items_total + v_price * v_qty;
  end loop;

  update telima.gas_orders set items_total = v_items_total, total = v_items_total + v_fee
   where id = v_row.id returning * into v_row;

  perform telima.notify_user(v_place.owner_id, 'gas_order_new', 'Nouvelle commande de gaz',
    v_row.code || ' · ' || v_row.total || ' FCFA', jsonb_build_object('gas_order_id', v_row.id));
  return v_row;
end $$;
