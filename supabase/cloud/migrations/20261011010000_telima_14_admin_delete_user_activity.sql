-- Telima 14 : connexions par jour + suppression complète d'un utilisateur par l'administrateur

-- ─────────────────────────────────────────────────────────────
-- 1. Activité quotidienne : une ligne par utilisateur et par jour
-- ─────────────────────────────────────────────────────────────
create table if not exists telima.daily_activity (
  day        date        not null,
  user_id    uuid        not null references telima.users(id) on delete cascade,
  platform   text,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),
  primary key (day, user_id)
);
create index if not exists idx_daily_activity_user on telima.daily_activity(user_id);

alter table telima.daily_activity enable row level security;
revoke all on telima.daily_activity from public, anon, authenticated;

-- Appelée par l'application à l'ouverture (au plus une fois par jour et par appareil).
create or replace function telima.touch_activity(p_platform text default null)
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  if auth.uid() is null then return; end if;
  insert into telima.daily_activity (day, user_id, platform)
  select (now() at time zone 'utc')::date, u.id, left(p_platform, 20)
    from telima.users u
   where u.id = auth.uid() and u.is_active
  on conflict (day, user_id) do update set last_seen = now();
end $$;

-- Tableau de bord administrateur : connexions par jour sur p_days jours.
create or replace function telima.admin_activity(p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_today date := (now() at time zone 'utc')::date;
  v_rows jsonb;
begin
  perform telima.require_staff();
  select coalesce(jsonb_agg(jsonb_build_object(
           'day', d.day, 'active', coalesce(a.active, 0),
           'clients', coalesce(a.clients, 0), 'drivers', coalesce(a.drivers, 0)) order by d.day), '[]'::jsonb)
    into v_rows
    from generate_series(v_today - (v_days - 1), v_today, interval '1 day') as g(ts)
    cross join lateral (select g.ts::date as day) d
    left join (
      select da.day,
             count(*)                                   as active,
             count(*) filter (where u.role = 'client')  as clients,
             count(*) filter (where u.role = 'driver')  as drivers
        from telima.daily_activity da
        join telima.users u on u.id = da.user_id
       where da.day >= v_today - (v_days - 1)
       group by da.day) a on a.day = d.day;
  return jsonb_build_object(
    'days', v_rows,
    'total_users', (select count(*) from telima.users),
    'active_today', (select count(*) from telima.daily_activity where day = v_today),
    'active_7d', (select count(distinct user_id) from telima.daily_activity where day >= v_today - 6),
    'active_30d', (select count(distinct user_id) from telima.daily_activity where day >= v_today - 29));
end $$;

-- ─────────────────────────────────────────────────────────────
-- 2. Suppression complète d'un utilisateur
-- ─────────────────────────────────────────────────────────────
-- Vérification avant suppression : ce qui bloque et ce qui sera supprimé.
create or replace function telima.admin_delete_user_check(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_u telima.users;
  v_balance integer := 0;
  v_active_deliveries integer;
  v_pending_withdrawals integer;
  v_active_orders integer;
begin
  perform telima.require_admin();
  select * into v_u from telima.users where id = p_user_id;
  if not found then raise exception 'Utilisateur introuvable' using errcode = 'P0001'; end if;

  select coalesce(balance, 0) into v_balance from telima.wallets where user_id = p_user_id;
  v_balance := coalesce(v_balance, 0);

  select count(*) into v_active_deliveries from telima.deliveries d
   where d.status not in ('completed', 'cancelled')
     and (d.customer_id = p_user_id
          or d.driver_id in (select id from telima.drivers where user_id = p_user_id));

  select count(*) into v_pending_withdrawals from telima.withdrawals
   where user_id = p_user_id and status = 'pending';

  select (select count(*) from telima.restaurant_orders o
            where o.status in ('sent','accepted','preparing','ready','out_for_delivery')
              and (o.customer_id = p_user_id
                   or o.restaurant_id in (select id from telima.restaurants where owner_id = p_user_id)))
       + (select count(*) from telima.gas_orders o
            where o.status in ('sent','accepted','preparing','ready','out_for_delivery')
              and (o.customer_id = p_user_id
                   or o.place_id in (select id from telima.places where owner_id = p_user_id)))
    into v_active_orders;

  return jsonb_build_object(
    'id', v_u.id, 'name', v_u.full_name, 'phone', v_u.phone, 'role', v_u.role,
    'is_self', p_user_id = auth.uid(),
    'is_admin', v_u.role = 'admin',
    'wallet_balance', v_balance,
    'active_deliveries', v_active_deliveries,
    'pending_withdrawals', v_pending_withdrawals,
    'active_orders', v_active_orders,
    'restaurants', (select count(*) from telima.restaurants where owner_id = p_user_id),
    'places', (select count(*) from telima.places where owner_id = p_user_id),
    'deliveries_total', (select count(*) from telima.deliveries where customer_id = p_user_id),
    'can_delete', p_user_id <> auth.uid() and v_u.role <> 'admin'
                  and v_active_deliveries = 0 and v_pending_withdrawals = 0 and v_active_orders = 0);
end $$;

-- Suppression définitive : compte, profil, livreur, portefeuille, restaurants, adresses, notifications…
-- L'historique des livraisons est conservé sans nom (la livraison reste, le lien avec le compte disparaît).
create or replace function telima.admin_delete_user(p_user_id uuid, p_force boolean default false)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare
  v_admin uuid := telima.require_admin();
  v_chk jsonb;
  v_u telima.users;
begin
  if p_user_id = v_admin then
    raise exception 'Vous ne pouvez pas supprimer votre propre compte' using errcode = 'P0001';
  end if;
  select * into v_u from telima.users where id = p_user_id;
  if not found then raise exception 'Utilisateur introuvable' using errcode = 'P0001'; end if;
  if v_u.role = 'admin' then
    raise exception 'Retirez d''abord le rôle administrateur de ce compte avant de le supprimer' using errcode = 'P0001';
  end if;

  v_chk := telima.admin_delete_user_check(p_user_id);
  if (v_chk->>'active_deliveries')::int > 0 then
    raise exception 'Suppression impossible : % livraison(s) en cours pour ce compte', v_chk->>'active_deliveries' using errcode = 'P0001';
  end if;
  if (v_chk->>'active_orders')::int > 0 then
    raise exception 'Suppression impossible : % commande(s) de restaurant ou de gaz en cours', v_chk->>'active_orders' using errcode = 'P0001';
  end if;
  if (v_chk->>'pending_withdrawals')::int > 0 then
    raise exception 'Suppression impossible : un retrait est en attente de paiement' using errcode = 'P0001';
  end if;
  if (v_chk->>'wallet_balance')::int <> 0 and not p_force then
    raise exception 'Le portefeuille contient % FCFA. Réglez-le d''abord, ou confirmez la suppression malgré le solde.', v_chk->>'wallet_balance' using errcode = 'P0001';
  end if;

  -- Trace dans le journal AVANT la suppression
  perform telima.log_admin_action('delete_user', 'users', p_user_id::text,
    jsonb_build_object('name', v_u.full_name, 'phone', v_u.phone, 'role', v_u.role,
                       'wallet_balance', v_chk->'wallet_balance', 'forced', p_force));

  -- Liens qui empêcheraient la suppression
  delete from telima.restaurant_orders
   where customer_id = p_user_id
      or restaurant_id in (select id from telima.restaurants where owner_id = p_user_id);
  delete from telima.gas_orders
   where customer_id = p_user_id
      or place_id in (select id from telima.places where owner_id = p_user_id);
  delete from telima.food_orders
   where customer_id = p_user_id
      or business_id in (select id from telima.business_accounts where owner_id = p_user_id);
  delete from telima.business_accounts where owner_id = p_user_id;
  delete from telima.places where owner_id = p_user_id;
  update telima.app_releases set created_by = null where created_by = p_user_id;
  update public.businessbook_announcements set created_by = null where created_by = p_user_id;

  -- Suppression du compte : tout le reste suit en cascade (profil, livreur, portefeuille, notifications, etc.)
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('deleted', true, 'name', v_u.full_name, 'phone', v_u.phone);
end $$;

-- ─────────────────────────────────────────────────────────────
-- 3. Droits : réservé aux utilisateurs connectés (contrôle de rôle dans chaque fonction)
-- ─────────────────────────────────────────────────────────────
revoke execute on function telima.touch_activity(text) from public, anon;
revoke execute on function telima.admin_activity(integer) from public, anon;
revoke execute on function telima.admin_delete_user_check(uuid) from public, anon;
revoke execute on function telima.admin_delete_user(uuid, boolean) from public, anon;
grant execute on function telima.touch_activity(text) to authenticated;
grant execute on function telima.admin_activity(integer) to authenticated;
grant execute on function telima.admin_delete_user_check(uuid) to authenticated;
grant execute on function telima.admin_delete_user(uuid, boolean) to authenticated;
