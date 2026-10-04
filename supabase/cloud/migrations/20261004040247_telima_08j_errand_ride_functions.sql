-- Migration appliquée sur le projet Supabase cloud : telima_08j_errand_ride_functions

-- Prix d'une course à faire ou d'un trajet (VTC)
create or replace function telima.quote_service(p_kind text, p_from_lat float8, p_from_lng float8, p_to_lat float8, p_to_lng float8,
                                                p_vehicle telima.vehicle_type default 'moto', p_route_km numeric default null)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_q jsonb; v_total int; v_rounding int := coalesce((telima.get_setting('price_rounding', '50'))::text::int, 50);
begin
  if p_kind = 'errand' then
    v_q := telima.quote_delivery(p_from_lat, p_from_lng, p_to_lat, p_to_lng, coalesce(p_vehicle, 'moto'), 'petit', false, null, 'courses', null, false);
    v_total := (v_q->>'total_price')::int + coalesce((telima.get_setting('errand_service_fee', '500'))::text::int, 500);
  elsif p_kind = 'ride' then
    if p_vehicle not in ('moto', 'voiture') then raise exception 'Moto-taxi ou voiture uniquement' using errcode = '22023'; end if;
    v_q := telima.quote_delivery(p_from_lat, p_from_lng, p_to_lat, p_to_lng, p_vehicle, 'petit', false, null, 'autre', p_route_km, false);
    v_total := telima.round_up_to(((v_q->>'total_price')::int
               * coalesce((telima.get_setting('ride_price_multiplier', '1'))::text::numeric, 1))::numeric, v_rounding);
  else
    raise exception 'Type inconnu' using errcode = '22023';
  end if;
  return v_q || jsonb_build_object('total_price', v_total, 'kind', p_kind);
end $$;

-- Course à faire : le livreur achète (repas, médicaments…) puis livre à l'adresse du client
-- p = { dropoff:{address,lat,lng,instructions}, items, category, budget, payment_method, vehicle_type }
create or replace function telima.create_errand(p jsonb)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user(); v_user telima.users; v_row telima.deliveries;
  v_drop jsonb := p->'dropoff'; v_q jsonb; v_cat text := coalesce(nullif(p->>'category', ''), 'autre');
  v_label text;
begin
  if coalesce(trim(p->>'items'), '') = '' or char_length(p->>'items') > 1500 then
    raise exception 'Décrivez ce qu''il faut acheter' using errcode = '22023';
  end if;
  if v_drop is null or v_drop->>'lat' is null then raise exception 'Adresse de livraison obligatoire' using errcode = '22023'; end if;
  select * into v_user from telima.users where id = v_uid;
  v_label := case v_cat when 'repas' then 'un restaurant' when 'pharmacie' then 'une pharmacie' when 'marche' then 'le marché'
                        when 'boutique' then 'une boutique' else 'un commerce' end;
  v_q := telima.quote_service('errand', (v_drop->>'lat')::float8, (v_drop->>'lng')::float8, (v_drop->>'lat')::float8,
                              (v_drop->>'lng')::float8, coalesce(nullif(p->>'vehicle_type', ''), 'moto')::telima.vehicle_type);
  perform set_config('telima.new_kind', 'errand', true);
  perform set_config('telima.new_extra', jsonb_build_object('items', trim(p->>'items'), 'category', v_cat,
                                                            'budget', nullif(p->>'budget', ''))::text, true);
  v_row := telima._insert_delivery(
    jsonb_build_object(
      'pickup', jsonb_build_object('address', 'Achats dans ' || v_label || ' au choix du livreur',
                                   'lat', v_drop->'lat', 'lng', v_drop->'lng', 'contact_name', v_user.full_name, 'contact_phone', v_user.phone),
      'dropoff', v_drop || jsonb_build_object('contact_name', coalesce(nullif(v_drop->>'contact_name', ''), v_user.full_name),
                                              'contact_phone', coalesce(nullif(v_drop->>'contact_phone', ''), v_user.phone)),
      'package', jsonb_build_object('category', case when v_cat = 'repas' then 'nourriture' else 'courses' end,
                                    'description', left(trim(p->>'items'), 300)),
      'vehicle_type', coalesce(nullif(p->>'vehicle_type', ''), 'moto'),
      'payment_method', coalesce(p->>'payment_method', 'cash')),
    v_uid, v_user.full_name, v_user.phone, v_uid, 'app', null, 1, false, null, null, (v_q->>'total_price')::int);
  perform set_config('telima.new_kind', '', true);
  perform set_config('telima.new_extra', '', true);
  if v_row.status = 'searching' then perform telima.notify_nearby_drivers(v_row); end if;
  return v_row;
end $$;

-- Transport de personnes : p = { pickup:{address,lat,lng}, dropoff:{address,lat,lng}, vehicle_type, passengers, payment_method, route_km }
create or replace function telima.create_ride(p jsonb)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user(); v_user telima.users; v_row telima.deliveries; v_q jsonb;
  v_vehicle telima.vehicle_type := coalesce(nullif(p->>'vehicle_type', ''), 'moto')::telima.vehicle_type;
  v_pass int := greatest(1, coalesce((p->>'passengers')::int, 1));
begin
  if v_vehicle = 'moto' and v_pass > 1 then raise exception 'Moto-taxi : 1 passager' using errcode = '22023'; end if;
  if v_pass > 4 then raise exception '4 passagers maximum' using errcode = '22023'; end if;
  select * into v_user from telima.users where id = v_uid;
  v_q := telima.quote_service('ride', (p->'pickup'->>'lat')::float8, (p->'pickup'->>'lng')::float8,
                              (p->'dropoff'->>'lat')::float8, (p->'dropoff'->>'lng')::float8, v_vehicle, nullif(p->>'route_km', '')::numeric);
  perform set_config('telima.new_kind', 'ride', true);
  perform set_config('telima.new_extra', jsonb_build_object('passengers', v_pass)::text, true);
  v_row := telima._insert_delivery(
    jsonb_build_object(
      'pickup', (p->'pickup') || jsonb_build_object('contact_name', v_user.full_name, 'contact_phone', v_user.phone),
      'dropoff', (p->'dropoff') || jsonb_build_object('contact_name', v_user.full_name, 'contact_phone', v_user.phone),
      'package', jsonb_build_object('category', 'autre', 'description', v_pass || ' passager(s)'),
      'vehicle_type', v_vehicle, 'route_km', p->'route_km',
      'payment_method', coalesce(p->>'payment_method', 'cash')),
    v_uid, v_user.full_name, v_user.phone, v_uid, 'app', null, 1, false, null, null, (v_q->>'total_price')::int);
  perform set_config('telima.new_kind', '', true);
  perform set_config('telima.new_extra', '', true);
  if v_row.status = 'searching' then perform telima.notify_nearby_drivers(v_row); end if;
  return v_row;
end $$;

-- Le livreur indique le montant des achats (et la photo du ticket)
create or replace function telima.driver_set_purchase(p_delivery_id uuid, p_amount integer, p_shop text default null,
                                                      p_receipt_path text default null)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or v_del.driver_id is distinct from v_uid or v_del.kind <> 'errand' then
    raise exception 'Course introuvable' using errcode = 'P0002';
  end if;
  if v_del.status not in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit') then
    raise exception 'Trop tard pour modifier les achats' using errcode = 'P0001';
  end if;
  if v_del.purchase_settled_at is not null then raise exception 'Achats déjà remboursés' using errcode = 'P0001'; end if;
  if p_amount is null or p_amount < 0 or p_amount > 1000000 then raise exception 'Montant invalide' using errcode = '22023'; end if;
  update telima.deliveries set purchase_amount = p_amount, purchase_shop = nullif(trim(coalesce(p_shop, '')), ''),
         purchase_receipt_path = coalesce(p_receipt_path, purchase_receipt_path), purchase_at = now()
   where id = p_delivery_id returning * into v_del;
  perform telima.notify_user(v_del.customer_id, 'errand_purchase', 'Achats effectués · ' || v_del.code,
    telima.fcfa_txt(p_amount) || coalesce(' chez ' || v_del.purchase_shop, '')
      || case when v_del.errand_budget is not null and p_amount > v_del.errand_budget
              then ' (budget de ' || telima.fcfa_txt(v_del.errand_budget) || ' dépassé)' else '' end
      || '. À rembourser au livreur à la livraison (espèces ou portefeuille).',
    jsonb_build_object('delivery_id', v_del.id));
  return v_del;
end $$;

-- Remboursement des achats : par portefeuille (client) ou constat d'espèces reçues (livreur)
create or replace function telima.settle_purchase(p_delivery_id uuid, p_method text)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or v_del.kind <> 'errand' or v_del.purchase_amount is null then
    raise exception 'Aucun achat à rembourser' using errcode = 'P0002';
  end if;
  if v_del.purchase_settled_at is not null then return v_del; end if;
  if p_method = 'wallet' then
    if v_del.customer_id is distinct from v_uid then raise exception 'Réservé au client' using errcode = '42501'; end if;
    if v_del.driver_id is null then raise exception 'Aucun livreur' using errcode = 'P0001'; end if;
    perform telima.wallet_apply(v_del.customer_id, 'purchase', -v_del.purchase_amount, v_del.id, null, 'Achats ' || v_del.code);
    perform telima.wallet_apply(v_del.driver_id, 'purchase', v_del.purchase_amount, v_del.id, null, 'Remboursement achats ' || v_del.code);
  elsif p_method = 'cash' then
    if v_del.driver_id is distinct from v_uid and not telima.is_staff() then raise exception 'Réservé au livreur' using errcode = '42501'; end if;
    perform telima.notify_user(v_del.customer_id, 'errand_purchase', 'Achats remboursés · ' || v_del.code,
      telima.fcfa_txt(v_del.purchase_amount) || ' reçus en espèces par le livreur.', jsonb_build_object('delivery_id', v_del.id));
  else
    raise exception 'Mode de remboursement invalide' using errcode = '22023';
  end if;
  update telima.deliveries set purchase_settlement = p_method, purchase_settled_at = now()
   where id = p_delivery_id returning * into v_del;
  return v_del;
end $$;

-- Services proposés par le livreur / chauffeur (colis, courses, transport de personnes)
create or replace function telima.set_driver_services(p_services text[])
returns telima.drivers language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_drv telima.drivers;
begin
  if p_services is null or cardinality(p_services) = 0 or not (p_services <@ array['parcel', 'errand', 'ride']) then
    raise exception 'Choisissez au moins un service' using errcode = '22023';
  end if;
  update telima.drivers set services = p_services where user_id = v_uid returning * into v_drv;
  if v_drv.user_id is null then raise exception 'Compte livreur introuvable' using errcode = 'P0002'; end if;
  return v_drv;
end $$;
