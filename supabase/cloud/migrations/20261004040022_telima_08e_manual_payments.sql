-- Migration appliquée sur le projet Supabase cloud : telima_08e_manual_payments

-- Rapproche un paiement déclaré et un SMS Mobile Money reçu (même montant + même numéro ou même référence)
create or replace function telima._match_payment_sms(p_payment_id uuid default null, p_sms_id bigint default null)
returns bigint language plpgsql security definer set search_path = telima, public as $$
declare v_pay telima.payments; v_sms telima.mm_sms;
begin
  if p_payment_id is not null then
    select * into v_pay from telima.payments where id = p_payment_id;
    select s.* into v_sms from telima.mm_sms s
     where s.payment_id is null and s.direction <> 'out' and s.amount = v_pay.amount
       and s.received_at > v_pay.created_at - interval '1 day'
       and ((s.counterpart_phone is not null and s.counterpart_phone = v_pay.metadata->>'payer_phone')
            or (s.txn_ref is not null and upper(s.txn_ref) = upper(coalesce(v_pay.metadata->>'txn_ref', ''))))
     order by s.received_at desc limit 1;
  else
    select * into v_sms from telima.mm_sms where id = p_sms_id;
    select p.* into v_pay from telima.payments p
     where p.status = 'pending' and p.metadata ? 'declared_at' and not (p.metadata ? 'sms_id')
       and p.amount = v_sms.amount and p.created_at > v_sms.received_at - interval '3 days'
       and ((v_sms.counterpart_phone is not null and p.metadata->>'payer_phone' = v_sms.counterpart_phone)
            or (v_sms.txn_ref is not null and upper(coalesce(p.metadata->>'txn_ref', '')) = upper(v_sms.txn_ref)))
     order by p.created_at desc limit 1;
  end if;
  if v_pay.id is null or v_sms.id is null then return null; end if;
  update telima.mm_sms set payment_id = v_pay.id where id = v_sms.id;
  update telima.payments set metadata = metadata || jsonb_build_object('sms_id', v_sms.id, 'sms_ref', v_sms.txn_ref)
   where id = v_pay.id;
  perform telima.notify_staff('payment_sms_match', 'Paiement confirmé par SMS — à valider',
    v_pay.amount || ' FCFA de ' || coalesce(v_pay.metadata->>'payer_phone', '?') || coalesce(' · réf. ' || v_sms.txn_ref, ''),
    jsonb_build_object('payment_id', v_pay.id));
  return v_sms.id;
end $$;

-- Le client signale « J'ai fait le paiement » (mode manuel)
create or replace function telima.declare_manual_payment(p_payment_id uuid, p_payer_phone text, p_txn_ref text default null)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user(); v_pay telima.payments; v_label text; v_code text;
begin
  select * into v_pay from telima.payments where id = p_payment_id for update;
  if v_pay.id is null or v_pay.payer_id is distinct from v_uid then
    raise exception 'Paiement introuvable' using errcode = 'P0002';
  end if;
  if v_pay.status <> 'pending' then raise exception 'Ce paiement est déjà traité' using errcode = 'P0001'; end if;
  if v_pay.method not in ('orange_money', 'moov_money') then
    raise exception 'Paiement Mobile Money uniquement' using errcode = '22023';
  end if;
  update telima.payments
     set provider = 'manual',
         metadata = metadata || jsonb_build_object(
           'manual', true, 'payer_phone', telima.normalize_phone(p_payer_phone),
           'txn_ref', nullif(upper(trim(coalesce(p_txn_ref, ''))), ''), 'declared_at', now())
   where id = p_payment_id returning * into v_pay;

  select code into v_code from telima.deliveries where id = v_pay.delivery_id;
  v_label := case when v_pay.metadata->>'kind' = 'topup' then 'Rechargement' else 'Livraison ' || coalesce(v_code, '') end;
  perform telima.notify_staff('payment_declared', 'Paiement ' || replace(initcap(replace(v_pay.method::text, '_', ' ')), 'Money', 'Money') || ' à vérifier',
    v_pay.amount || ' FCFA de ' || (v_pay.metadata->>'payer_phone') || ' · ' || v_label
      || coalesce(' · réf. ' || (v_pay.metadata->>'txn_ref'), ''),
    jsonb_build_object('payment_id', v_pay.id));
  perform telima.notify_user(v_uid, 'payment', 'Paiement en cours de vérification',
    v_pay.amount || ' FCFA · ' || v_label || '. Vous serez averti dès sa validation.',
    jsonb_build_object('payment_id', v_pay.id, 'delivery_id', v_pay.delivery_id));
  perform telima._match_payment_sms(v_pay.id, null);
  select * into v_pay from telima.payments where id = p_payment_id;
  return v_pay;
end $$;

-- L'administrateur refuse un paiement déclaré (argent non reçu)
create or replace function telima.admin_reject_payment(p_payment_id uuid, p_reason text)
returns telima.payments language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_pay telima.payments;
begin
  select * into v_pay from telima.payments where id = p_payment_id for update;
  if v_pay.id is null then raise exception 'Paiement introuvable' using errcode = 'P0002'; end if;
  if v_pay.status <> 'pending' then raise exception 'Paiement déjà traité' using errcode = 'P0001'; end if;
  update telima.payments set status = 'failed',
         metadata = metadata || jsonb_build_object('failure', coalesce(nullif(trim(p_reason), ''), 'Paiement non reçu'), 'rejected_by', v_uid)
   where id = p_payment_id returning * into v_pay;
  if v_pay.delivery_id is not null then
    update telima.deliveries set payment_status = 'failed' where id = v_pay.delivery_id;
  end if;
  update telima.mm_sms set payment_id = null where payment_id = p_payment_id;
  perform telima.log_admin_action('reject_payment', 'payments', p_payment_id::text, jsonb_build_object('reason', p_reason));
  return v_pay;
end $$;

-- Compteurs « à traiter » du tableau de bord
create or replace function telima.admin_pending_counts()
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
begin
  perform telima.require_staff();
  return jsonb_build_object(
    'payments_to_verify', (select count(*) from telima.payments where status = 'pending' and metadata ? 'declared_at'),
    'withdrawals_pending', (select count(*) from telima.withdrawals where status = 'pending'),
    'sms_unmatched', (select count(*) from telima.mm_sms where payment_id is null and direction <> 'out'
                        and received_at > now() - interval '3 days'));
end $$;
