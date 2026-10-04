-- Migration appliquée sur le projet Supabase cloud : telima_02b6_rating_earnings_business

create or replace function telima.get_delivery_otp(p_delivery_id uuid)
returns text language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id;
  if v_del.id is null or v_del.driver_id = v_uid
     or not (v_del.customer_id = v_uid or telima.is_staff()
             or (v_del.business_id is not null and exists (select 1 from telima.business_members m
                   where m.business_id = v_del.business_id and m.user_id = v_uid))) then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return (select otp_code from telima.delivery_secrets where delivery_id = p_delivery_id);
end $$;

create or replace function telima.rate_delivery(p_delivery_id uuid, p_stars int, p_comment text default null)
returns telima.ratings language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries; v_rating telima.ratings;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id;
  if v_del.id is null or v_del.customer_id is distinct from v_uid then
    raise exception 'Livraison introuvable' using errcode = 'P0002';
  end if;
  if v_del.status <> 'completed' or v_del.driver_id is null then
    raise exception 'Vous pourrez noter la livraison une fois terminée' using errcode = 'P0001';
  end if;
  if p_stars not between 1 and 5 then raise exception 'Note entre 1 et 5' using errcode = '22023'; end if;
  insert into telima.ratings(delivery_id, customer_id, driver_id, stars, comment)
  values (p_delivery_id, v_uid, v_del.driver_id, p_stars, nullif(trim(p_comment), ''))
  on conflict (delivery_id) do update set stars = excluded.stars, comment = excluded.comment
  returning * into v_rating;
  return v_rating;
end $$;

create or replace function telima.tg_ratings_refresh_driver()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_driver uuid := coalesce(new.driver_id, old.driver_id);
begin
  update telima.drivers d set
    rating_avg = coalesce((select round(avg(stars)::numeric, 2) from telima.ratings where driver_id = v_driver), 0),
    rating_count = (select count(*) from telima.ratings where driver_id = v_driver)
  where d.user_id = v_driver;
  return null;
end $$;
create trigger trg_ratings_refresh after insert or update on telima.ratings
  for each row execute function telima.tg_ratings_refresh_driver();

create or replace function telima.get_driver_earnings()
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_tz text := 'Africa/Ouagadougou';
  v_today timestamptz := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  v_week timestamptz := date_trunc('week', now() at time zone v_tz) at time zone v_tz;
  v_month timestamptz := date_trunc('month', now() at time zone v_tz) at time zone v_tz;
begin
  return (
    select jsonb_build_object(
      'today', coalesce(sum(driver_earning) filter (where completed_at >= v_today), 0),
      'week', coalesce(sum(driver_earning) filter (where completed_at >= v_week), 0),
      'month', coalesce(sum(driver_earning) filter (where completed_at >= v_month), 0),
      'count_today', count(*) filter (where completed_at >= v_today),
      'count_week', count(*) filter (where completed_at >= v_week),
      'count_month', count(*) filter (where completed_at >= v_month),
      'count_total', count(*),
      'commission_month', coalesce(sum(commission_amount) filter (where completed_at >= v_month), 0),
      'commission_total', coalesce(sum(commission_amount), 0),
      'earning_total', coalesce(sum(driver_earning), 0),
      'balance', coalesce((select balance from telima.wallets where user_id = v_uid), 0),
      'pending_withdrawals', coalesce((select sum(amount) from telima.withdrawals where user_id = v_uid and status = 'pending'), 0)
    )
    from telima.deliveries where driver_id = v_uid and status = 'completed'
  );
end $$;

create or replace function telima.request_withdrawal(p_amount integer, p_method telima.payment_method, p_phone text)
returns telima.withdrawals language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_active_user();
  v_min int := coalesce((telima.get_setting('withdrawal_min', '1000'))::text::int, 1000);
  v_wallet uuid := telima.ensure_wallet(v_uid);
  v_wd telima.withdrawals;
begin
  if not exists (select 1 from telima.drivers where user_id = v_uid and status = 'approved') then
    raise exception 'Retraits réservés aux livreurs approuvés' using errcode = '42501';
  end if;
  if p_amount < v_min then raise exception 'Montant minimum : % FCFA', v_min using errcode = '22023'; end if;
  if p_method not in ('orange_money', 'moov_money', 'cash') then
    raise exception 'Moyen de retrait invalide' using errcode = '22023';
  end if;
  insert into telima.withdrawals(wallet_id, user_id, amount, method, phone)
  values (v_wallet, v_uid, p_amount, p_method, telima.normalize_phone(p_phone)) returning * into v_wd;
  perform telima.wallet_apply(v_uid, 'withdrawal', -p_amount, null, v_wd.id, 'Demande de retrait ' || p_method::text);
  perform telima.notify_staff('withdrawal', 'Demande de retrait', p_amount || ' FCFA', jsonb_build_object('withdrawal_id', v_wd.id));
  return v_wd;
end $$;

create or replace function telima.create_business_account(p jsonb)
returns telima.business_accounts language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_b telima.business_accounts;
begin
  if coalesce(trim(p->>'name'), '') = '' then raise exception 'Nom obligatoire' using errcode = '22023'; end if;
  insert into telima.business_accounts(name, type, owner_id, phone, address, lat, lng, city_id)
  values (trim(p->>'name'), coalesce(nullif(p->>'type', ''), 'boutique')::telima.business_type, v_uid,
          case when coalesce(p->>'phone', '') <> '' then telima.normalize_phone(p->>'phone') end,
          nullif(p->>'address', ''), nullif(p->>'lat', '')::float8, nullif(p->>'lng', '')::float8,
          nullif(p->>'city_id', '')::uuid)
  returning * into v_b;
  insert into telima.business_members(business_id, user_id, role) values (v_b.id, v_uid, 'owner');
  return v_b;
end $$;

create or replace function telima.add_business_member(p_business_id uuid, p_phone text, p_role telima.member_role default 'member')
returns telima.business_members language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_user uuid; v_m telima.business_members;
begin
  if not exists (select 1 from telima.business_members where business_id = p_business_id and user_id = v_uid and role in ('owner', 'manager')) then
    raise exception 'Seul le propriétaire ou un gérant peut ajouter des membres' using errcode = '42501';
  end if;
  if p_role = 'owner' then raise exception 'Rôle invalide' using errcode = '22023'; end if;
  select id into v_user from telima.users where phone = telima.normalize_phone(p_phone) and is_active;
  if v_user is null then raise exception 'Aucun compte avec ce numéro' using errcode = 'P0002'; end if;
  insert into telima.business_members(business_id, user_id, role) values (p_business_id, v_user, p_role)
  on conflict (business_id, user_id) do update set role = excluded.role returning * into v_m;
  return v_m;
end $$;

create or replace function telima.get_business_summary(p_business_id uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if not exists (select 1 from telima.business_members where business_id = p_business_id and user_id = v_uid) and not telima.is_staff() then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  return (select jsonb_build_object(
            'count', count(*),
            'completed', count(*) filter (where status = 'completed'),
            'cancelled', count(*) filter (where status = 'cancelled'),
            'active', count(*) filter (where status not in ('completed', 'cancelled')),
            'spent', coalesce(sum(total_price) filter (where status = 'completed'), 0))
          from telima.deliveries
         where business_id = p_business_id and created_at >= p_from and created_at < p_to);
end $$;

create or replace function telima.request_password_reset(p_phone text)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare
  v_phone text := telima.normalize_phone(p_phone);
  v_user telima.users;
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_sim boolean := coalesce(telima.get_setting('sms_mode', '"simulation"') #>> '{}', 'simulation') = 'simulation';
begin
  select * into v_user from telima.users where phone = v_phone;
  if v_user.id is not null and v_user.is_active then
    if (select count(*) from telima.password_reset_requests
         where user_id = v_user.id and created_at > now() - interval '1 hour') >= 3 then
      raise exception 'Trop de demandes. Réessayez dans une heure.' using errcode = 'P0001';
    end if;
    insert into telima.password_reset_requests(user_id, phone, code_hash, code_plain, expires_at)
    values (v_user.id, v_phone, extensions.crypt(v_code, extensions.gen_salt('bf')), case when v_sim then v_code end, now() + interval '30 minutes');
    if v_sim then
      perform telima.notify_staff('password_reset', 'Demande de récupération de compte',
        v_user.full_name || ' (' || v_phone || ') — code : ' || v_code, jsonb_build_object('user_id', v_user.id));
    end if;
  end if;
  return jsonb_build_object('sent', true, 'simulation', v_sim);
end $$;

create or replace function telima.consume_password_reset(p_phone text, p_code text)
returns uuid language plpgsql security definer set search_path = telima, public as $$
declare v_req telima.password_reset_requests;
begin
  select * into v_req from telima.password_reset_requests
   where phone = telima.normalize_phone(p_phone) and used_at is null and expires_at > now()
   order by created_at desc limit 1 for update;
  if v_req.id is null then raise exception 'Code expiré ou invalide' using errcode = 'P0001'; end if;
  if v_req.attempts >= 5 then raise exception 'Trop d''essais' using errcode = 'P0001'; end if;
  if v_req.code_hash <> extensions.crypt(trim(p_code), v_req.code_hash) then
    update telima.password_reset_requests set attempts = attempts + 1 where id = v_req.id;
    return null;
  end if;
  update telima.password_reset_requests set used_at = now(), code_plain = null where id = v_req.id;
  return v_req.user_id;
end $$;
