-- Parcours complet exécuté avec les rôles réels (authenticated + RLS)
\set QUIET on
-- Comptes : client, livreur, admin, autre client
insert into auth.users(id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000c', '22670000001@telima.app', '{"phone":"70000001","full_name":"Awa Client","role":"client"}'),
 ('00000000-0000-0000-0000-00000000000d', '22670000002@telima.app', '{"phone":"70000002","full_name":"Issa Livreur","role":"driver"}'),
 ('00000000-0000-0000-0000-00000000000a', '22670000003@telima.app', '{"phone":"70000003","full_name":"Admin Telima"}'),
 ('00000000-0000-0000-0000-00000000000e', '22670000004@telima.app', '{"phone":"70000004","full_name":"Autre Client","role":"admin"}');
update telima.users set role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';
do $$ begin assert (select role from telima.users where phone='+22670000004') = 'client', 'admin auto-attribué !'; end $$;

create or replace function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p::text, false) $$;

-- ===== Livreur : candidature
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d'); set role authenticated;
select status from telima.submit_driver_application('{"id_document_number":"B1234567","vehicle_type":"moto","plate_number":"11 JK 2233","brand":"Haojue"}');
do $$ begin
  begin perform telima.set_driver_online(true, 12.37, -1.52); raise exception 'aurait dû échouer';
  exception when insufficient_privilege then null; end;
end $$;
-- un livreur ne peut pas modifier son rôle
do $$ begin
  begin update telima.users set role='admin' where id=auth.uid(); raise exception 'garde rôle inopérante';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- ===== Admin : approbation
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a'); set role authenticated;
select status from telima.admin_set_driver_status('00000000-0000-0000-0000-00000000000d', 'approved', null);
reset role;

-- ===== Livreur en ligne
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d'); set role authenticated;
select is_online from telima.set_driver_online(true, 12.3700, -1.5200);
reset role;

-- ===== Client : devis puis commande
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c'); set role authenticated;
select (telima.quote_delivery(12.3686, -1.5275, 12.3260, -1.4950))->>'total_price' as devis;
create temp table t_del as select * from telima.create_delivery('{
  "pickup":{"address":"Marché Rood Woko","lat":12.3686,"lng":-1.5275,"contact_name":"Awa","contact_phone":"70000001","instructions":"Boutique à côté du marché"},
  "dropoff":{"address":"Ouaga 2000, derrière la station","lat":12.3260,"lng":-1.4950,"contact_name":"Moussa","contact_phone":"76000000","instructions":"Appelez-moi en arrivant"},
  "package":{"category":"petit_colis","description":"Chaussures","quantity":1,"fragile":true,"size":"petit"},
  "payment_method":"cash"}');
select code, status, distance_km, total_price, commission_amount, driver_earning from t_del;
do $$ begin assert (select status from t_del) = 'searching'; assert (select code from t_del) like 'LIV-%-000001'; end $$;
-- le client ne peut pas lire le secret
do $$ begin
  begin perform * from telima.delivery_secrets; raise exception 'secret lisible';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
grant select on t_del to authenticated;

-- ===== Autre client : ne voit pas la commande
select pg_temp.as_user('00000000-0000-0000-0000-00000000000e'); set role authenticated;
do $$ begin assert (select count(*) from telima.deliveries) = 0, 'fuite RLS'; end $$;
reset role;

-- ===== Livreur : demandes disponibles + acceptation + étapes
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d'); set role authenticated;
do $$ begin assert (select count(*) from telima.get_available_requests()) = 1, 'demande non visible'; end $$;
select (telima.accept_delivery((select id from t_del))).status;
do $$ begin
  begin perform telima.get_delivery_otp((select id from t_del)); raise exception 'OTP visible par livreur';
  exception when insufficient_privilege then null; end;
end $$;
select (telima.driver_advance_status((select id from t_del), 'to_pickup', 12.37, -1.52)).status;
select telima.driver_update_location(12.3687, -1.5274);
select (telima.driver_advance_status((select id from t_del), 'at_pickup')).status;
select (telima.driver_advance_status((select id from t_del), 'picked_up')).status;
select (telima.driver_advance_status((select id from t_del), 'in_transit')).status;
select (telima.driver_advance_status((select id from t_del), 'at_dropoff')).status;
-- mauvais code
select (telima.complete_delivery((select id from t_del), 'abcd')).id is null as code_refuse;
reset role;
-- le client lit le code et le transmet au destinataire
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c'); set role authenticated;
create temp table t_otp as select telima.get_delivery_otp((select id from t_del)) as otp;
reset role; grant select on t_otp to authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d'); set role authenticated;
select (telima.complete_delivery((select id from t_del), (select otp from t_otp), 'Moussa')).status as final_status;
select telima.get_driver_earnings();
reset role;

-- ===== Vérifications
do $$
declare d telima.deliveries;
begin
  select * into d from telima.deliveries where id = (select id from t_del);
  assert d.status = 'completed'; assert d.payment_status = 'paid';
  assert (select balance from telima.wallets where user_id = d.driver_id) = -d.commission_amount, 'commission non débitée';
  assert (select count(*) from telima.delivery_status_history where delivery_id = d.id) = 10, 'historique incomplet';
  assert (select count(*) from telima.notifications where user_id = d.customer_id) >= 8, 'notifications manquantes';
  assert exists (select 1 from telima.notifications where user_id = d.customer_id and body like '%quelques minutes%');
end $$;

-- ===== Évaluation
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c'); set role authenticated;
select stars from telima.rate_delivery((select id from t_del), 5, 'Rapide et poli');
reset role;
do $$ begin assert (select rating_avg from telima.drivers where user_id='00000000-0000-0000-0000-00000000000d') = 5; end $$;

-- ===== Paiement portefeuille + annulation + remboursement
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c'); set role authenticated;
create temp table t_pay as select * from telima.request_wallet_topup(5000, 'orange_money');
reset role; grant select on t_pay to authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c'); set role authenticated;
select status from telima.confirm_simulated_payment((select id from t_pay));
create temp table t_del2 as select * from telima.create_delivery('{
  "pickup":{"address":"A","lat":12.3686,"lng":-1.5275},
  "dropoff":{"address":"B","lat":12.3500,"lng":-1.5100,"contact_name":"X","contact_phone":"76000000"},
  "package":{"category":"document"}, "payment_method":"wallet"}');
select status from telima.cancel_delivery((select id from t_del2), 'Erreur');
reset role;
do $$ begin assert (select balance from telima.wallets where user_id='00000000-0000-0000-0000-00000000000c') = 5000, 'remboursement'; end $$;

-- ===== Mobile Money : statut « Nouvelle demande » jusqu'au paiement
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c'); set role authenticated;
create temp table t_del3 as select * from telima.create_delivery('{
  "pickup":{"address":"A","lat":12.3686,"lng":-1.5275},
  "dropoff":{"address":"B","lat":12.3500,"lng":-1.5100,"contact_name":"X","contact_phone":"76000000"},
  "package":{"category":"nourriture"}, "payment_method":"moov_money"}');
do $$ begin assert (select status from t_del3) = 'created'; end $$;
select status from telima.confirm_simulated_payment((select id from telima.payments where delivery_id = (select id from t_del3)));
do $$ begin assert (select status from telima.deliveries where id = (select id from t_del3)) = 'searching'; end $$;
reset role;

-- ===== Multi-destinations
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c'); set role authenticated;
select code, stop_order, status, total_price from telima.create_delivery_batch('{
  "pickup":{"address":"Boutique A","lat":12.3686,"lng":-1.5275},
  "payment_method":"cash",
  "stops":[
    {"dropoff":{"address":"Client 1","lat":12.3600,"lng":-1.5200,"contact_name":"C1","contact_phone":"76000001"},"package":{"category":"petit_colis"}},
    {"dropoff":{"address":"Client 2","lat":12.3550,"lng":-1.5100,"contact_name":"C2","contact_phone":"76000002"},"package":{"category":"petit_colis"}},
    {"dropoff":{"address":"Client 3","lat":12.3500,"lng":-1.5000,"contact_name":"C3","contact_phone":"76000003"},"package":{"category":"petit_colis"}}]}');
reset role;

-- ===== Admin : commande téléphonique, attribution manuelle, stats, retrait
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a'); set role authenticated;
select code, status, total_price from telima.admin_create_delivery('{
  "customer_phone":"65112233","customer_name":"Mme Ouédraogo",
  "pickup":{"address":"Pharmacie du Progrès","lat":12.3690,"lng":-1.5250},
  "dropoff":{"address":"Gounghin","lat":12.3640,"lng":-1.5500,"contact_name":"Mme Ouédraogo","contact_phone":"65112233"},
  "package":{"category":"autre"}, "payment_method":"cash_on_delivery", "price_override":1000}');
select count(*) as livreurs_attribuables from telima.admin_list_assignable_drivers((select id from t_del3));
select (telima.admin_assign_delivery((select id from t_del3), '00000000-0000-0000-0000-00000000000d')).status;
select telima.admin_dashboard_stats(now() - interval '1 day', now() + interval '1 day');
select * from telima.admin_daily_stats(3);
select telima.admin_wallet_adjust('00000000-0000-0000-0000-00000000000d', 5000, 'Bonus test');
select count(*) as logs from telima.admin_logs;
reset role;

select pg_temp.as_user('00000000-0000-0000-0000-00000000000d'); set role authenticated;
select status from telima.request_withdrawal(1000, 'orange_money', '70000002');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a'); set role authenticated;
select status from telima.admin_process_withdrawal((select id from telima.withdrawals limit 1), true, 'OM-123', null);
reset role;

-- ===== Visiteur (anon) : devis OK, pas d'accès aux livraisons
select set_config('request.jwt.claim.sub', '', false); set role anon;
select (telima.quote_delivery(12.3686, -1.5275, 12.3260, -1.4950, 'voiture', 'grand', false, null, 'gros_colis', 6.2))->>'total_price' as devis_voiture;
do $$ begin
  begin perform * from telima.deliveries; raise exception 'anon lit les livraisons';
  exception when insufficient_privilege then null; end;
end $$;
select telima.request_password_reset('70000001');
reset role;
\echo '=== PARCOURS OK ==='
