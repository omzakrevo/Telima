-- Migration appliquée sur le projet Supabase cloud : telima_08g_notify_triggers

create or replace function telima.fcfa_txt(p integer)
returns text language sql immutable as $$
  select case when p < 0 then '-' else '' end || replace(to_char(abs(p), 'FM999G999G999'), ',', ' ') || ' FCFA'
$$;

-- Mouvements de portefeuille : chaque crédit / débit est notifié à son titulaire
create or replace function telima.tg_wallet_tx_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_user uuid; v_title text; v_code text;
begin
  if new.type = 'withdrawal' then return null; end if;  -- notifié par la demande de retrait
  select user_id into v_user from telima.wallets where id = new.wallet_id;
  select code into v_code from telima.deliveries where id = new.delivery_id;
  v_title := case new.type::text
    when 'earning' then 'Gain crédité'
    when 'commission' then 'Commission prélevée'
    when 'withdrawal_refund' then 'Retrait remboursé'
    when 'topup' then 'Portefeuille rechargé'
    when 'payment' then 'Paiement par portefeuille'
    when 'refund' then 'Remboursement'
    when 'purchase' then case when new.amount > 0 then 'Achats remboursés' else 'Achats payés' end
    else 'Ajustement du solde' end;
  perform telima.notify_user(v_user, 'wallet', v_title,
    case when new.amount > 0 then '+' else '' end || telima.fcfa_txt(new.amount)
      || coalesce(' · ' || v_code, '') || ' · Solde : ' || telima.fcfa_txt(new.balance_after),
    jsonb_build_object('delivery_id', new.delivery_id));
  return null;
end $$;
create trigger trg_wallet_tx_notify after insert on telima.wallet_transactions
  for each row execute function telima.tg_wallet_tx_notify();

-- Paiements validés / refusés
create or replace function telima.tg_payment_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_code text;
begin
  if new.status is not distinct from old.status or new.payer_id is null then return null; end if;
  select code into v_code from telima.deliveries where id = new.delivery_id;
  if new.status = 'paid' and new.metadata->>'kind' is distinct from 'topup' and new.method <> 'wallet' then
    perform telima.notify_user(new.payer_id, 'payment', 'Paiement validé',
      telima.fcfa_txt(new.amount) || coalesce(' · ' || v_code, '') || case when new.method in ('orange_money', 'moov_money')
        then '. Votre commande est lancée.' else '' end,
      jsonb_build_object('payment_id', new.id, 'delivery_id', new.delivery_id));
  elsif new.status = 'failed' then
    perform telima.notify_user(new.payer_id, 'payment', 'Paiement refusé',
      telima.fcfa_txt(new.amount) || coalesce(' · ' || v_code, '') || ' — ' || coalesce(new.metadata->>'failure', 'paiement non reçu')
        || '. Réessayez ou choisissez un autre moyen de paiement.',
      jsonb_build_object('payment_id', new.id, 'delivery_id', new.delivery_id));
  end if;
  return null;
end $$;
create trigger trg_payment_notify after update of status on telima.payments
  for each row execute function telima.tg_payment_notify();

-- Retraits : accusé de réception au demandeur
create or replace function telima.tg_withdrawal_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  perform telima.notify_user(new.user_id, 'withdrawal', 'Demande de retrait enregistrée',
    telima.fcfa_txt(new.amount) || ' vers ' || new.phone || ' (' || replace(new.method::text, '_', ' ')
      || '). L''administrateur va effectuer le transfert.',
    jsonb_build_object('withdrawal_id', new.id));
  return null;
end $$;
create trigger trg_withdrawal_notify after insert on telima.withdrawals
  for each row execute function telima.tg_withdrawal_notify();

-- Nouvelle commande : client + personnel
create or replace function telima.tg_delivery_created_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if new.stop_order > 1 then return null; end if;
  if new.customer_id is not null then
    perform telima.notify_user(new.customer_id, 'delivery_created',
      case when new.kind = 'errand' then 'Course enregistrée' else 'Commande enregistrée' end,
      new.code || ' · ' || telima.fcfa_txt(new.total_price) || case when new.status = 'created'
        then ' · en attente du paiement' else ' · recherche d''un livreur' end,
      jsonb_build_object('delivery_id', new.id));
  end if;
  perform telima.notify_staff('new_order', case when new.kind = 'errand' then 'Nouvelle course à faire' else 'Nouvelle commande' end,
    new.code || ' · ' || coalesce(new.customer_name, '') || ' · ' || telima.fcfa_txt(new.total_price),
    jsonb_build_object('delivery_id', new.id));
  return null;
end $$;
create trigger trg_delivery_created_notify after insert on telima.deliveries
  for each row execute function telima.tg_delivery_created_notify();

-- Annulations et fins de course : personnel + livreur
create or replace function telima.tg_delivery_events_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if new.status is not distinct from old.status then return null; end if;
  if new.status = 'cancelled' then
    perform telima.notify_staff('delivery_cancelled', 'Commande annulée', new.code, jsonb_build_object('delivery_id', new.id));
  elsif new.status = 'completed' and new.driver_id is not null then
    perform telima.notify_user(new.driver_id, 'delivery_status', 'Course terminée', new.code || ' · bravo !',
                               jsonb_build_object('delivery_id', new.id));
  elsif new.status = 'assigned' and new.driver_id is not null then
    perform telima.notify_user(new.driver_id, 'delivery_status', 'Course acceptée',
      new.code || ' · ' || case when new.kind = 'errand' then 'achats à faire puis livraison : ' || new.dropoff_address
                                else new.pickup_address || ' → ' || new.dropoff_address end,
      jsonb_build_object('delivery_id', new.id));
  end if;
  return null;
end $$;
create trigger trg_delivery_events_notify after update of status on telima.deliveries
  for each row execute function telima.tg_delivery_events_notify();

-- Code de remise (communiqué au destinataire) : envoyé au client en notification
create or replace function telima.tg_delivery_otp_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_del telima.deliveries;
begin
  select * into v_del from telima.deliveries where id = new.delivery_id;
  if v_del.customer_id is not null then
    perform telima.notify_user(v_del.customer_id, 'otp', 'Code de remise · ' || v_del.code,
      'Code : ' || new.otp_code || ' — à donner au livreur à la réception'
        || case when v_del.kind = 'errand' then '.' else ' (communiquez-le au destinataire).' end,
      jsonb_build_object('delivery_id', v_del.id));
  end if;
  return null;
end $$;
create trigger trg_delivery_otp_notify after insert on telima.delivery_secrets
  for each row execute function telima.tg_delivery_otp_notify();
