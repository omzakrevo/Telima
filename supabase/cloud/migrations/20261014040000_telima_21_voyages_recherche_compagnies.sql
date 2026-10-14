-- Voyages : recherche par compagnie et par tranche horaire, liste publique des compagnies, page compagnie plus complète.
-- Heures du Burkina = UTC (Africa/Ouagadougou). Appliquée en production en plusieurs fois : telima_21a…21d (ordre : liste des compagnies,
-- page compagnie, nouvelle recherche, renommage de l'ancienne recherche).

-- Recherche : + compagnie (p_company) et tranche horaire [p_hour_from, p_hour_to[ en heures locales
-- L'ancienne version à 4 paramètres est renommée (et non supprimée : le DROP bloque l'outil d'exécution) pour éviter toute ambiguïté.
alter function telima.search_travel_trips(text, text, date, integer) rename to search_travel_trips_v1;
create or replace function telima.search_travel_trips(p_from text default null, p_to text default null,
                                                      p_date date default null, p_limit integer default 80,
                                                      p_company uuid default null,
                                                      p_hour_from integer default null, p_hour_to integer default null)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_from text := nullif(telima._travel_norm(p_from), ''); v_to text := nullif(telima._travel_norm(p_to), '');
begin
  return coalesce((
    select jsonb_agg(telima._travel_trip_json(t, c) order by t.departure_at)
      from (select t.* from telima.travel_trips t
              join telima.transport_companies c on c.id = t.company_id
             where t.status = 'scheduled' and c.status = 'approved'
               and t.departure_at > now() + interval '15 minutes'
               and (p_company is null or t.company_id = p_company)
               and (v_from is null or telima._travel_norm(t.from_city) like '%' || v_from || '%')
               and (v_to is null or telima._travel_norm(t.to_city) like '%' || v_to || '%')
               and (p_date is null or (t.departure_at at time zone 'Africa/Ouagadougou')::date = p_date)
               and (p_hour_from is null or p_hour_to is null
                    or extract(hour from (t.departure_at at time zone 'Africa/Ouagadougou')) >= p_hour_from
                   and extract(hour from (t.departure_at at time zone 'Africa/Ouagadougou')) < p_hour_to)
             order by t.departure_at
             limit greatest(1, least(coalesce(p_limit, 80), 300))) t
      join telima.transport_companies c on c.id = t.company_id), '[]'::jsonb);
end $$;

-- Compagnies visibles par tout le monde (bandeau de la page Voyages)
create or replace function telima.travel_companies()
returns jsonb language sql stable security definer set search_path = telima, public as $$
  select coalesce(jsonb_agg(x.j order by x.ord, x.name), '[]'::jsonb) from (
    select c.name,
           (select count(*) from telima.travel_trips t where t.company_id = c.id and t.status = 'scheduled' and t.departure_at > now()) = 0 as ord,
           jsonb_build_object('id', c.id, 'slug', c.slug, 'name', c.name, 'city', c.city, 'logo_path', c.logo_path,
                              'accepting_bookings', c.accepting_bookings, 'delivers_tickets', c.delivers_tickets,
                              'description', c.description, 'phone', c.phone, 'station_address', c.station_address,
                              'lat', c.lat, 'lng', c.lng) as j
      from telima.transport_companies c where c.status = 'approved') x;
$$;

-- Page d'une compagnie : 14 prochains jours, jusqu'à 400 départs (horaires par ligne)
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
                                where t.company_id = v_c.id and t.status = 'scheduled'
                                  and t.departure_at > now() + interval '15 minutes'
                                  and t.departure_at < now() + interval '14 days'
                                order by t.departure_at limit 400) t), '[]'::jsonb));
end $$;

revoke execute on function telima.search_travel_trips(text, text, date, integer, uuid, integer, integer), telima.travel_companies()
  from public, anon, authenticated;
grant execute on function telima.search_travel_trips(text, text, date, integer, uuid, integer, integer), telima.travel_companies()
  to anon, authenticated, service_role;
