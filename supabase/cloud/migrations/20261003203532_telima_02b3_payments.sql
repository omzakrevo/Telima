-- Migration appliquée sur le projet Supabase cloud : telima_02b3_payments

create or replace function telima._confirm_payment(p_payment_id uuid, p_provider_ref text)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_pay telima.payments; v_del telima.deliveries;
begin
  select * into v_pay from telima.payments where id = p_payment_id for update;
  if v_pay.id is null then raise exception 'Paiement introuvable' using errcode = 'P0002'; end if;
  if v_pay.status = 'paid' then return v_pay; end if;
  if v_pay.status <> 'pending' then raise exception 'Paiement non confirmable' using errcode = 'P0001'; end if;

  update telima.payments set status = 'paid', paid_at = now(), provider_ref = p_provider_ref
   where id = p_payment_id returning * into v_pay;

  if v_pay.metadata->>'kind' = 'topup' then
    perform telima.wallet_apply(v_pay.payer_id, 'topup', v_pay.amount, null, null,
                                'Rechargement ' || v_pay.method::text);
  elsif v_pay.delivery_id is not null then
    update telima.deliveries set payment_status = 'paid' where id = v_pay.delivery_id returning * into v_del;
    if v_del.status = 'created' and v_del.stop_order = 1 then
      update telima.deliveries set status = 'searching', searching_at = now()
       where id = v_del.id returning * into v_del;
      perform telima.notify_nearby_drivers(v_del);
    end if;
  end if;
  return v_pay;
end $$;

create or replace function telima.confirm_simulated_payment(p_payment_id uuid)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_pay telima.payments;
begin
  if telima.get_setting('payment_mode', '"simulation"') #>> '{}' <> 'simulation' then
    raise exception 'Le mode simulation est désactivé' using errcode = '42501';
  end if;
  select * into v_pay from telima.payments where id = p_payment_id;
  if v_pay.payer_id is distinct from v_uid and not telima.is_staff() then
    raise exception 'Paiement introuvable' using errcode = 'P0002';
  end if;
  return telima._confirm_payment(p_payment_id, 'SIM-' || upper(substr(md5(random()::text), 1, 10)));
end $$;

create or replace function telima.mark_payment_failed(p_payment_id uuid, p_reason text default null)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_pay telima.payments;
begin
  select * into v_pay from telima.payments where id = p_payment_id for update;
  if v_pay.id is null or (v_pay.payer_id is distinct from v_uid and not telima.is_staff()) then
    raise exception 'Paiement introuvable' using errcode = 'P0002';
  end if;
  if v_pay.status <> 'pending' then return v_pay; end if;
  update telima.payments set status = 'failed', metadata = metadata || jsonb_build_object('failure', p_reason)
   where id = p_payment_id returning * into v_pay;
  if v_pay.delivery_id is not null then
    update telima.deliveries set payment_status = 'failed' where id = v_pay.delivery_id;
  end if;
  return v_pay;
end $$;

create or replace function telima.change_payment_method(p_delivery_id uuid, p_method telima.payment_method)
returns telima.deliveries language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = p_delivery_id for update;
  if v_del.id is null or (v_del.customer_id is distinct from v_uid and not telima.is_staff()) then
    raise exception 'Livraison introuvable' using errcode = 'P0002';
  end if;
  if v_del.payment_status = 'paid' or v_del.status not in ('created', 'searching') then
    raise exception 'Le moyen de paiement ne peut plus être modifié' using errcode = 'P0001';
  end if;
  if p_method in ('orange_money', 'moov_money', 'wallet') and v_del.batch_id is not null then
    raise exception 'Non disponible pour un lot' using errcode = 'P0001';
  end if;
  update telima.payments set status = 'cancelled' where delivery_id = p_delivery_id and status in ('pending', 'failed');
  if p_method = 'wallet' then
    perform telima.wallet_apply(v_del.customer_id, 'payment', -v_del.total_price, v_del.id, null, 'Paiement livraison ' || v_del.code);
  end if;
  insert into telima.payments(delivery_id, payer_id, amount, method, provider, status, paid_at, metadata)
  values (v_del.id, v_del.customer_id, v_del.total_price, p_method,
          case when p_method in ('orange_money', 'moov_money') then p_method::text when p_method = 'wallet' then 'internal' else 'cash' end,
          case when p_method = 'wallet' then 'paid' else 'pending' end::telima.payment_status,
          case when p_method = 'wallet' then now() end, jsonb_build_object('kind', 'delivery'));
  update telima.deliveries
     set payment_method = p_method,
         payment_status = case when p_method = 'wallet' then 'paid' else 'pending' end::telima.payment_status,
         status = case when p_method in ('orange_money', 'moov_money') then 'created'
                       when status = 'created' and stop_order = 1 then 'searching' else status end,
         searching_at = coalesce(searching_at, case when p_method not in ('orange_money', 'moov_money') then now() end)
   where id = p_delivery_id returning * into v_del;
  if v_del.status = 'searching' then perform telima.notify_nearby_drivers(v_del); end if;
  return v_del;
end $$;

create or replace function telima.request_wallet_topup(p_amount integer, p_method telima.payment_method)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_pay telima.payments;
begin
  if p_amount < 100 or p_amount > 1000000 then
    raise exception 'Montant invalide (100 à 1 000 000 FCFA)' using errcode = '22023';
  end if;
  if p_method not in ('orange_money', 'moov_money') then
    raise exception 'Rechargement possible via Orange Money ou Moov Money' using errcode = '22023';
  end if;
  insert into telima.payments(payer_id, amount, method, provider, status, metadata)
  values (v_uid, p_amount, p_method, p_method::text, 'pending', jsonb_build_object('kind', 'topup'))
  returning * into v_pay;
  return v_pay;
end $$;
