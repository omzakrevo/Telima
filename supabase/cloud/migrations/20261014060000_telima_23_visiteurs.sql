-- Telima 23 : compteur de visiteurs (site web et application), connectés ou non.
-- Un visiteur = un identifiant aléatoire gardé sur l'appareil (aucune donnée personnelle).
-- Comptés une fois par jour et par plateforme ; « ouvertures » = nombre de lancements dans la journée.

create table if not exists telima.site_visits (
  day        date        not null,
  visitor_id uuid        not null,
  platform   text        not null check (platform in ('web', 'android', 'ios', 'autre')),
  user_id    uuid,
  opens      integer     not null default 1,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  primary key (day, visitor_id, platform)
);
create index if not exists idx_site_visits_day on telima.site_visits(day);

alter table telima.site_visits enable row level security;
revoke all on telima.site_visits from public, anon, authenticated;

-- Appelée à chaque ouverture du site ou de l'application, avec ou sans compte.
create or replace function telima.track_visit(p_visitor uuid, p_platform text default 'autre')
returns void language plpgsql security definer set search_path = telima, public as $$
declare
  v_platform text := case when p_platform in ('web', 'android', 'ios') then p_platform else 'autre' end;
begin
  if p_visitor is null then return; end if;
  insert into telima.site_visits (day, visitor_id, platform, user_id)
  values ((now() at time zone 'utc')::date, p_visitor, v_platform, auth.uid())
  on conflict (day, visitor_id, platform) do update
    set opens = telima.site_visits.opens + 1,
        last_seen = now(),
        user_id = coalesce(excluded.user_id, telima.site_visits.user_id);
end $$;

grant execute on function telima.track_visit(uuid, text) to anon, authenticated;

-- Tableau de bord administrateur : visiteurs uniques par jour et par plateforme.
create or replace function telima.admin_visitors(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_today date := (now() at time zone 'utc')::date;
  v_rows jsonb;
begin
  perform telima.require_staff();
  select coalesce(jsonb_agg(jsonb_build_object(
           'day', d.day,
           'web', coalesce(a.web, 0),
           'app', coalesce(a.app, 0),
           'total', coalesce(a.total, 0),
           'opens', coalesce(a.opens, 0)) order by d.day), '[]'::jsonb)
    into v_rows
    from generate_series(v_today - (v_days - 1), v_today, interval '1 day') as g(ts)
    cross join lateral (select g.ts::date as day) d
    left join (
      select day,
             count(distinct visitor_id) filter (where platform = 'web')            as web,
             count(distinct visitor_id) filter (where platform <> 'web')           as app,
             count(distinct visitor_id)                                            as total,
             sum(opens)                                                            as opens
        from telima.site_visits
       where day >= v_today - (v_days - 1)
       group by day) a on a.day = d.day;
  return jsonb_build_object(
    'days', v_rows,
    'today_web',  (select count(distinct visitor_id) from telima.site_visits where day = v_today and platform = 'web'),
    'today_app',  (select count(distinct visitor_id) from telima.site_visits where day = v_today and platform <> 'web'),
    'today',      (select count(distinct visitor_id) from telima.site_visits where day = v_today),
    'd7_web',     (select count(distinct visitor_id) from telima.site_visits where day >= v_today - 6 and platform = 'web'),
    'd7_app',     (select count(distinct visitor_id) from telima.site_visits where day >= v_today - 6 and platform <> 'web'),
    'd7',         (select count(distinct visitor_id) from telima.site_visits where day >= v_today - 6),
    'd30_web',    (select count(distinct visitor_id) from telima.site_visits where day >= v_today - 29 and platform = 'web'),
    'd30_app',    (select count(distinct visitor_id) from telima.site_visits where day >= v_today - 29 and platform <> 'web'),
    'd30',        (select count(distinct visitor_id) from telima.site_visits where day >= v_today - 29),
    'all_time',   (select count(distinct visitor_id) from telima.site_visits));
end $$;
