-- Module « Voyages » : durcissement après relecture de telima_18.
--
-- 1. Une compagnie qui s'inscrit elle-même est « en attente » : l'équipe Telima la valide avant qu'elle soit visible
--    (évite les compagnies imaginaires ou usurpées qui prendraient des réservations et feraient encaisser des billets).
--    Les compagnies saisies par l'équipe (sans propriétaire) restent approuvées tout de suite.
-- 2. Une réservation non confirmée libère ses places au bout de 2 h (ou dès que le départ est passé) ;
--    un client ne peut pas avoir plus de 3 réservations en attente en même temps.
-- 3. Départ annulé : message de remboursement si le voyageur avait déjà payé, alerte de l'équipe si un livreur a déjà le ticket.
-- 4. Départ déplacé : les voyageurs concernés sont prévenus.
-- 5. Adresse de livraison sans position : message clair ; secret du QR code tiré avec gen_random_uuid().
-- 6. Contrôle d'un ticket par son seul numéro (« 12 ») traité côté serveur, sans dépendre de l'année en cours.

-- ---------------------------------------------------------------------
-- 1. Inscription validée par l'équipe Telima
-- ---------------------------------------------------------------------
create or replace function telima._insert_company(p jsonb, p_owner uuid, p_created_by uuid)
returns telima.transport_companies language plpgsql security definer set search_path = telima, public as $$
declare v_row telima.transport_companies;
begin
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'Le nom de la compagnie est obligatoire' using errcode = '22023'; end if;
  if p->>'lat' is null or p->>'lng' is null then raise exception 'Placez la gare sur la carte' using errcode = '22023'; end if;
  insert into telima.transport_companies(owner_id, created_by, slug, name, description, phone, city, station_address, lat, lng,
                                         logo_path, delivers_tickets, ticket_delivery_radius_km, status)
  values (p_owner, p_created_by, telima.make_company_slug(p->>'name'), trim(p->>'name'), nullif(trim(p->>'description'), ''),
          case when coalesce(trim(p->>'phone'), '') <> '' then telima.normalize_phone(p->>'phone') end,
          nullif(trim(p->>'city'), ''), nullif(trim(p->>'station_address'), ''),
          (p->>'lat')::float8, (p->>'lng')::float8, nullif(p->>'logo_path', ''),
          coalesce((p->>'delivers_tickets')::boolean, true), coalesce((p->>'ticket_delivery_radius_km')::numeric, 20),
          -- inscrite par la compagnie : à valider ; saisie par l'équipe (sans propriétaire) : approuvée
          case when p_owner is null then 'approved'::telima.place_status else 'pending'::telima.place_status end)
  returning * into v_row;
  return v_row;
end $$;

create or replace function telima.register_transport_company(p jsonb)
returns telima.transport_companies language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_row telima.transport_companies;
begin
  if (select count(*) from telima.transport_companies where owner_id = v_uid) >= 3 then
    raise exception 'Vous avez atteint le maximum de 3 compagnies' using errcode = 'P0001';
  end if;
  v_row := telima._insert_company(p, v_uid, v_uid);
  perform telima.notify_staff('company_new', 'Compagnie de transport à valider', v_row.name,
                              jsonb_build_object('company_id', v_row.id));
  return v_row;
end $$;

create or replace function telima.admin_set_transport_company_status(p_company_id uuid, p_status telima.place_status)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_c telima.transport_companies; v_old telima.place_status;
begin
  perform telima.require_staff();
  select status into v_old from telima.transport_companies where id = p_company_id;
  update telima.transport_companies set status = p_status where id = p_company_id returning * into v_c;
  if not found then raise exception 'Compagnie introuvable' using errcode = 'P0002'; end if;
  perform telima.log_admin_action('company_status', 'compagnie', p_company_id::text, jsonb_build_object('status', p_status));
  if v_c.owner_id is not null then
    perform telima.notify_user(v_c.owner_id, 'company_status',
      case when p_status = 'approved' and v_old = 'pending' then 'Compagnie validée'
           when p_status = 'approved' then 'Compagnie rétablie'
           when p_status = 'rejected' then 'Inscription refusée'
           else 'Compagnie suspendue' end,
      v_c.name, jsonb_build_object('company_id', p_company_id));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Réservations non confirmées : expiration
-- ---------------------------------------------------------------------
-- Annule les réservations « en attente » depuis plus de 2 h (ou dont le départ est passé), libère les places
-- et prévient le voyageur. p_trip null = tous les départs. Renvoie le nombre de réservations annulées.
create or replace function telima._travel_expire_pending(p_trip uuid default null)
returns integer language plpgsql security definer set search_path = telima, public as $$
declare v_b record; v_n int := 0;
begin
  for v_b in
    select b.id, b.trip_id, b.passengers, b.customer_id, b.code
      from telima.travel_bookings b
      join telima.travel_trips t on t.id = b.trip_id
     where b.status = 'pending'
       and (p_trip is null or b.trip_id = p_trip)
       and (b.created_at < now() - interval '2 hours' or t.departure_at < now())
     order by b.created_at
       for update of b skip locked
  loop
    update telima.travel_bookings
       set status = 'cancelled', reject_reason = 'Délai de confirmation dépassé : la compagnie n''a pas répondu'
     where id = v_b.id;
    perform telima._travel_seats(v_b.trip_id, v_b.passengers);
    perform telima.notify_user(v_b.customer_id, 'travel_booking_cancelled', 'Réservation expirée',
      v_b.code || ' : la compagnie n''a pas confirmé à temps, les places sont libérées. Vous pouvez réserver à nouveau ou appeler la compagnie.',
      jsonb_build_object('travel_booking_id', v_b.id));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

create or replace function telima.expire_stale_travel_bookings()
returns integer language sql security definer set search_path = telima, public as $$
  select telima._travel_expire_pending(null);
$$;

-- Nettoyage automatique toutes les 15 minutes si l'extension pg_cron est active.
-- Sinon l'expiration a lieu à la prochaine réservation sur le même départ (voir create_travel_booking).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('telima-expire-travel-bookings', '*/15 * * * *', 'select telima.expire_stale_travel_bookings()');
  end if;
exception when others then
  raise notice 'pg_cron non disponible : expiration à la demande uniquement (%)', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- 2 + 5. Réservation : plafond d'attente, adresse complète, secret du QR code
-- ---------------------------------------------------------------------
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
  v_row telima.travel_bookings;
begin
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
      unit_price, tickets_total, delivery_fee, total, distance_km)
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
      v_t.price, v_t.price * v_n, v_fee, v_t.price * v_n + v_fee, v_km)
  returning * into v_row;

  perform telima._travel_seats(v_t.id, -v_n);
  perform telima._travel_notify_company(v_c.id, 'travel_booking_new', 'Nouvelle réservation',
    v_row.code || ' · ' || v_n || ' place(s) · ' || telima._travel_trip_label(v_t),
    jsonb_build_object('travel_booking_id', v_row.id, 'company_id', v_c.id));
  return v_row;
end $$;

-- ---------------------------------------------------------------------
-- 3. Départ annulé : remboursement et livraison déjà partie
-- ---------------------------------------------------------------------
create or replace function telima.travel_trip_cancel(p_trip_id uuid, p_reason text default null)
returns telima.travel_trips language plpgsql security definer set search_path = telima, public as $$
declare v_t telima.travel_trips; v_c telima.transport_companies; v_b record; v_msg text; v_cancelled boolean;
begin
  perform telima.require_active_user();
  select * into v_t from telima.travel_trips where id = p_trip_id for update;
  if not found then raise exception 'Départ introuvable' using errcode = 'P0002'; end if;
  if not telima.is_company_manager(v_t.company_id) then raise exception 'Accès refusé' using errcode = '42501'; end if;
  if v_t.status = 'cancelled' then return v_t; end if;
  select * into v_c from telima.transport_companies where id = v_t.company_id;
  perform set_config('telima.trip_op', 'on', true);
  update telima.travel_trips set status = 'cancelled', cancel_reason = nullif(left(trim(coalesce(p_reason, '')), 200), '')
   where id = v_t.id returning * into v_t;
  perform set_config('telima.trip_op', 'off', true);
  for v_b in select * from telima.travel_bookings
              where trip_id = v_t.id and status in ('pending', 'confirmed', 'out_for_delivery', 'delivered') for update loop
    update telima.travel_bookings set status = 'cancelled', reject_reason = coalesce(v_t.cancel_reason, 'Départ annulé par la compagnie')
     where id = v_b.id;
    v_msg := v_c.name || ' · ' || telima._travel_trip_label(v_t) || coalesce(' : ' || v_t.cancel_reason, '');
    if v_b.delivery_id is not null then
      -- Comme telima.cancel_delivery (paiement en espèces, rien à rembourser) ; seulement si aucun livreur n'est parti
      perform set_config('telima.status_note', 'Départ annulé par la compagnie', true);
      update telima.deliveries set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
             cancel_reason = 'Départ annulé par la compagnie', payment_status = 'cancelled'
       where id = v_b.delivery_id and status in ('created', 'searching');
      v_cancelled := found;
      if v_cancelled then
        update telima.payments set status = 'cancelled' where delivery_id = v_b.delivery_id and status = 'pending';
      elsif v_b.status = 'delivered' then
        v_msg := v_msg || ' Le ticket vous a déjà été livré : si vous avez payé, la compagnie doit vous rembourser (billets) — contactez-la.';
      else
        -- Un livreur a déjà retiré ou porte le ticket : l'équipe doit l'arrêter
        v_msg := v_msg || ' Un livreur est déjà en route avec votre ticket : refusez-le, vous ne devez rien payer.';
        perform telima.notify_staff('travel_delivery_conflict', 'Départ annulé : ticket en cours de livraison',
          v_b.code || ' · ' || v_msg, jsonb_build_object('travel_booking_id', v_b.id, 'delivery_id', v_b.delivery_id));
      end if;
    elsif v_b.status in ('confirmed') then
      v_msg := v_msg || ' Si vous avez déjà payé au guichet, demandez le remboursement à la compagnie.';
    end if;
    perform telima.notify_user(v_b.customer_id, 'travel_booking_cancelled', 'Départ annulé', v_msg,
      jsonb_build_object('travel_booking_id', v_b.id));
  end loop;
  return v_t;
end $$;

-- ---------------------------------------------------------------------
-- 4. Départ déplacé : prévenir les voyageurs
-- ---------------------------------------------------------------------
create or replace function telima.tg_travel_trips_notify_move()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_b record; v_name text;
begin
  if new.status <> 'scheduled' or new.departure_at is not distinct from old.departure_at then return new; end if;
  select name into v_name from telima.transport_companies where id = new.company_id;
  for v_b in select id, customer_id from telima.travel_bookings
              where trip_id = new.id and status in ('pending', 'confirmed', 'out_for_delivery', 'delivered') loop
    perform telima.notify_user(v_b.customer_id, 'travel_booking_changed', 'Horaire de départ modifié',
      v_name || ' : nouveau départ ' || telima._travel_trip_label(new) || '. Annulez si cela ne vous convient plus.',
      jsonb_build_object('travel_booking_id', v_b.id));
  end loop;
  return new;
end $$;
drop trigger if exists trg_travel_trips_notify_move on telima.travel_trips;
create trigger trg_travel_trips_notify_move after update of departure_at on telima.travel_trips
  for each row when (old.departure_at is distinct from new.departure_at) execute function telima.tg_travel_trips_notify_move();

-- ---------------------------------------------------------------------
-- 6. Contrôle d'un ticket : « 12 » = dernier ticket de la compagnie dont le numéro se termine par 000012
-- ---------------------------------------------------------------------
create or replace function telima.check_travel_ticket(p_company_id uuid, p_value text)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_val text := trim(coalesce(p_value, ''));
  v_code text; v_token text; v_parts text[];
  v_b telima.travel_bookings; v_t telima.travel_trips;
  v_ok boolean := true; v_msg text := 'Ticket valable';
begin
  perform telima.require_active_user();
  if not telima.is_company_manager(p_company_id) then raise exception 'Accès refusé' using errcode = '42501'; end if;
  if upper(v_val) like 'TELIMA-VOY:%' then
    v_parts := string_to_array(v_val, ':');
    v_code := upper(v_parts[2]); v_token := v_parts[3];
  else
    v_code := upper(v_val);
  end if;
  if v_code ~ '^[0-9]{1,6}$' then
    select * into v_b from telima.travel_bookings
     where company_id = p_company_id and code like 'VOY-%-' || lpad(v_code, 6, '0')
     order by created_at desc limit 1;
  else
    select * into v_b from telima.travel_bookings where code = v_code and company_id = p_company_id;
  end if;
  if not found then
    return jsonb_build_object('valid', false, 'message', 'Aucune réservation ' || v_code || ' pour cette compagnie');
  end if;
  select * into v_t from telima.travel_trips where id = v_b.trip_id;
  if v_token is not null and v_token <> v_b.qr_token then
    v_ok := false; v_msg := 'QR code non valable (copie ou ticket modifié)';
  elsif v_b.status = 'boarded' then
    v_ok := false; v_msg := 'Déjà embarqué le ' || to_char(v_b.boarded_at at time zone 'Africa/Ouagadougou', 'DD/MM à HH24:MI');
  elsif v_b.status in ('pending') then
    v_ok := false; v_msg := 'Réservation pas encore confirmée';
  elsif v_b.status in ('rejected', 'cancelled') then
    v_ok := false; v_msg := 'Réservation annulée';
  elsif v_t.status = 'cancelled' then
    v_ok := false; v_msg := 'Départ annulé';
  end if;
  return jsonb_build_object('valid', v_ok, 'message', v_msg, 'booking_id', v_b.id, 'code', v_b.code, 'status', v_b.status,
    'customer_name', v_b.customer_name, 'customer_phone', v_b.customer_phone, 'passengers', v_b.passengers,
    'passenger_names', v_b.passenger_names, 'seat_numbers', v_b.seat_numbers, 'ticket_mode', v_b.ticket_mode,
    'payment_status', v_b.payment_status, 'tickets_total', v_b.tickets_total, 'trip', telima._travel_trip_label(v_t));
end $$;

-- ---------------------------------------------------------------------
-- Droits d'exécution (create or replace conserve les droits existants ; on fixe ceux des nouvelles fonctions)
-- ---------------------------------------------------------------------
revoke all on function
  telima._travel_expire_pending(uuid), telima.expire_stale_travel_bookings(), telima.tg_travel_trips_notify_move()
  from public, anon, authenticated;
grant execute on function telima.expire_stale_travel_bookings() to service_role;
