-- Migration appliquée sur le projet Supabase cloud : telima_08m_declare_retry

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
  v_label := case when v_pay.metadata->>'kind' = 'topup' then 'Rechargement' else 'Commande ' || coalesce(v_code, '') end;
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
