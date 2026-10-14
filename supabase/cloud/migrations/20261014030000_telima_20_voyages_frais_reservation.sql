-- Module « Voyages » : frais de réservation Telima (500 FCFA par réservation), payés par Mobile Money.
--
-- * Le ticket se retire au guichet de la compagnie (e-ticket) et se paie là-bas.
-- * Le service de réservation Telima coûte 500 F par réservation (pas par voyageur), réglés en Mobile Money
--   (Orange Money ou Moov Money) avec le circuit « Paiement manuel » déjà en place :
--   le client déclare son paiement, l'administrateur le vérifie dans « Paiements à vérifier ».
-- * Tant que les frais ne sont pas reçus, la réservation ne peut pas être confirmée.
--
-- Partie A (sans effet visible) : colonnes, synchronisation du statut des frais, nouvel essai, action « frais reçus ».
-- Partie B : création de la réservation avec les frais, et blocage de la confirmation tant qu'ils ne sont pas payés.

-- =====================================================================
-- Partie A
-- =====================================================================
alter table telima.travel_bookings
  add column if not exists service_fee integer not null default 0 check (service_fee >= 0),
  add column if not exists service_fee_status text not null default 'none'
    check (service_fee_status in ('none', 'unpaid', 'verifying', 'paid', 'failed')),
  add column if not exists fee_payment_id uuid references telima.payments(id) on delete set null;
create index if not exists idx_travel_bookings_fee_payment on telima.travel_bookings(fee_payment_id);

-- Montant des frais (une seule valeur à changer ici)
create or replace function telima.travel_service_fee()
returns integer language sql immutable set search_path = telima, public as $$ select 500 $$;

-- Le statut des frais suit le paiement (déclaré, validé, refusé)
create or replace function telima.tg_travel_fee_sync()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_id uuid; v_status text; v_prev text; v_b telima.travel_bookings;
begin
  v_id := nullif(new.metadata->>'travel_booking_id', '')::uuid;
  if v_id is null then return new; end if;
  v_status := case when new.status = 'paid' then 'paid'
                   when new.status in ('failed', 'cancelled') then 'failed'
                   when new.metadata ? 'declared_at' then 'verifying'
                   else 'unpaid' end;
  select service_fee_status into v_prev from telima.travel_bookings where id = v_id and fee_payment_id = new.id for update;
  if not found or v_prev = v_status then return new; end if;
  update telima.travel_bookings set service_fee_status = v_status where id = v_id returning * into v_b;
  if v_status = 'paid' then
    perform telima.notify_user(v_b.customer_id, 'travel_fee_paid', 'Frais de réservation reçus',
      v_b.code || ' : vos 500 F de frais sont reçus. La compagnie peut maintenant confirmer votre place.',
      jsonb_build_object('travel_booking_id', v_b.id));
    perform telima._travel_notify_company(v_b.company_id, 'travel_booking_new', 'Réservation payée, à confirmer',
      v_b.code || ' · frais de réservation reçus, vous pouvez confirmer.',
      jsonb_build_object('travel_booking_id', v_b.id, 'company_id', v_b.company_id));
  elsif v_status = 'failed' then
    perform telima.notify_user(v_b.customer_id, 'travel_fee_failed', 'Frais de réservation non reçus',
      v_b.code || ' : le paiement des frais n''a pas été reçu. Réessayez depuis votre réservation.',
      jsonb_build_object('travel_booking_id', v_b.id));
  end if;
  return new;
end $$;
drop trigger if exists trg_travel_fee_sync on telima.payments;
create trigger trg_travel_fee_sync after insert or update on telima.payments
  for each row when (new.metadata->>'kind' = 'travel_fee') execute function telima.tg_travel_fee_sync();

-- Même libellé que les autres paiements pour l'équipe : « Réservation VOY-… »
create or replace function telima.declare_manual_payment(p_payment_id uuid, p_payer_phone text, p_txn_ref text default null)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_pay telima.payments; v_label text; v_code text;
begin
  select * into v_pay from telima.payments where id = p_payment_id for update;
  if v_pay.id is null or v_pay.payer_id is distinct from v_uid then
    raise exception 'Paiement introuvable' using errcode = 'P0002';
  end if;
  if v_pay.status not in ('pending', 'failed') then raise exception 'Ce paiement est déjà traité' using errcode = 'P0001'; end if;
  if v_pay.method not in ('orange_money', 'moov_money') then
    raise exception 'Paiement Mobile Money uniquement' using errcode = '22023';
  end if;
  -- nouvel essai après un refus : le paiement repasse en attente
  update telima.payments
     set provider = 'manual', status = 'pending',
         metadata = (metadata - 'failure' - 'sms_id' - 'sms_ref') || jsonb_build_object(
           'manual', true, 'payer_phone', telima.normalize_phone(p_payer_phone),
           'txn_ref', nullif(upper(trim(coalesce(p_txn_ref, ''))), ''), 'declared_at', now())
   where id = p_payment_id returning * into v_pay;
  if v_pay.delivery_id is not null then
    update telima.deliveries set payment_status = 'pending' where id = v_pay.delivery_id and payment_status = 'failed';
  end if;

  select code into v_code from telima.deliveries where id = v_pay.delivery_id;
  v_label := case when v_pay.metadata->>'kind' = 'topup' then 'Rechargement'
                  when v_pay.metadata->>'kind' = 'travel_fee' then 'Frais de réservation ' || coalesce(v_pay.metadata->>'booking_code', '')
                  else 'Commande ' || coalesce(v_code, '') end;
  perform telima.notify_staff('payment_declared',
    'Paiement ' || case when v_pay.method = 'orange_money' then 'Orange Money' else 'Moov Money' end || ' à vérifier',
    telima.fcfa_txt(v_pay.amount) || ' de ' || (v_pay.metadata->>'payer_phone') || ' · ' || v_label
      || coalesce(' · réf. ' || (v_pay.metadata->>'txn_ref'), ''),
    jsonb_build_object('payment_id', v_pay.id));
  perform telima.notify_user(v_uid, 'payment', 'Paiement en cours de vérification',
    telima.fcfa_txt(v_pay.amount) || ' · ' || v_label || '. Vous serez averti dès sa validation.',
    jsonb_build_object('payment_id', v_pay.id, 'delivery_id', v_pay.delivery_id));
  perform telima._match_payment_sms(v_pay.id, null);
  select * into v_pay from telima.payments where id = p_payment_id;
  return v_pay;
end $$;

-- Le voyageur change de moyen de paiement ou recrée un paiement de frais (Orange Money / Moov Money)
create or replace function telima.retry_travel_fee(p_booking_id uuid, p_method text default null)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_b telima.travel_bookings; v_p telima.payments; v_m text;
begin
  select * into v_b from telima.travel_bookings where id = p_booking_id and customer_id = v_uid for update;
  if not found then raise exception 'Réservation introuvable' using errcode = 'P0002'; end if;
  if v_b.status in ('rejected', 'cancelled') then raise exception 'Cette réservation est annulée' using errcode = 'P0001'; end if;
  if v_b.service_fee <= 0 or v_b.service_fee_status not in ('unpaid', 'failed') then
    raise exception 'Aucun frais à payer pour cette réservation' using errcode = 'P0001';
  end if;
  select * into v_p from telima.payments where id = v_b.fee_payment_id for update;
  v_m := coalesce(nullif(trim(p_method), ''), v_p.method::text, 'orange_money');
  if v_m not in ('orange_money', 'moov_money') then raise exception 'Choisissez Orange Money ou Moov Money' using errcode = '22023'; end if;
  if v_p.id is not null and v_p.status in ('pending', 'failed') then
    update telima.payments set method = v_m::telima.payment_method where id = v_p.id returning * into v_p;
  else
    insert into telima.payments(payer_id, amount, method, status, metadata)
    values (v_uid, v_b.service_fee, v_m::telima.payment_method, 'pending',
            jsonb_build_object('kind', 'travel_fee', 'travel_booking_id', v_b.id, 'booking_code', v_b.code))
    returning * into v_p;
    update telima.travel_bookings set fee_payment_id = v_p.id, service_fee_status = 'unpaid' where id = v_b.id;
  end if;
  return v_p;
end $$;

revoke all on function telima.travel_service_fee(), telima.tg_travel_fee_sync(), telima.retry_travel_fee(uuid, text)
  from public, anon, authenticated;
grant execute on function telima.travel_service_fee() to anon, authenticated, service_role;
grant execute on function telima.retry_travel_fee(uuid, text) to authenticated, service_role;

-- =====================================================================
-- Partie B : réservation avec frais, confirmation bloquée tant qu'ils ne sont pas payés
-- =====================================================================
create or replace function telima.create_travel_booking(p jsonb)
returns telima.travel_bookings language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_user telima.users;
  v_t telima.travel_trips;
  v_c telima.transport_companies;
  v_mode text := coalesce(p->>'ticket_mode', 'eticket');
  v_n int := coalesce((p->>'passengers')::int, 1);
  v_names text[] := '{}';
  v_drop jsonb := p->'dropoff';
  v_fee int := 0;
  v_km numeric;
  v_service int := telima.travel_service_fee();
  v_fee_method text := coalesce(nullif(trim(p->>'fee_method'), ''), 'orange_money');
  v_pid uuid;
  v_row telima.travel_bookings;
begin
  if v_fee_method not in ('orange_money', 'moov_money') then
    raise exception 'Frais de réservation : choisissez Orange Money ou Moov Money' using errcode = '22023';
  end if;
  select * into v_user from telima.users where id = v_uid;
  select * into v_t from telima.travel_trips where id = (p->>'trip_id')::uuid for update;
  if not found then raise exception 'Voyage introuvable' using errcode = 'P0002'; end if;
  -- Libère d'abord les places retenues par des réservations restées sans réponse
  perform telima._travel_expire_pending(v_t.id);
  select * into v_t from telima.travel_trips where id = v_t.id;
  select * into v_c from telima.transport_companies where id = v_t.company_id and status = 'approved';
  if not found then raise exception 'Compagnie introuvable' using errcode = 'P0002'; end if;
  if not v_c.accepting_bookings then raise exception 'Cette compagnie ne prend pas de réservation pour le moment' using errcode = 'P0001'; end if;
  if v_t.status <> 'scheduled' then raise exception 'Ce départ a été annulé' using errcode = 'P0001'; end if;
  if v_t.departure_at <= now() + interval '15 minutes' then raise exception 'Ce départ est trop proche pour réserver' using errcode = 'P0001'; end if;
  if v_n < 1 or v_n > 10 then raise exception 'De 1 à 10 voyageurs par réservation' using errcode = '22023'; end if;
  if (select count(*) from telima.travel_bookings where customer_id = v_uid and status = 'pending') >= 3 then
    raise exception 'Vous avez déjà 3 réservations en attente de confirmation : attendez la réponse des compagnies ou annulez-en une' using errcode = 'P0001';
  end if;
  if v_t.seats_available < v_n then
    raise exception 'Plus que % place(s) disponible(s) sur ce départ', v_t.seats_available using errcode = 'P0001';
  end if;
  if v_mode not in ('eticket', 'delivery') then raise exception 'Mode de ticket invalide' using errcode = '22023'; end if;
  if jsonb_typeof(p->'passenger_names') = 'array' then
    select coalesce(array_agg(left(trim(x), 60)), '{}') into v_names
      from jsonb_array_elements_text(p->'passenger_names') x where trim(x) <> '';
    if cardinality(v_names) > v_n then raise exception 'Trop de noms pour % voyageur(s)', v_n using errcode = '22023'; end if;
  end if;
  if v_mode = 'delivery' then
    if v_t.departure_at <= now() + interval '3 hours' then
      raise exception 'Départ trop proche pour livrer le ticket : choisissez l''e-ticket' using errcode = 'P0001';
    end if;
    if v_drop is null or coalesce(trim(v_drop->>'address'), '') = '' then
      raise exception 'Adresse de livraison du ticket obligatoire' using errcode = '22023';
    end if;
    if coalesce(v_drop->>'lat', '') = '' or coalesce(v_drop->>'lng', '') = '' then
      raise exception 'Placez l''adresse de livraison sur la carte' using errcode = '22023';
    end if;
    select (f->>'fee')::int, (f->>'distance_km')::numeric into v_fee, v_km
      from (select telima.travel_ticket_delivery_fee(v_t.id, (v_drop->>'lat')::float8, (v_drop->>'lng')::float8) f) x;
  end if;

  insert into telima.travel_bookings(code, qr_token, trip_id, company_id, customer_id, passengers, passenger_names,
      customer_name, customer_phone, note, ticket_mode, dropoff_address, dropoff_lat, dropoff_lng, dropoff_note,
      unit_price, tickets_total, delivery_fee, total, distance_km, service_fee, service_fee_status)
  values (telima.next_code('travel_booking', 'VOY'), substr(replace(gen_random_uuid()::text, '-', ''), 1, 20),
      v_t.id, v_c.id, v_uid, v_n, v_names,
      coalesce(nullif(trim(p->>'customer_name'), ''), v_user.full_name),
      telima.normalize_phone(coalesce(nullif(trim(p->>'customer_phone'), ''), v_user.phone)),
      nullif(left(trim(coalesce(p->>'note', '')), 300), ''),
      v_mode,
      case when v_mode = 'delivery' then trim(v_drop->>'address') end,
      case when v_mode = 'delivery' then (v_drop->>'lat')::float8 end,
      case when v_mode = 'delivery' then (v_drop->>'lng')::float8 end,
      case when v_mode = 'delivery' then nullif(trim(v_drop->>'note'), '') end,
      v_t.price, v_t.price * v_n, v_fee, v_t.price * v_n + v_fee, v_km,
      v_service, case when v_service > 0 then 'unpaid' else 'none' end)
  returning * into v_row;

  -- Frais de réservation Telima : paiement Mobile Money en attente (circuit « manuel » existant)
  if v_service > 0 then
    insert into telima.payments(payer_id, amount, method, status, metadata)
    values (v_uid, v_service, v_fee_method::telima.payment_method, 'pending',
            jsonb_build_object('kind', 'travel_fee', 'travel_booking_id', v_row.id, 'booking_code', v_row.code))
    returning id into v_pid;
    update telima.travel_bookings set fee_payment_id = v_pid where id = v_row.id returning * into v_row;
  end if;

  perform telima._travel_seats(v_t.id, -v_n);
  perform telima._travel_notify_company(v_c.id, 'travel_booking_new', 'Nouvelle réservation',
    v_row.code || ' · ' || v_n || ' place(s) · ' || telima._travel_trip_label(v_t) || case when v_service > 0 then ' · frais de réservation à recevoir' else '' end,
    jsonb_build_object('travel_booking_id', v_row.id, 'company_id', v_c.id));
  return v_row;
end $$;

create or replace function telima.travel_booking_action(p_booking_id uuid, p_action text, p jsonb default '{}'::jsonb)
returns telima.travel_bookings language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_b telima.travel_bookings;
  v_t telima.travel_trips;
  v_c telima.transport_companies;
  v_del telima.deliveries;
begin
  select * into v_b from telima.travel_bookings where id = p_booking_id for update;
  if not found then raise exception 'Réservation introuvable' using errcode = 'P0002'; end if;
  if not telima.is_company_manager(v_b.company_id) then
    raise exception 'Cette réservation ne concerne pas votre compagnie' using errcode = '42501';
  end if;
  select * into v_t from telima.travel_trips where id = v_b.trip_id;
  select * into v_c from telima.transport_companies where id = v_b.company_id;
  p := coalesce(p, '{}'::jsonb);

  if p_action = 'confirm' and v_b.status = 'pending' and v_b.service_fee > 0 and v_b.service_fee_status <> 'paid' then
    raise exception 'Les frais de réservation Telima (% F) ne sont pas encore reçus : le voyageur doit d''abord les payer en Mobile Money', v_b.service_fee
      using errcode = 'P0001';
  end if;

  if p_action = 'confirm' and v_b.status = 'pending' then
    update telima.travel_bookings
       set status = 'confirmed', confirmed_at = now(), confirmed_by = v_uid,
           seat_numbers = nullif(left(trim(coalesce(p->>'seat_numbers', '')), 80), ''),
           ticket_number = nullif(left(trim(coalesce(p->>'ticket_number', '')), 40), ''),
           company_message = nullif(left(trim(coalesce(p->>'message', '')), 300), '')
     where id = v_b.id returning * into v_b;
    if v_b.ticket_mode = 'delivery' then
      v_del := telima._travel_create_ticket_delivery(v_b, v_uid);
      update telima.travel_bookings set delivery_id = v_del.id where id = v_b.id returning * into v_b;
      perform telima.notify_user(v_b.customer_id, 'travel_booking_confirmed', 'Réservation confirmée',
        v_c.name || ' · ' || telima._travel_trip_label(v_t) || '. Un livreur vous apporte le ticket : '
        || v_b.total || ' FCFA à payer à la livraison.',
        jsonb_build_object('travel_booking_id', v_b.id, 'delivery_id', v_del.id));
    else
      perform telima.notify_user(v_b.customer_id, 'travel_booking_confirmed', 'Réservation confirmée',
        v_c.name || ' · ' || telima._travel_trip_label(v_t) || '. Retirez votre ticket au guichet : '
        || v_b.tickets_total || ' FCFA à payer au guichet avant le départ.',
        jsonb_build_object('travel_booking_id', v_b.id));
    end if;
  elsif p_action = 'reject' and v_b.status in ('pending', 'confirmed') and v_b.delivery_id is null then
    update telima.travel_bookings set status = 'rejected', reject_reason = nullif(left(trim(coalesce(p->>'reason', '')), 200), '')
     where id = v_b.id returning * into v_b;
    perform telima._travel_seats(v_b.trip_id, v_b.passengers);
    perform telima.notify_user(v_b.customer_id, 'travel_booking_rejected', 'Réservation refusée',
      v_c.name || coalesce(' : ' || v_b.reject_reason, ''), jsonb_build_object('travel_booking_id', v_b.id));
  elsif p_action = 'board' and v_b.status in ('confirmed', 'out_for_delivery', 'delivered') then
    update telima.travel_bookings set status = 'boarded', boarded_at = now(), payment_status = 'paid'
     where id = v_b.id returning * into v_b;
  elsif p_action = 'paid' and v_b.status not in ('rejected', 'cancelled') then
    update telima.travel_bookings set payment_status = 'paid' where id = v_b.id returning * into v_b;
  elsif p_action = 'fee_received' and v_b.service_fee > 0 and v_b.service_fee_status <> 'paid' and v_b.status not in ('rejected', 'cancelled') then
    -- Équipe Telima uniquement : frais reçus en dehors de l'application (appel, SMS Mobile Money…)
    if not telima.is_staff() then raise exception 'Réservé à l''équipe Telima' using errcode = '42501'; end if;
    if v_b.fee_payment_id is null then raise exception 'Aucun paiement de frais pour cette réservation' using errcode = 'P0001'; end if;
    update telima.payments set status = 'pending' where id = v_b.fee_payment_id and status = 'failed';
    perform telima._confirm_payment(v_b.fee_payment_id, coalesce(nullif(trim(p->>'ref'), ''), 'MANUEL'));
    perform telima.log_admin_action('travel_fee_received', 'reservation', v_b.id::text, jsonb_build_object('ref', p->>'ref'));
    select * into v_b from telima.travel_bookings where id = v_b.id;
  else
    raise exception 'Action impossible pour une réservation « % »', v_b.status using errcode = 'P0001';
  end if;
  return v_b;
end $$;
