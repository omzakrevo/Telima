-- Module « Voyages » : réservation de tickets de car (Ouaga ↔ Bobo, etc.) avec confirmation et e-ticket,
-- et livraison possible du ticket papier par un livreur Telima.
--
-- * Une compagnie de transport publie ses départs (ville de départ / d'arrivée, date et heure, prix, places).
--   Elle est gérée soit par son propriétaire (compte Telima), soit par l'administration (owner_id null)
--   pour les compagnies pas encore inscrites.
-- * Le client réserve : les places sont bloquées tout de suite, la réservation attend la confirmation.
-- * La compagnie (ou l'administration) confirme : le client obtient un e-ticket avec QR code.
--   - Ticket « e-ticket » : il paie au guichet de la gare avant le départ.
--   - Ticket « livraison » : à la confirmation, une livraison Telima est créée (gare → client) ; le livreur
--     apporte le ticket papier et encaisse en espèces le prix des billets (pour la compagnie) + les frais de livraison.
-- * À l'embarquement, la compagnie contrôle l'e-ticket (QR code ou code VOY-…) et le marque « embarqué ».

create type telima.travel_booking_status as enum
  ('pending', 'confirmed', 'out_for_delivery', 'delivered', 'boarded', 'rejected', 'cancelled');

-- ---------------------------------------------------------------------
-- Compagnies de transport
-- ---------------------------------------------------------------------
create table telima.transport_companies (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid references telima.users(id) on delete set null,   -- null = gérée par l'administration
  created_by         uuid references telima.users(id) on delete set null,
  slug               text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) between 2 and 50),
  name               text not null check (char_length(name) between 2 and 80),
  description        text check (description is null or char_length(description) <= 500),
  phone              text,
  city               text,                                     -- ville du siège / de la gare principale
  station_address    text,                                     -- gare principale (retrait des tickets papier)
  lat                double precision not null check (lat between -90 and 90),
  lng                double precision not null check (lng between -180 and 180),
  logo_path          text,                                     -- compartiment public telima-voyages
  accepting_bookings boolean not null default true,
  delivers_tickets   boolean not null default true,            -- propose la livraison du ticket papier
  ticket_delivery_radius_km numeric(5,1) not null default 20 check (ticket_delivery_radius_km >= 0),
  status             telima.place_status not null default 'approved',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index idx_transport_companies_owner on telima.transport_companies(owner_id);
create index idx_transport_companies_status on telima.transport_companies(status);
create trigger trg_transport_companies_updated before update on telima.transport_companies
  for each row execute function telima.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Départs (voyages)
-- ---------------------------------------------------------------------
create table telima.travel_trips (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references telima.transport_companies(id) on delete cascade,
  from_city         text not null check (char_length(from_city) between 2 and 60),
  to_city           text not null check (char_length(to_city) between 2 and 60),
  departure_at      timestamptz not null,
  duration_minutes  integer check (duration_minutes is null or duration_minutes between 10 and 4320),
  bus_class         text check (bus_class is null or char_length(bus_class) <= 40),   -- « Classique, VIP, Climatisé… »
  price             integer not null check (price >= 0),
  seats_total       integer not null check (seats_total between 1 and 200),
  seats_available   integer not null check (seats_available >= 0),
  departure_station text,                                     -- gare de départ (si différente de la gare principale)
  station_lat       double precision check (station_lat is null or station_lat between -90 and 90),
  station_lng       double precision check (station_lng is null or station_lng between -180 and 180),
  notes             text check (notes is null or char_length(notes) <= 300),
  status            text not null default 'scheduled' check (status in ('scheduled', 'cancelled')),
  cancel_reason     text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (seats_available <= seats_total),
  check (lower(from_city) <> lower(to_city))
);
create index idx_travel_trips_company on telima.travel_trips(company_id, departure_at);
create index idx_travel_trips_search on telima.travel_trips(status, departure_at);
create trigger trg_travel_trips_updated before update on telima.travel_trips
  for each row execute function telima.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Réservations
-- ---------------------------------------------------------------------
create table telima.travel_bookings (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique,
  qr_token         text not null,                              -- secret du QR code de l'e-ticket
  trip_id          uuid not null references telima.travel_trips(id) on delete restrict,
  company_id       uuid not null references telima.transport_companies(id) on delete cascade,
  customer_id      uuid not null references telima.users(id) on delete cascade,
  status           telima.travel_booking_status not null default 'pending',
  passengers       integer not null check (passengers between 1 and 10),
  passenger_names  text[] not null default '{}',
  customer_name    text not null,
  customer_phone   text not null,
  note             text check (note is null or char_length(note) <= 300),
  ticket_mode      text not null check (ticket_mode in ('eticket', 'delivery')),
  dropoff_address  text,
  dropoff_lat      double precision,
  dropoff_lng      double precision,
  dropoff_note     text,
  unit_price       integer not null check (unit_price >= 0),
  tickets_total    integer not null check (tickets_total >= 0),
  delivery_fee     integer not null default 0 check (delivery_fee >= 0),
  total            integer not null check (total >= 0),
  distance_km      numeric(7,2),
  payment_status   telima.gas_payment_status not null default 'unpaid',
  seat_numbers     text,                                       -- renseigné par la compagnie à la confirmation
  ticket_number    text,                                       -- numéro du ticket de la compagnie
  company_message  text,
  reject_reason    text,
  delivery_id      uuid references telima.deliveries(id) on delete set null,
  confirmed_at     timestamptz,
  confirmed_by     uuid references telima.users(id) on delete set null,
  boarded_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (cardinality(passenger_names) <= 10),
  check (ticket_mode = 'eticket' or (dropoff_lat is not null and dropoff_lng is not null and dropoff_address is not null))
);
create index idx_travel_bookings_customer on telima.travel_bookings(customer_id, created_at desc);
create index idx_travel_bookings_company on telima.travel_bookings(company_id, created_at desc);
create index idx_travel_bookings_trip on telima.travel_bookings(trip_id);
create index idx_travel_bookings_delivery on telima.travel_bookings(delivery_id);
create trigger trg_travel_bookings_updated before update on telima.travel_bookings
  for each row execute function telima.tg_set_updated_at();

-- ---------------------------------------------------------------------
-- Aides
-- ---------------------------------------------------------------------
-- Propriétaire de la compagnie, ou équipe Telima (qui gère aussi les compagnies sans propriétaire)
create or replace function telima.is_company_manager(p_company uuid)
returns boolean language sql stable security definer set search_path = telima, public as $$
  select telima.is_staff()
      or exists (select 1 from telima.transport_companies where id = p_company and owner_id = auth.uid());
$$;

-- Texte comparable : minuscules, sans accents ni tirets (« Bobo-Dioulasso » = « bobo dioulasso »)
create or replace function telima._travel_norm(p text)
returns text language sql immutable as $$
  select trim(regexp_replace(lower(translate(coalesce(p, ''), 'àâäÀÂÄéèêëÉÈÊËîïÎÏôöÔÖùûüÙÛÜçÇ', 'aaaaaaeeeeeeeeiiiioooouuuuuucc')),
                             '[^a-z0-9]+', ' ', 'g'));
$$;

create or replace function telima.make_company_slug(p_name text)
returns text language plpgsql volatile set search_path = telima, public as $$
declare v_base text; v_slug text; v_try int := 0;
begin
  v_base := left(replace(telima._travel_norm(p_name), ' ', '-'), 40);
  v_base := trim(both '-' from v_base);
  if char_length(v_base) < 2 then v_base := 'compagnie'; end if;
  v_slug := v_base;
  while exists (select 1 from telima.transport_companies where slug = v_slug) loop
    v_try := v_try + 1;
    v_slug := v_base || '-' || substr(md5(random()::text || clock_timestamp()::text), 1, case when v_try < 4 then 3 else 6 end);
  end loop;
  return v_slug;
end $$;

-- Prévient la compagnie : son propriétaire, ou l'équipe Telima si elle est gérée par l'administration
create or replace function telima._travel_notify_company(p_company uuid, p_type text, p_title text, p_body text, p_data jsonb)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from telima.transport_companies where id = p_company;
  if v_owner is not null then
    perform telima.notify_user(v_owner, p_type, p_title, p_body, p_data);
  else
    perform telima.notify_staff(p_type, p_title, p_body, p_data);
  end if;
end $$;

-- Libellé court d'un voyage : « Ouagadougou → Bobo-Dioulasso, 14/10 07:00 »
create or replace function telima._travel_trip_label(t telima.travel_trips)
returns text language sql stable as $$
  select t.from_city || ' → ' || t.to_city || ', ' || to_char(t.departure_at at time zone 'Africa/Ouagadougou', 'DD/MM HH24:MI');
$$;

-- Les places disponibles ne changent que par les fonctions de réservation (ou en changeant le nombre total de places)
create or replace function telima._travel_seats(p_trip uuid, p_delta int)
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  perform set_config('telima.seat_op', 'on', true);
  update telima.travel_trips set seats_available = seats_available + p_delta where id = p_trip;
  perform set_config('telima.seat_op', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- Gardes
-- ---------------------------------------------------------------------
create or replace function telima.tg_transport_companies_guard()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if not telima.is_staff() then
    new.status := old.status; new.owner_id := old.owner_id; new.slug := old.slug; new.created_by := old.created_by;
  end if;
  return new;
end $$;
create trigger trg_transport_companies_guard before update on telima.transport_companies
  for each row execute function telima.tg_transport_companies_guard();

create or replace function telima.tg_travel_trips_guard()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_booked int;
begin
  if tg_op = 'INSERT' then
    new.seats_available := new.seats_total;
    new.status := 'scheduled';
    new.cancel_reason := null;
    if new.departure_at < now() then raise exception 'La date de départ est déjà passée' using errcode = '22023'; end if;
    return new;
  end if;
  if new.company_id is distinct from old.company_id then
    raise exception 'Un départ ne peut pas changer de compagnie' using errcode = '22023';
  end if;
  -- Annulation : uniquement par travel_trip_cancel (qui prévient les voyageurs)
  if new.status is distinct from old.status and coalesce(current_setting('telima.trip_op', true), 'off') <> 'on' then
    new.status := old.status; new.cancel_reason := old.cancel_reason;
  end if;
  if new.seats_total <> old.seats_total then
    v_booked := old.seats_total - old.seats_available;
    if new.seats_total < v_booked then
      raise exception 'Déjà % place(s) réservée(s) : le total ne peut pas être inférieur', v_booked using errcode = 'P0001';
    end if;
    new.seats_available := new.seats_total - v_booked;
  elsif new.seats_available is distinct from old.seats_available
        and coalesce(current_setting('telima.seat_op', true), 'off') <> 'on' then
    new.seats_available := old.seats_available;
  end if;
  return new;
end $$;
create trigger trg_travel_trips_guard before insert or update on telima.travel_trips
  for each row execute function telima.tg_travel_trips_guard();

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table telima.transport_companies enable row level security;
alter table telima.travel_trips enable row level security;
alter table telima.travel_bookings enable row level security;

create policy transport_companies_read on telima.transport_companies for select
  using (status = 'approved' or owner_id = auth.uid() or telima.is_staff());
create policy transport_companies_admin on telima.transport_companies for all
  using (telima.is_staff()) with check (telima.is_staff());
create policy transport_companies_owner_update on telima.transport_companies for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy travel_trips_read on telima.travel_trips for select
  using (exists (select 1 from telima.transport_companies c where c.id = company_id
                 and (c.status = 'approved' or c.owner_id = auth.uid() or telima.is_staff())));
create policy travel_trips_manage on telima.travel_trips for all
  using (telima.is_company_manager(company_id)) with check (telima.is_company_manager(company_id));

create policy travel_bookings_read on telima.travel_bookings for select
  using (customer_id = auth.uid() or telima.is_company_manager(company_id));

grant select on telima.transport_companies, telima.travel_trips, telima.travel_bookings to authenticated;
grant update on telima.transport_companies to authenticated;
grant insert, update, delete on telima.travel_trips to authenticated;

-- ---------------------------------------------------------------------
-- Logos : compartiment public ; chacun écrit dans son dossier
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('telima-voyages', 'telima-voyages', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy telima_voyages_upload_own on storage.objects for insert to authenticated
  with check (bucket_id = 'telima-voyages' and (storage.foldername(name))[1] = auth.uid()::text);
create policy telima_voyages_read on storage.objects for select using (bucket_id = 'telima-voyages');
create policy telima_voyages_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'telima-voyages' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- Créer une compagnie
-- p = { name, description?, phone?, city?, station_address, lat, lng, logo_path?, delivers_tickets?, ticket_delivery_radius_km? }
-- ---------------------------------------------------------------------
create or replace function telima._insert_company(p jsonb, p_owner uuid, p_created_by uuid)
returns telima.transport_companies language plpgsql security definer set search_path = telima, public as $$
declare v_row telima.transport_companies;
begin
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'Le nom de la compagnie est obligatoire' using errcode = '22023'; end if;
  if p->>'lat' is null or p->>'lng' is null then raise exception 'Placez la gare sur la carte' using errcode = '22023'; end if;
  insert into telima.transport_companies(owner_id, created_by, slug, name, description, phone, city, station_address, lat, lng,
                                         logo_path, delivers_tickets, ticket_delivery_radius_km)
  values (p_owner, p_created_by, telima.make_company_slug(p->>'name'), trim(p->>'name'), nullif(trim(p->>'description'), ''),
          case when coalesce(trim(p->>'phone'), '') <> '' then telima.normalize_phone(p->>'phone') end,
          nullif(trim(p->>'city'), ''), nullif(trim(p->>'station_address'), ''),
          (p->>'lat')::float8, (p->>'lng')::float8, nullif(p->>'logo_path', ''),
          coalesce((p->>'delivers_tickets')::boolean, true), coalesce((p->>'ticket_delivery_radius_km')::numeric, 20))
  returning * into v_row;
  return v_row;
end $$;

-- Une compagnie s'inscrit elle-même (active tout de suite ; l'administration peut la suspendre)
create or replace function telima.register_transport_company(p jsonb)
returns telima.transport_companies language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_row telima.transport_companies;
begin
  if (select count(*) from telima.transport_companies where owner_id = v_uid) >= 3 then
    raise exception 'Vous avez atteint le maximum de 3 compagnies' using errcode = 'P0001';
  end if;
  v_row := telima._insert_company(p, v_uid, v_uid);
  perform telima.notify_staff('company_new', 'Nouvelle compagnie de transport', v_row.name, jsonb_build_object('company_id', v_row.id));
  return v_row;
end $$;

-- L'administration saisit une compagnie qui n'est pas (encore) inscrite : elle la gère elle-même
create or replace function telima.admin_create_transport_company(p jsonb)
returns telima.transport_companies language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff(); v_row telima.transport_companies;
begin
  v_row := telima._insert_company(p, null, v_uid);
  perform telima.log_admin_action('company_create', 'compagnie', v_row.id::text, jsonb_build_object('name', v_row.name));
  return v_row;
end $$;

-- L'administration confie une compagnie à un compte (téléphone), ou la reprend (p_phone vide)
create or replace function telima.admin_set_company_owner(p_company_id uuid, p_phone text)
returns telima.transport_companies language plpgsql security definer set search_path = telima, public as $$
declare v_owner uuid; v_row telima.transport_companies;
begin
  perform telima.require_staff();
  if coalesce(trim(p_phone), '') <> '' then
    select id into v_owner from telima.users where phone = telima.normalize_phone(p_phone);
    if v_owner is null then raise exception 'Aucun compte Telima avec ce numéro' using errcode = 'P0002'; end if;
  end if;
  update telima.transport_companies set owner_id = v_owner where id = p_company_id returning * into v_row;
  if not found then raise exception 'Compagnie introuvable' using errcode = 'P0002'; end if;
  perform telima.log_admin_action('company_owner', 'compagnie', p_company_id::text, jsonb_build_object('owner_id', v_owner));
  if v_owner is not null then
    perform telima.notify_user(v_owner, 'company_status', 'Compagnie confiée', 'Vous gérez maintenant ' || v_row.name || ' sur Telima.',
                               jsonb_build_object('company_id', v_row.id));
  end if;
  return v_row;
end $$;

-- ---------------------------------------------------------------------
-- Lecture publique (sans compte)
-- ---------------------------------------------------------------------
create or replace function telima._travel_trip_json(t telima.travel_trips, c telima.transport_companies)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', t.id, 'company_id', c.id, 'company_name', c.name, 'company_slug', c.slug, 'company_logo', c.logo_path,
    'company_phone', c.phone, 'delivers_tickets', c.delivers_tickets and c.accepting_bookings,
    'from_city', t.from_city, 'to_city', t.to_city, 'departure_at', t.departure_at, 'duration_minutes', t.duration_minutes,
    'bus_class', t.bus_class, 'price', t.price, 'seats_total', t.seats_total, 'seats_available', t.seats_available,
    'departure_station', coalesce(t.departure_station, c.station_address),
    'station_lat', coalesce(t.station_lat, c.lat), 'station_lng', coalesce(t.station_lng, c.lng),
    'notes', t.notes, 'status', t.status, 'accepting_bookings', c.accepting_bookings);
$$;

-- Recherche : ville de départ / d'arrivée (début ou partie du nom, sans accents) et jour (heure du Burkina)
create or replace function telima.search_travel_trips(p_from text default null, p_to text default null,
                                                      p_date date default null, p_limit integer default 80)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_from text := nullif(telima._travel_norm(p_from), ''); v_to text := nullif(telima._travel_norm(p_to), '');
begin
  return coalesce((
    select jsonb_agg(telima._travel_trip_json(t, c) order by t.departure_at)
      from (select t.* from telima.travel_trips t
              join telima.transport_companies c on c.id = t.company_id
             where t.status = 'scheduled' and c.status = 'approved'
               and t.departure_at > now() + interval '15 minutes'
               and (v_from is null or telima._travel_norm(t.from_city) like '%' || v_from || '%')
               and (v_to is null or telima._travel_norm(t.to_city) like '%' || v_to || '%')
               and (p_date is null or (t.departure_at at time zone 'Africa/Ouagadougou')::date = p_date)
             order by t.departure_at
             limit greatest(1, least(coalesce(p_limit, 80), 200))) t
      join telima.transport_companies c on c.id = t.company_id), '[]'::jsonb);
end $$;

-- Villes proposées dans la recherche (départs à venir)
create or replace function telima.travel_cities()
returns jsonb language sql stable security definer set search_path = telima, public as $$
  select coalesce(jsonb_agg(x.city order by x.city), '[]'::jsonb) from (
    select distinct on (telima._travel_norm(c)) c as city from (
      select t.from_city as c from telima.travel_trips t join telima.transport_companies k on k.id = t.company_id
       where t.status = 'scheduled' and t.departure_at > now() and k.status = 'approved'
      union all
      select t.to_city from telima.travel_trips t join telima.transport_companies k on k.id = t.company_id
       where t.status = 'scheduled' and t.departure_at > now() and k.status = 'approved') s
    order by telima._travel_norm(c), c) x;
$$;

-- Page publique d'une compagnie (lien partagé /v/<slug>) : ses prochains départs
create or replace function telima.transport_company_by_slug(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_c telima.transport_companies;
begin
  select * into v_c from telima.transport_companies where slug = lower(trim(p_slug)) and status = 'approved';
  if not found then return null; end if;
  return jsonb_build_object(
    'id', v_c.id, 'slug', v_c.slug, 'name', v_c.name, 'description', v_c.description, 'phone', v_c.phone,
    'city', v_c.city, 'station_address', v_c.station_address, 'lat', v_c.lat, 'lng', v_c.lng, 'logo_path', v_c.logo_path,
    'accepting_bookings', v_c.accepting_bookings, 'delivers_tickets', v_c.delivers_tickets,
    'trips', coalesce((select jsonb_agg(telima._travel_trip_json(t, v_c) order by t.departure_at)
                         from (select * from telima.travel_trips t
                                where t.company_id = v_c.id and t.status = 'scheduled' and t.departure_at > now() + interval '15 minutes'
                                order by t.departure_at limit 60) t), '[]'::jsonb));
end $$;

-- Un départ (écran de réservation)
create or replace function telima.travel_trip(p_trip_id uuid)
returns jsonb language sql stable security definer set search_path = telima, public as $$
  select telima._travel_trip_json(t, c) from telima.travel_trips t
    join telima.transport_companies c on c.id = t.company_id
   where t.id = p_trip_id and c.status = 'approved';
$$;

-- ---------------------------------------------------------------------
-- Frais de livraison du ticket : gare de départ → client (tarif « document » de Telima, moto)
-- ---------------------------------------------------------------------
create or replace function telima.travel_ticket_delivery_fee(p_trip_id uuid, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_t telima.travel_trips; v_c telima.transport_companies; v_q jsonb; v_km numeric; v_lat float8; v_lng float8;
begin
  select * into v_t from telima.travel_trips where id = p_trip_id;
  if not found then raise exception 'Voyage introuvable' using errcode = 'P0002'; end if;
  select * into v_c from telima.transport_companies where id = v_t.company_id and status = 'approved';
  if not found then raise exception 'Compagnie introuvable' using errcode = 'P0002'; end if;
  if not v_c.delivers_tickets then raise exception 'Cette compagnie ne propose pas la livraison du ticket' using errcode = 'P0001'; end if;
  v_lat := coalesce(v_t.station_lat, v_c.lat); v_lng := coalesce(v_t.station_lng, v_c.lng);
  v_km := telima.haversine_km(v_lat, v_lng, p_lat, p_lng);
  if v_km > v_c.ticket_delivery_radius_km then
    raise exception 'Adresse trop éloignée de la gare (livraison jusqu''à % km)', v_c.ticket_delivery_radius_km using errcode = 'P0001';
  end if;
  v_q := telima.quote_delivery(v_lat, v_lng, p_lat, p_lng, 'moto', 'petit', false, 0.2, 'document', null, false);
  return jsonb_build_object('fee', (v_q->>'total_price')::int, 'distance_km', (v_q->>'distance_km')::numeric);
end $$;

-- ---------------------------------------------------------------------
-- Réserver : prix relu côté serveur, places bloquées tout de suite
-- p = { trip_id, passengers, passenger_names?: [..], customer_name?, customer_phone?, note?,
--       ticket_mode: 'eticket'|'delivery', dropoff?: {address, lat, lng, note} }
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
  select * into v_c from telima.transport_companies where id = v_t.company_id and status = 'approved';
  if not found then raise exception 'Compagnie introuvable' using errcode = 'P0002'; end if;
  if not v_c.accepting_bookings then raise exception 'Cette compagnie ne prend pas de réservation pour le moment' using errcode = 'P0001'; end if;
  if v_t.status <> 'scheduled' then raise exception 'Ce départ a été annulé' using errcode = 'P0001'; end if;
  if v_t.departure_at <= now() + interval '15 minutes' then raise exception 'Ce départ est trop proche pour réserver' using errcode = 'P0001'; end if;
  if v_n < 1 or v_n > 10 then raise exception 'De 1 à 10 voyageurs par réservation' using errcode = '22023'; end if;
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
    select (f->>'fee')::int, (f->>'distance_km')::numeric into v_fee, v_km
      from (select telima.travel_ticket_delivery_fee(v_t.id, (v_drop->>'lat')::float8, (v_drop->>'lng')::float8) f) x;
  end if;

  insert into telima.travel_bookings(code, qr_token, trip_id, company_id, customer_id, passengers, passenger_names,
      customer_name, customer_phone, note, ticket_mode, dropoff_address, dropoff_lat, dropoff_lng, dropoff_note,
      unit_price, tickets_total, delivery_fee, total, distance_km)
  values (telima.next_code('travel_booking', 'VOY'), substr(md5(random()::text || clock_timestamp()::text || v_uid::text), 1, 16),
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

-- Livraison du ticket papier : gare → client ; le livreur encaisse le prix des billets pour la compagnie
create or replace function telima._travel_create_ticket_delivery(v_b telima.travel_bookings, p_by uuid)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_t telima.travel_trips; v_c telima.transport_companies; v_del telima.deliveries;
begin
  select * into v_t from telima.travel_trips where id = v_b.trip_id;
  select * into v_c from telima.transport_companies where id = v_b.company_id;
  v_del := telima._insert_delivery(
    jsonb_build_object(
      'pickup', jsonb_build_object('address', coalesce(v_t.departure_station, v_c.station_address, v_c.name),
                                   'lat', coalesce(v_t.station_lat, v_c.lat), 'lng', coalesce(v_t.station_lng, v_c.lng),
                                   'contact_name', v_c.name || ' (guichet)', 'contact_phone', coalesce(v_c.phone, v_b.customer_phone),
                                   'instructions', 'Retirer le ticket ' || coalesce(v_b.ticket_number, v_b.code) || ' au guichet'),
      'dropoff', jsonb_build_object('address', v_b.dropoff_address, 'lat', v_b.dropoff_lat, 'lng', v_b.dropoff_lng,
                                    'contact_name', v_b.customer_name, 'contact_phone', v_b.customer_phone,
                                    'instructions', v_b.dropoff_note),
      'package', jsonb_build_object('category', 'document', 'size', 'petit', 'weight_kg', 0.2,
                   'description', 'Ticket de voyage ' || v_b.code || ' — ' || v_c.name || ', ' || telima._travel_trip_label(v_t)
                                  || ', ' || v_b.passengers || ' place(s) — à encaisser auprès du client : '
                                  || v_b.tickets_total || ' FCFA (billets, pour la compagnie)'),
      'vehicle_type', 'moto', 'payment_method', 'cash'),
    v_b.customer_id, v_b.customer_name, v_b.customer_phone, p_by, 'app', null, 1, false, null, null, v_b.delivery_fee);
  perform telima.notify_nearby_drivers(v_del);
  return v_del;
end $$;

-- ---------------------------------------------------------------------
-- Compagnie / administration : traiter une réservation
-- p_action : confirm (p = {seat_numbers?, ticket_number?, message?}) | reject (p = {reason}) | board | paid
-- ---------------------------------------------------------------------
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
        v_c.name || ' · ' || telima._travel_trip_label(v_t) || '. Votre e-ticket est prêt : '
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
  else
    raise exception 'Action impossible pour une réservation « % »', v_b.status using errcode = 'P0001';
  end if;
  return v_b;
end $$;

-- Client : annuler tant que ce n'est pas confirmé, ou un e-ticket confirmé jusqu'à 2 h avant le départ
create or replace function telima.cancel_travel_booking(p_booking_id uuid)
returns telima.travel_bookings language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_b telima.travel_bookings; v_t telima.travel_trips;
begin
  select * into v_b from telima.travel_bookings where id = p_booking_id and customer_id = v_uid for update;
  if not found then raise exception 'Réservation introuvable' using errcode = 'P0002'; end if;
  select * into v_t from telima.travel_trips where id = v_b.trip_id;
  if not (v_b.status = 'pending'
          or (v_b.status = 'confirmed' and v_b.delivery_id is null and v_t.departure_at > now() + interval '2 hours')) then
    raise exception 'Annulation impossible ici : appelez la compagnie' using errcode = 'P0001';
  end if;
  update telima.travel_bookings set status = 'cancelled' where id = v_b.id returning * into v_b;
  perform telima._travel_seats(v_b.trip_id, v_b.passengers);
  perform telima._travel_notify_company(v_b.company_id, 'travel_booking_cancelled', 'Réservation annulée',
    v_b.code || ' · ' || v_b.passengers || ' place(s) libérée(s)', jsonb_build_object('travel_booking_id', v_b.id, 'company_id', v_b.company_id));
  return v_b;
end $$;

-- Compagnie : annuler un départ (les voyageurs sont prévenus ; livraisons de tickets pas encore prises annulées)
create or replace function telima.travel_trip_cancel(p_trip_id uuid, p_reason text default null)
returns telima.travel_trips language plpgsql security definer set search_path = telima, public as $$
declare v_t telima.travel_trips; v_c telima.transport_companies; v_b record;
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
    if v_b.delivery_id is not null then
      -- Comme telima.cancel_delivery (paiement en espèces, rien à rembourser) ; seulement si aucun livreur n'est parti
      perform set_config('telima.status_note', 'Départ annulé par la compagnie', true);
      update telima.deliveries set status = 'cancelled', cancelled_at = now(), cancelled_by = auth.uid(),
             cancel_reason = 'Départ annulé par la compagnie', payment_status = 'cancelled'
       where id = v_b.delivery_id and status in ('created', 'searching');
      if found then
        update telima.payments set status = 'cancelled' where delivery_id = v_b.delivery_id and status = 'pending';
      end if;
    end if;
    perform telima.notify_user(v_b.customer_id, 'travel_booking_cancelled', 'Départ annulé',
      v_c.name || ' · ' || telima._travel_trip_label(v_t) || coalesce(' : ' || v_t.cancel_reason, ''),
      jsonb_build_object('travel_booking_id', v_b.id));
  end loop;
  return v_t;
end $$;

-- La réservation suit la livraison de son ticket
create or replace function telima.tg_travel_follow_delivery()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_b telima.travel_bookings;
begin
  select * into v_b from telima.travel_bookings where delivery_id = new.id for update;
  if not found or v_b.status in ('delivered', 'boarded', 'cancelled', 'rejected') then return new; end if;
  if new.status in ('picked_up', 'in_transit', 'at_dropoff') and v_b.status <> 'out_for_delivery' then
    update telima.travel_bookings set status = 'out_for_delivery' where id = v_b.id;
  elsif new.status in ('handed_over', 'completed') then
    update telima.travel_bookings set status = 'delivered', payment_status = 'paid' where id = v_b.id;
  elsif new.status = 'cancelled' then
    -- Livraison annulée : la réservation reste valable en e-ticket, à payer au guichet
    update telima.travel_bookings set status = 'confirmed', ticket_mode = 'eticket', delivery_id = null,
           delivery_fee = 0, total = tickets_total
     where id = v_b.id;
    perform telima.notify_user(v_b.customer_id, 'travel_booking_confirmed', 'Livraison du ticket annulée',
      'Votre réservation ' || v_b.code || ' reste valable : présentez votre e-ticket et payez au guichet.',
      jsonb_build_object('travel_booking_id', v_b.id));
  end if;
  return new;
end $$;
create trigger trg_travel_follow_delivery after update of status on telima.deliveries
  for each row when (old.status is distinct from new.status) execute function telima.tg_travel_follow_delivery();

-- ---------------------------------------------------------------------
-- Contrôle à l'embarquement : QR code de l'e-ticket (« TELIMA-VOY:<code>:<secret> ») ou code VOY-… saisi
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
  select * into v_b from telima.travel_bookings where code = v_code and company_id = p_company_id;
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

-- Statistiques de la compagnie
create or replace function telima.transport_company_dashboard(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
begin
  perform telima.require_active_user();
  if not telima.is_company_manager(p_company_id) then raise exception 'Accès refusé' using errcode = '42501'; end if;
  return jsonb_build_object(
    'pending', (select count(*) from telima.travel_bookings where company_id = p_company_id and status = 'pending'),
    'today', (select count(*) from telima.travel_bookings where company_id = p_company_id and created_at >= date_trunc('day', now())),
    'upcoming_trips', (select count(*) from telima.travel_trips where company_id = p_company_id and status = 'scheduled' and departure_at > now()),
    'seats_sold_week', coalesce((select sum(passengers) from telima.travel_bookings
                                  where company_id = p_company_id and status in ('confirmed', 'out_for_delivery', 'delivered', 'boarded')
                                    and created_at >= now() - interval '7 days'), 0));
end $$;

-- Administrateur : suspendre ou rétablir une compagnie
create or replace function telima.admin_set_transport_company_status(p_company_id uuid, p_status telima.place_status)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_c telima.transport_companies;
begin
  perform telima.require_staff();
  update telima.transport_companies set status = p_status where id = p_company_id returning * into v_c;
  if not found then raise exception 'Compagnie introuvable' using errcode = 'P0002'; end if;
  perform telima.log_admin_action('company_status', 'compagnie', p_company_id::text, jsonb_build_object('status', p_status));
  if v_c.owner_id is not null then
    perform telima.notify_user(v_c.owner_id, 'company_status',
      case when p_status = 'approved' then 'Compagnie rétablie' else 'Compagnie suspendue' end,
      v_c.name, jsonb_build_object('company_id', p_company_id));
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Droits d'exécution
-- ---------------------------------------------------------------------
revoke all on function
  telima.is_company_manager(uuid), telima._travel_norm(text), telima.make_company_slug(text),
  telima._travel_notify_company(uuid, text, text, text, jsonb), telima._travel_trip_label(telima.travel_trips),
  telima._travel_seats(uuid, int), telima._insert_company(jsonb, uuid, uuid),
  telima.register_transport_company(jsonb), telima.admin_create_transport_company(jsonb),
  telima.admin_set_company_owner(uuid, text),
  telima._travel_trip_json(telima.travel_trips, telima.transport_companies),
  telima.search_travel_trips(text, text, date, integer), telima.travel_cities(), telima.transport_company_by_slug(text),
  telima.travel_trip(uuid), telima.travel_ticket_delivery_fee(uuid, double precision, double precision),
  telima.create_travel_booking(jsonb), telima._travel_create_ticket_delivery(telima.travel_bookings, uuid),
  telima.travel_booking_action(uuid, text, jsonb), telima.cancel_travel_booking(uuid),
  telima.travel_trip_cancel(uuid, text), telima.check_travel_ticket(uuid, text),
  telima.transport_company_dashboard(uuid), telima.admin_set_transport_company_status(uuid, telima.place_status)
  from public, anon, authenticated;
-- Lecture publique (lien partagé, recherche sans compte)
grant execute on function telima.search_travel_trips(text, text, date, integer), telima.travel_cities(),
  telima.transport_company_by_slug(text), telima.travel_trip(uuid), telima._travel_norm(text)
  to anon, authenticated, service_role;
grant execute on function telima.is_company_manager(uuid), telima.register_transport_company(jsonb),
  telima.admin_create_transport_company(jsonb), telima.admin_set_company_owner(uuid, text),
  telima.travel_ticket_delivery_fee(uuid, double precision, double precision), telima.create_travel_booking(jsonb),
  telima.travel_booking_action(uuid, text, jsonb), telima.cancel_travel_booking(uuid),
  telima.travel_trip_cancel(uuid, text), telima.check_travel_ticket(uuid, text),
  telima.transport_company_dashboard(uuid), telima.admin_set_transport_company_status(uuid, telima.place_status)
  to authenticated, service_role;

-- Chemin de recherche fixe pour les fonctions utilitaires (alerte de sécurité Supabase).
-- Appliqué en production sous le nom telima_18b_voyages_search_path.
alter function telima._travel_norm(text) set search_path = telima, public;
alter function telima._travel_trip_label(telima.travel_trips) set search_path = telima, public;
alter function telima._travel_trip_json(telima.travel_trips, telima.transport_companies) set search_path = telima, public;
