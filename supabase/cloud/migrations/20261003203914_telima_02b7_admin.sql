-- Migration appliquée sur le projet Supabase cloud : telima_02b7_admin

create or replace function telima.admin_assign_delivery(p_delivery_id uuid, p_driver_id uuid)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_staff();
  v_del telima.deliveries;
  v_vehicle telima.vehicles;
  v_old uuid;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null then raise exception 'Livraison introuvable' using errcode = 'P0002'; end if;
  if v_del.status not in ('created', 'searching', 'assigned', 'to_pickup', 'at_pickup') then
    raise exception 'Attribution impossible à l''étape %', v_del.status using errcode = 'P0001';
  end if;
  if not exists (select 1 from telima.drivers where user_id = p_driver_id and status = 'approved') then
    raise exception 'Livreur non approuvé' using errcode = 'P0001';
  end if;
  select * into v_vehicle from telima.vehicles where driver_id = p_driver_id and is_active;
  if v_vehicle.id is null then raise exception 'Ce livreur n''a pas de véhicule actif' using errcode = 'P0001'; end if;
  v_old := v_del.driver_id;

  update telima.deliveries set driver_id = p_driver_id, vehicle_id = v_vehicle.id, status = 'assigned',
         assigned_at = now(), near_notified = false, searching_at = coalesce(searching_at, now())
   where (id = p_delivery_id or (v_del.batch_id is not null and batch_id = v_del.batch_id
                                  and status in ('created', 'searching', 'assigned', 'to_pickup', 'at_pickup')));
  select * into v_del from telima.deliveries where id = p_delivery_id;
  if v_del.batch_id is not null then
    update telima.delivery_batches set driver_id = p_driver_id where id = v_del.batch_id;
  end if;

  perform telima.notify_user(p_driver_id, 'assigned_by_admin', 'Nouvelle course attribuée',
                             v_del.code || ' : ' || v_del.pickup_address || ' → ' || v_del.dropoff_address,
                             jsonb_build_object('delivery_id', v_del.id));
  if v_old is not null and v_old <> p_driver_id then
    perform telima.notify_user(v_old, 'unassigned', 'Course réattribuée', v_del.code || ' a été confiée à un autre livreur.',
                               jsonb_build_object('delivery_id', v_del.id));
  end if;
  perform telima.log_admin_action('assign_delivery', 'deliveries', v_del.id::text,
                                  jsonb_build_object('code', v_del.code, 'driver_id', p_driver_id, 'previous_driver_id', v_old));
  return v_del;
end $$;

create or replace function telima.admin_create_delivery(p jsonb)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare
  v_uid uuid := telima.require_staff();
  v_phone text := telima.normalize_phone(p->>'customer_phone');
  v_name text := coalesce(nullif(trim(p->>'customer_name'), ''), 'Client');
  v_customer uuid;
  v_row telima.deliveries;
begin
  select id into v_customer from telima.users where phone = v_phone and is_active;
  if (p->>'payment_method') = 'wallet' and v_customer is null then
    raise exception 'Ce client n''a pas de portefeuille' using errcode = 'P0001';
  end if;
  v_row := telima._insert_delivery(p, v_customer, v_name, v_phone, v_uid, 'admin', null, 1, false, null, null,
                                   nullif(p->>'price_override', '')::int);
  if v_row.status = 'created' then
    update telima.deliveries set status = 'searching', searching_at = now() where id = v_row.id returning * into v_row;
  end if;
  perform telima.log_admin_action('create_delivery', 'deliveries', v_row.id::text,
                                  jsonb_build_object('code', v_row.code, 'customer_phone', v_phone));
  if nullif(p->>'driver_id', '') is not null then
    v_row := telima.admin_assign_delivery(v_row.id, (p->>'driver_id')::uuid);
  else
    perform telima.notify_nearby_drivers(v_row);
  end if;
  return v_row;
end $$;

create or replace function telima.admin_set_driver_status(p_driver_id uuid, p_status telima.driver_status, p_note text default null)
returns telima.drivers language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff(); v_drv telima.drivers;
begin
  update telima.drivers set status = p_status, status_note = p_note,
         is_online = case when p_status = 'approved' then is_online else false end,
         approved_at = case when p_status = 'approved' then now() else approved_at end,
         approved_by = case when p_status = 'approved' then v_uid else approved_by end
   where user_id = p_driver_id returning * into v_drv;
  if v_drv.user_id is null then raise exception 'Livreur introuvable' using errcode = 'P0002'; end if;
  update telima.users set role = 'driver' where id = p_driver_id and role = 'client';
  perform telima.notify_user(p_driver_id, 'driver_status',
    case p_status when 'approved' then 'Compte livreur approuvé'
                  when 'suspended' then 'Compte livreur suspendu'
                  when 'rejected' then 'Inscription livreur refusée'
                  else 'Compte livreur en attente' end,
    coalesce(p_note, case p_status when 'approved' then 'Vous pouvez passer EN LIGNE et recevoir des courses.' else '' end));
  perform telima.log_admin_action('set_driver_status', 'drivers', p_driver_id::text,
                                  jsonb_build_object('status', p_status, 'note', p_note));
  return v_drv;
end $$;

create or replace function telima.admin_set_user_active(p_user_id uuid, p_active boolean)
returns telima.users language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_u telima.users;
begin
  if p_user_id = v_uid then raise exception 'Vous ne pouvez pas désactiver votre propre compte' using errcode = 'P0001'; end if;
  update telima.users set is_active = p_active, deactivated_at = case when p_active then null else now() end
   where id = p_user_id returning * into v_u;
  if not p_active then update telima.drivers set is_online = false where user_id = p_user_id; end if;
  perform telima.log_admin_action(case when p_active then 'activate_user' else 'deactivate_user' end, 'users', p_user_id::text);
  return v_u;
end $$;

create or replace function telima.admin_set_user_role(p_user_id uuid, p_role telima.user_role)
returns telima.users language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_u telima.users;
begin
  if p_user_id = v_uid and p_role <> 'admin' then
    raise exception 'Vous ne pouvez pas retirer votre propre rôle administrateur' using errcode = 'P0001';
  end if;
  update telima.users set role = p_role where id = p_user_id returning * into v_u;
  if p_role = 'driver' then insert into telima.drivers(user_id, city_id) values (p_user_id, v_u.city_id) on conflict do nothing; end if;
  perform telima.log_admin_action('set_user_role', 'users', p_user_id::text, jsonb_build_object('role', p_role));
  return v_u;
end $$;

create or replace function telima.admin_process_withdrawal(p_withdrawal_id uuid, p_approve boolean,
                                                           p_provider_ref text default null, p_note text default null)
returns telima.withdrawals language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_wd telima.withdrawals;
begin
  select * into v_wd from telima.withdrawals where id = p_withdrawal_id for update;
  if v_wd.id is null then raise exception 'Retrait introuvable' using errcode = 'P0002'; end if;
  if v_wd.status <> 'pending' then raise exception 'Retrait déjà traité' using errcode = 'P0001'; end if;
  update telima.withdrawals set status = case when p_approve then 'paid' else 'rejected' end::telima.withdrawal_status,
         provider_ref = p_provider_ref, note = p_note, processed_by = v_uid, processed_at = now()
   where id = p_withdrawal_id returning * into v_wd;
  if not p_approve then
    perform telima.wallet_apply(v_wd.user_id, 'withdrawal_refund', v_wd.amount, null, v_wd.id, 'Retrait refusé : ' || coalesce(p_note, ''));
  end if;
  perform telima.notify_user(v_wd.user_id, 'withdrawal',
    case when p_approve then 'Retrait effectué' else 'Retrait refusé' end,
    v_wd.amount || ' FCFA' || coalesce(' — ' || p_note, ''), jsonb_build_object('withdrawal_id', v_wd.id));
  perform telima.log_admin_action(case when p_approve then 'withdrawal_paid' else 'withdrawal_rejected' end,
                                  'withdrawals', v_wd.id::text, jsonb_build_object('amount', v_wd.amount, 'ref', p_provider_ref));
  return v_wd;
end $$;

create or replace function telima.admin_wallet_adjust(p_user_id uuid, p_amount integer, p_description text)
returns integer language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_balance int;
begin
  if coalesce(trim(p_description), '') = '' then raise exception 'Motif obligatoire' using errcode = '22023'; end if;
  v_balance := telima.wallet_apply(p_user_id, case when p_amount > 0 then 'topup' else 'adjustment' end::telima.wallet_tx_type,
                                   p_amount, null, null, 'Ajustement admin : ' || p_description, true);
  perform telima.log_admin_action('wallet_adjust', 'wallets', p_user_id::text,
                                  jsonb_build_object('amount', p_amount, 'description', p_description));
  return v_balance;
end $$;

create or replace function telima.admin_confirm_payment(p_payment_id uuid, p_provider_ref text)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_pay telima.payments;
begin
  v_pay := telima._confirm_payment(p_payment_id, p_provider_ref);
  perform telima.log_admin_action('confirm_payment', 'payments', p_payment_id::text, jsonb_build_object('ref', p_provider_ref));
  return v_pay;
end $$;

create or replace function telima.admin_dashboard_stats(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff();
begin
  return jsonb_build_object(
    'clients', (select count(*) from telima.users where role = 'client' and is_active),
    'drivers', (select count(*) from telima.drivers d join telima.users u on u.id = d.user_id where u.is_active and d.status = 'approved'),
    'drivers_pending', (select count(*) from telima.drivers where status = 'pending'),
    'drivers_online', (select count(*) from telima.drivers where is_online and status = 'approved'),
    'orders', (select count(*) from telima.deliveries where created_at >= p_from and created_at < p_to),
    'orders_active', (select count(*) from telima.deliveries where status not in ('completed', 'cancelled')),
    'orders_searching', (select count(*) from telima.deliveries where status in ('created', 'searching')),
    'completed', (select count(*) from telima.deliveries where status = 'completed' and completed_at >= p_from and completed_at < p_to),
    'cancelled', (select count(*) from telima.deliveries where status = 'cancelled' and cancelled_at >= p_from and cancelled_at < p_to),
    'revenue', (select coalesce(sum(total_price), 0) from telima.deliveries where status = 'completed' and completed_at >= p_from and completed_at < p_to),
    'commissions', (select coalesce(sum(commission_amount), 0) from telima.deliveries where status = 'completed' and completed_at >= p_from and completed_at < p_to),
    'payments', (select coalesce(sum(amount), 0) from telima.payments where status = 'paid' and paid_at >= p_from and paid_at < p_to),
    'payments_by_method', (select coalesce(jsonb_object_agg(method, total), '{}'::jsonb) from (
        select method::text, sum(amount) total from telima.payments where status = 'paid' and paid_at >= p_from and paid_at < p_to group by method) s),
    'withdrawals_paid', (select coalesce(sum(amount), 0) from telima.withdrawals where status = 'paid' and processed_at >= p_from and processed_at < p_to),
    'withdrawals_pending', (select coalesce(sum(amount), 0) from telima.withdrawals where status = 'pending'),
    'withdrawals_pending_count', (select count(*) from telima.withdrawals where status = 'pending'),
    'support_open', (select count(*) from telima.support_requests where status <> 'closed')
  );
end $$;

create or replace function telima.admin_daily_stats(p_days int default 14)
returns table(day date, orders bigint, completed bigint, cancelled bigint, revenue bigint, commissions bigint)
language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff();
begin
  return query
  with days as (
    select generate_series((now() at time zone 'Africa/Ouagadougou')::date - (greatest(p_days, 1) - 1),
                           (now() at time zone 'Africa/Ouagadougou')::date, interval '1 day')::date as day
  )
  select d.day,
         (select count(*) from telima.deliveries x where (x.created_at at time zone 'Africa/Ouagadougou')::date = d.day),
         (select count(*) from telima.deliveries x where x.status = 'completed' and (x.completed_at at time zone 'Africa/Ouagadougou')::date = d.day),
         (select count(*) from telima.deliveries x where x.status = 'cancelled' and (x.cancelled_at at time zone 'Africa/Ouagadougou')::date = d.day),
         (select coalesce(sum(x.total_price), 0)::bigint from telima.deliveries x where x.status = 'completed' and (x.completed_at at time zone 'Africa/Ouagadougou')::date = d.day),
         (select coalesce(sum(x.commission_amount), 0)::bigint from telima.deliveries x where x.status = 'completed' and (x.completed_at at time zone 'Africa/Ouagadougou')::date = d.day)
    from days d order by d.day;
end $$;

create or replace function telima.admin_list_assignable_drivers(p_delivery_id uuid)
returns table(driver_id uuid, full_name text, phone text, is_online boolean, vehicle_type telima.vehicle_type,
              plate_number text, rating_avg numeric, distance_km numeric, busy boolean)
language plpgsql stable security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_staff(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id;
  return query
    select d.user_id, u.full_name, u.phone, d.is_online, v.type, v.plate_number, d.rating_avg,
           case when d.current_lat is null then null
                else round(telima.haversine_km(d.current_lat, d.current_lng, v_del.pickup_lat, v_del.pickup_lng)::numeric, 2) end,
           exists (select 1 from telima.deliveries x where x.driver_id = d.user_id and x.id <> p_delivery_id
                     and x.status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff')
                     and (v_del.batch_id is null or x.batch_id is distinct from v_del.batch_id))
      from telima.drivers d
      join telima.users u on u.id = d.user_id and u.is_active
      join telima.vehicles v on v.driver_id = d.user_id and v.is_active
     where d.status = 'approved'
     order by d.is_online desc, 8 asc nulls last, u.full_name;
end $$;
