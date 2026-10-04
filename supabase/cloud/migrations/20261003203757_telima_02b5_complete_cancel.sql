-- Migration appliquée sur le projet Supabase cloud : telima_02b5_complete_cancel

create or replace function telima.driver_update_location(p_lat double precision, p_lng double precision,
                                                         p_heading double precision default null, p_speed double precision default null)
returns void language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_min_interval int := coalesce((telima.get_setting('location_min_interval_s', '10'))::text::int, 10);
  v_near_km numeric := coalesce((telima.get_setting('near_pickup_km', '0.5'))::text::numeric, 0.5);
  v_del record;
  v_last timestamptz;
begin
  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then
    raise exception 'Position invalide' using errcode = '22023';
  end if;
  update telima.drivers set current_lat = p_lat, current_lng = p_lng, last_location_at = now()
   where user_id = v_uid;
  if not found then raise exception 'Profil livreur introuvable' using errcode = 'P0002'; end if;

  for v_del in select * from telima.deliveries
                where driver_id = v_uid and status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff')
  loop
    select max(recorded_at) into v_last from telima.delivery_locations where delivery_id = v_del.id;
    if v_last is null or v_last < now() - make_interval(secs => v_min_interval) then
      insert into telima.delivery_locations(delivery_id, driver_id, lat, lng, heading, speed)
      values (v_del.id, v_uid, p_lat, p_lng, p_heading, p_speed);
    end if;
    if v_del.status = 'to_pickup' and not v_del.near_notified and v_del.stop_order = 1
       and telima.haversine_km(p_lat, p_lng, v_del.pickup_lat, v_del.pickup_lng) <= v_near_km then
      update telima.deliveries set near_notified = true where id = v_del.id;
      perform telima.notify_user(v_del.customer_id, 'driver_near', v_del.code,
                                 'Votre livreur arrive dans quelques minutes.', jsonb_build_object('delivery_id', v_del.id));
    end if;
  end loop;
end $$;

create or replace function telima.complete_delivery(
  p_delivery_id uuid, p_otp text default null, p_receiver_name text default null,
  p_photo_path text default null, p_signature_path text default null,
  p_lat double precision default null, p_lng double precision default null)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_del telima.deliveries;
  v_secret telima.delivery_secrets;
  v_mode text := coalesce(telima.get_setting('proof_mode', '"otp"') #>> '{}', 'otp');
  v_max int := coalesce((telima.get_setting('otp_max_attempts', '5'))::text::int, 5);
  v_proof telima.proof_type;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or (v_del.driver_id is distinct from v_uid and not telima.is_staff()) then
    raise exception 'Course introuvable' using errcode = 'P0002';
  end if;
  if v_del.status not in ('in_transit', 'at_dropoff') then
    raise exception 'La livraison ne peut pas être terminée à cette étape' using errcode = 'P0001';
  end if;

  select * into v_secret from telima.delivery_secrets where delivery_id = p_delivery_id for update;
  if p_otp is not null and p_otp <> '' then
    if v_secret.locked then
      raise exception 'Code bloqué après trop d''essais. Contactez le support.' using errcode = 'P0001';
    end if;
    if v_secret.otp_code <> trim(p_otp) then
      update telima.delivery_secrets set attempts = attempts + 1, locked = (attempts + 1 >= v_max)
       where delivery_id = p_delivery_id;
      return null;
    end if;
    v_proof := 'otp';
  elsif v_mode = 'otp' and not telima.is_staff() then
    raise exception 'Code de livraison requis' using errcode = 'P0001';
  elsif p_photo_path is not null then
    v_proof := 'photo';
  elsif p_signature_path is not null then
    v_proof := 'signature';
  elsif coalesce(trim(p_receiver_name), '') <> '' then
    v_proof := 'name';
  else
    raise exception 'Une preuve de livraison est requise' using errcode = 'P0001';
  end if;

  perform set_config('telima.status_lat', coalesce(p_lat::text, ''), true);
  perform set_config('telima.status_lng', coalesce(p_lng::text, ''), true);

  update telima.deliveries set status = 'handed_over', delivered_at = now(), proof_type = v_proof,
         receiver_name = nullif(trim(p_receiver_name), ''), proof_photo_path = p_photo_path,
         proof_signature_path = p_signature_path
   where id = p_delivery_id;
  update telima.deliveries set status = 'completed', completed_at = now()
   where id = p_delivery_id returning * into v_del;

  if v_del.payment_method in ('cash', 'cash_on_delivery') then
    update telima.payments set status = 'paid', paid_at = now(), provider = 'cash'
     where delivery_id = v_del.id and status = 'pending';
    update telima.deliveries set payment_status = 'paid' where id = v_del.id returning * into v_del;
    if v_del.commission_amount > 0 and v_del.driver_id is not null then
      perform telima.wallet_apply(v_del.driver_id, 'commission', -v_del.commission_amount, v_del.id, null,
                                  'Commission plateforme ' || v_del.code || ' (espèces encaissées : ' || v_del.total_price || ' FCFA)', true);
    end if;
  elsif v_del.payment_status = 'paid' and v_del.driver_id is not null then
    perform telima.wallet_apply(v_del.driver_id, 'earning', v_del.driver_earning, v_del.id, null,
                                'Gain course ' || v_del.code);
  end if;

  update telima.drivers set total_deliveries = total_deliveries + 1 where user_id = v_del.driver_id;
  update telima.customers set total_deliveries = total_deliveries + 1 where user_id = v_del.customer_id;
  return v_del;
end $$;

create or replace function telima.cancel_delivery(p_delivery_id uuid, p_reason text)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries; v_staff boolean := telima.is_staff();
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or (v_del.customer_id is distinct from v_uid and not v_staff) then
    raise exception 'Livraison introuvable' using errcode = 'P0002';
  end if;
  if v_del.status in ('completed', 'cancelled', 'handed_over') then
    raise exception 'Cette livraison ne peut plus être annulée' using errcode = 'P0001';
  end if;
  if not v_staff and v_del.status not in ('created', 'searching', 'assigned', 'to_pickup', 'at_pickup') then
    raise exception 'Le colis a déjà été récupéré : contactez le support pour annuler' using errcode = 'P0001';
  end if;

  perform set_config('telima.status_note', coalesce(p_reason, ''), true);
  update telima.deliveries set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid,
         cancel_reason = nullif(trim(p_reason), '')
   where id = p_delivery_id returning * into v_del;

  if v_del.payment_status = 'paid' and v_del.customer_id is not null then
    perform telima.wallet_apply(v_del.customer_id, 'refund', v_del.total_price, v_del.id, null,
                                'Remboursement ' || v_del.code);
    update telima.payments set status = 'refunded' where delivery_id = v_del.id and status = 'paid';
    update telima.deliveries set payment_status = 'refunded' where id = v_del.id returning * into v_del;
  else
    update telima.payments set status = 'cancelled' where delivery_id = v_del.id and status = 'pending';
    update telima.deliveries set payment_status = 'cancelled' where id = v_del.id returning * into v_del;
  end if;

  if v_staff then
    perform telima.log_admin_action('cancel_delivery', 'deliveries', v_del.id::text, jsonb_build_object('code', v_del.code, 'reason', p_reason));
  end if;
  return v_del;
end $$;

create or replace function telima.can_access_delivery(p_delivery_id uuid)
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (
    select 1 from telima.deliveries d
     where d.id = p_delivery_id
       and (d.customer_id = auth.uid() or d.driver_id = auth.uid() or telima.is_staff()
            or (d.business_id is not null and exists (
                  select 1 from telima.business_members m where m.business_id = d.business_id and m.user_id = auth.uid())))
  )
$$;

create or replace function telima.get_delivery_driver(p_delivery_id uuid)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_res jsonb;
begin
  if not telima.can_access_delivery(p_delivery_id) then
    raise exception 'Livraison introuvable' using errcode = 'P0002';
  end if;
  select jsonb_build_object(
           'driver_id', u.id,
           'first_name', split_part(u.full_name, ' ', 1),
           'full_name', u.full_name,
           'phone', u.phone,
           'avatar_url', u.avatar_url,
           'rating_avg', d.rating_avg,
           'rating_count', d.rating_count,
           'vehicle_type', v.type,
           'vehicle_label', concat_ws(' ', v.brand, v.model, v.color),
           'plate_number', v.plate_number,
           'lat', d.current_lat,
           'lng', d.current_lng,
           'last_location_at', d.last_location_at,
           'eta_minutes', del.eta_minutes)
    into v_res
    from telima.deliveries del
    join telima.users u on u.id = del.driver_id
    join telima.drivers d on d.user_id = del.driver_id
    left join telima.vehicles v on v.id = del.vehicle_id
   where del.id = p_delivery_id
     and del.status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff', 'handed_over', 'completed');
  return v_res;
end $$;
