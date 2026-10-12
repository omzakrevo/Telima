-- Boutiques : plusieurs photos et une video par article, notes et avis (boutique et article)

alter table telima.shop_products add column if not exists photos text[] not null default '{}';
alter table telima.shop_products add column if not exists video_path text;
alter table telima.shop_products drop constraint if exists shop_products_photos_max;
alter table telima.shop_products add constraint shop_products_photos_max check (cardinality(photos) <= 8);

-- compartiment : videos acceptees (30 Mo max par fichier)
update storage.buckets
   set file_size_limit = 31457280,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime']
 where id = 'telima-boutiques';

-- ---------------------------------------------------------------------
-- Avis : une note (1 a 5) par personne et par boutique, et une par article
-- ---------------------------------------------------------------------
create table if not exists telima.shop_reviews (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references telima.shops(id) on delete cascade,
  product_id  uuid references telima.shop_products(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  author_name text,
  rating      smallint not null check (rating between 1 and 5),
  comment     text check (comment is null or char_length(comment) <= 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists uq_shop_review_shop on telima.shop_reviews(shop_id, user_id) where product_id is null;
create unique index if not exists uq_shop_review_product on telima.shop_reviews(product_id, user_id) where product_id is not null;
create index if not exists idx_shop_reviews_shop on telima.shop_reviews(shop_id, created_at desc);

alter table telima.shop_reviews enable row level security;
create policy shop_reviews_read on telima.shop_reviews for select using (true);
create policy shop_reviews_admin on telima.shop_reviews for all using (telima.is_staff()) with check (telima.is_staff());
grant select on telima.shop_reviews to anon, authenticated;

-- Donner ou modifier sa note (p_product null = la boutique). Le commercant ne note pas sa propre boutique.
create or replace function telima.rate_shop(p_shop uuid, p_product uuid, p_rating integer, p_comment text default null)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := auth.uid(); v_name text;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'La note doit etre entre 1 et 5'; end if;
  if not exists (select 1 from telima.shops where id = p_shop and status = 'approved') then raise exception 'Boutique introuvable'; end if;
  if telima.is_shop_owner(p_shop) then raise exception 'Vous ne pouvez pas noter votre propre boutique'; end if;
  if p_product is not null and not exists (select 1 from telima.shop_products where id = p_product and shop_id = p_shop) then
    raise exception 'Article introuvable';
  end if;
  select full_name into v_name from telima.users where id = v_uid;
  if p_product is null then
    insert into telima.shop_reviews (shop_id, product_id, user_id, author_name, rating, comment)
    values (p_shop, null, v_uid, v_name, p_rating, nullif(trim(p_comment), ''))
    on conflict (shop_id, user_id) where product_id is null
    do update set rating = excluded.rating, comment = excluded.comment, author_name = excluded.author_name, updated_at = now();
  else
    insert into telima.shop_reviews (shop_id, product_id, user_id, author_name, rating, comment)
    values (p_shop, p_product, v_uid, v_name, p_rating, nullif(trim(p_comment), ''))
    on conflict (product_id, user_id) where product_id is not null
    do update set rating = excluded.rating, comment = excluded.comment, author_name = excluded.author_name, updated_at = now();
  end if;
  return telima.shop_rating(p_shop, p_product);
end $$;

create or replace function telima.delete_my_shop_review(p_shop uuid, p_product uuid default null)
returns void language sql security definer set search_path = telima, public as $$
  delete from telima.shop_reviews
   where user_id = auth.uid() and shop_id = p_shop and product_id is not distinct from p_product;
$$;

create or replace function telima.shop_rating(p_shop uuid, p_product uuid default null)
returns jsonb language sql stable security definer set search_path = telima, public as $$
  select jsonb_build_object('avg', coalesce(round(avg(rating)::numeric, 1), 0), 'count', count(*))
    from telima.shop_reviews where shop_id = p_shop and product_id is not distinct from p_product;
$$;

-- Avis recents (boutique ou article) + l'avis de la personne connectee
create or replace function telima.shop_reviews_list(p_shop uuid, p_product uuid default null, p_limit integer default 50)
returns jsonb language sql stable security definer set search_path = telima, public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id, 'rating', r.rating, 'comment', r.comment, 'author', coalesce(r.author_name, 'Client'),
           'created_at', r.created_at, 'mine', r.user_id = auth.uid()) order by r.created_at desc), '[]'::jsonb)
    from (select * from telima.shop_reviews where shop_id = p_shop and product_id is not distinct from p_product
           order by created_at desc limit greatest(1, least(coalesce(p_limit, 50), 100))) r;
$$;

grant execute on function telima.rate_shop(uuid, uuid, integer, text) to authenticated;
grant execute on function telima.delete_my_shop_review(uuid, uuid) to authenticated;
grant execute on function telima.shop_rating(uuid, uuid) to anon, authenticated;
grant execute on function telima.shop_reviews_list(uuid, uuid, integer) to anon, authenticated;

-- ---------------------------------------------------------------------
-- Page publique et liste : photos, video et notes
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
    'rating_avg', (select coalesce(round(avg(rating)::numeric, 1), 0) from telima.shop_reviews where shop_id = v_r.id and product_id is null),
    'rating_count', (select count(*) from telima.shop_reviews where shop_id = v_r.id and product_id is null),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.sort_order, c.created_at)
                              from telima.shop_categories c where c.shop_id = v_r.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
                          'id', i.id, 'category_id', i.category_id, 'name', i.name, 'description', i.description,
                          'price', i.price, 'photo_path', i.photo_path, 'is_available', i.is_available,
                          'sizes', i.sizes, 'colors', i.colors, 'stock', i.stock,
                          'photos', i.photos, 'video_path', i.video_path,
                          'rating_avg', (select coalesce(round(avg(rv.rating)::numeric, 1), 0) from telima.shop_reviews rv where rv.product_id = i.id),
                          'rating_count', (select count(*) from telima.shop_reviews rv where rv.product_id = i.id))
                        order by i.sort_order, i.created_at)
                         from telima.shop_products i where i.shop_id = v_r.id), '[]'::jsonb));
end $$;

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
      'rating_avg', (select coalesce(round(avg(rating)::numeric, 1), 0) from telima.shop_reviews where shop_id = x.id and product_id is null),
      'rating_count', (select count(*) from telima.shop_reviews where shop_id = x.id and product_id is null),
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
