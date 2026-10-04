-- Migration appliquée sur le projet Supabase cloud : telima_02b1_insert_delivery

create or replace function telima._insert_delivery(
  p jsonb, p_customer_id uuid, p_customer_name text, p_customer_phone text,
  p_created_by uuid, p_via text, p_batch_id uuid default null, p_stop_order int default 1,
  p_is_extra_stop boolean default false, p_from_lat double precision default null,
  p_from_lng double precision default null, p_price_override integer default null)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_pick jsonb := p->'pickup';
  v_drop jsonb := p->'dropoff';
  v_pkg  jsonb := coalesce(p->'package', '{}'::jsonb);
  v_method telima.payment_method := coalesce(p->>'payment_method', 'cash')::telima.payment_method;
  v_enabled jsonb := telima.get_setting('payment_methods', '["cash","cash_on_delivery","orange_money","moov_money","wallet"]');
  v_quote jsonb;
  v_comm jsonb;
  v_total int;
  v_row telima.deliveries;
  v_status telima.delivery_status;
  v_payment_status telima.payment_status := 'pending';
begin
  if v_pick is null or v_drop is null then
    raise exception 'Point de récupération et destination obligatoires' using errcode = '22023';
  end if;
  if coalesce(trim(v_pick->>'address'), '') = '' or coalesce(trim(v_drop->>'address'), '') = '' then
    raise exception 'Adresse obligatoire' using errcode = '22023';
  end if;
  if not (v_enabled ? v_method::text) then
    raise exception 'Moyen de paiement indisponible' using errcode = 'P0001';
  end if;

  v_quote := telima.quote_delivery(
    coalesce(p_from_lat, (v_pick->>'lat')::float8), coalesce(p_from_lng, (v_pick->>'lng')::float8),
    (v_drop->>'lat')::float8, (v_drop->>'lng')::float8,
    nullif(p->>'vehicle_type', '')::telima.vehicle_type,
    coalesce(nullif(v_pkg->>'size', ''), 'petit')::telima.package_size,
    coalesce((v_pkg->>'fragile')::boolean, false),
    nullif(v_pkg->>'weight_kg', '')::numeric,
    coalesce(nullif(v_pkg->>'category', ''), 'petit_colis')::telima.package_category,
    nullif(p->>'route_km', '')::numeric,
    p_is_extra_stop);

  v_total := coalesce(p_price_override, (v_quote->>'total_price')::int);
  if v_total < 0 then raise exception 'Prix invalide' using errcode = '22023'; end if;
  v_comm := telima.compute_commission(v_total);

  v_status := case when v_method in ('orange_money', 'moov_money') then 'created' else 'searching' end;
  if p_batch_id is not null and p_stop_order > 1 then
    v_status := 'created';
  end if;

  insert into telima.deliveries(
    code, status, customer_id, customer_name, customer_phone, business_id, created_by, created_via,
    vehicle_type, city_id, zone_id, batch_id, stop_order,
    pickup_address, pickup_lat, pickup_lng, pickup_contact_name, pickup_contact_phone, pickup_instructions,
    dropoff_address, dropoff_lat, dropoff_lng, dropoff_contact_name, dropoff_contact_phone, dropoff_instructions,
    package_category, package_description, package_photo_path, package_quantity, package_fragile, package_size, package_weight_kg,
    distance_km, price_base, price_distance, price_extras, price_zone, total_price,
    commission_type, commission_value, commission_amount, driver_earning,
    payment_method, payment_status, searching_at)
  values (
    telima.next_code('delivery', 'LIV'), v_status, p_customer_id, p_customer_name, p_customer_phone,
    nullif(p->>'business_id', '')::uuid, p_created_by, p_via,
    (v_quote->>'vehicle_type')::telima.vehicle_type, nullif(v_quote->>'city_id', '')::uuid, nullif(v_quote->>'zone_id', '')::uuid,
    p_batch_id, p_stop_order,
    trim(v_pick->>'address'), (v_pick->>'lat')::float8, (v_pick->>'lng')::float8,
    coalesce(nullif(trim(v_pick->>'contact_name'), ''), p_customer_name),
    telima.normalize_phone(coalesce(nullif(v_pick->>'contact_phone', ''), p_customer_phone)),
    nullif(trim(v_pick->>'instructions'), ''),
    trim(v_drop->>'address'), (v_drop->>'lat')::float8, (v_drop->>'lng')::float8,
    coalesce(nullif(trim(v_drop->>'contact_name'), ''), 'Destinataire'),
    telima.normalize_phone(v_drop->>'contact_phone'),
    nullif(trim(v_drop->>'instructions'), ''),
    coalesce(nullif(v_pkg->>'category', ''), 'petit_colis')::telima.package_category,
    nullif(trim(v_pkg->>'description'), ''), nullif(v_pkg->>'photo_path', ''),
    coalesce((v_pkg->>'quantity')::int, 1), coalesce((v_pkg->>'fragile')::boolean, false),
    coalesce(nullif(v_pkg->>'size', ''), 'petit')::telima.package_size, nullif(v_pkg->>'weight_kg', '')::numeric,
    (v_quote->>'distance_km')::numeric,
    case when p_price_override is null then (v_quote->>'price_base')::int else v_total end,
    case when p_price_override is null then (v_quote->>'price_distance')::int else 0 end,
    case when p_price_override is null then (v_quote->>'price_extras')::int else 0 end,
    case when p_price_override is null then (v_quote->>'price_zone')::int else 0 end,
    v_total,
    (v_comm->>'type')::telima.commission_type, (v_comm->>'value')::numeric,
    (v_comm->>'amount')::int, (v_comm->>'driver_earning')::int,
    v_method, 'pending', case when v_status = 'searching' then now() end)
  returning * into v_row;

  insert into telima.delivery_secrets(delivery_id, otp_code)
  values (v_row.id, lpad((floor(random() * 10000))::int::text, 4, '0'));

  if v_method = 'wallet' then
    if p_customer_id is null then
      raise exception 'Le portefeuille nécessite un compte client' using errcode = 'P0001';
    end if;
    perform telima.wallet_apply(p_customer_id, 'payment', -v_total, v_row.id, null,
                                'Paiement livraison ' || v_row.code);
    v_payment_status := 'paid';
  end if;
  insert into telima.payments(delivery_id, payer_id, amount, method, provider, status, paid_at, metadata)
  values (v_row.id, p_customer_id, v_total, v_method,
          case when v_method in ('orange_money', 'moov_money') then v_method::text
               when v_method = 'wallet' then 'internal' else 'cash' end,
          v_payment_status, case when v_payment_status = 'paid' then now() end,
          jsonb_build_object('kind', 'delivery'));
  if v_payment_status = 'paid' then
    update telima.deliveries set payment_status = 'paid' where id = v_row.id returning * into v_row;
  end if;

  return v_row;
end $$;
