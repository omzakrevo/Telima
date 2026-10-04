-- =====================================================================
-- TELIMA — Migration 4 : configuration initiale (modifiable depuis le dashboard)
-- =====================================================================

insert into telima.app_settings(key, value, description, is_public) values
  ('app_name',               '"Telima"', 'Nom de l''application', true),
  ('commission',             '{"type":"percent","value":15}', 'Commission plateforme : percent (en %) ou fixed (en FCFA)', true),
  ('road_factor',            '1.3', 'Coefficient route / vol d''oiseau si la distance routière est indisponible', true),
  ('price_rounding',         '50', 'Arrondi supérieur des prix (FCFA)', true),
  ('dispatch_radius_km',     '7', 'Rayon de recherche des livreurs autour du point de récupération (km)', true),
  ('avg_speed_kmh',          '25', 'Vitesse moyenne pour l''estimation des temps (km/h)', true),
  ('location_min_interval_s','10', 'Intervalle minimal entre deux positions GPS enregistrées (s)', true),
  ('near_pickup_km',         '0.5', 'Distance déclenchant « Votre livreur arrive dans quelques minutes » (km)', true),
  ('proof_mode',             '"otp"', 'Preuve de livraison : otp (code obligatoire) ou any (code, photo, signature ou nom)', true),
  ('otp_max_attempts',       '5', 'Nombre maximal d''essais du code de livraison', true),
  ('payment_methods',        '["cash","cash_on_delivery","orange_money","moov_money","wallet"]', 'Moyens de paiement actifs', true),
  ('payment_mode',           '"simulation"', 'Mobile Money : simulation ou live (API fournisseur)', true),
  ('sms_mode',               '"simulation"', 'SMS : simulation (codes visibles par l''administration) ou live', true),
  ('driver_max_debt',        '10000', 'Commissions dues maximales avant blocage du passage EN LIGNE (FCFA)', true),
  ('withdrawal_min',         '1000', 'Montant minimal de retrait (FCFA)', true),
  ('support',                '{"phone":"+22600000000","whatsapp":"+22600000000","email":"support@telima.app","hours":"7h – 21h, 7j/7"}', 'Coordonnées du support', true)
on conflict (key) do nothing;

insert into telima.cities(name, center_lat, center_lng, radius_km) values
  ('Ouagadougou',     12.3714, -1.5197, 30),
  ('Bobo-Dioulasso',  11.1771, -4.2979, 25),
  ('Banfora',         10.6333, -4.7667, 15),
  ('Niankorodougou',  10.7350, -5.0880, 10)
on conflict (name) do nothing;

insert into telima.delivery_zones(city_id, name, center_lat, center_lng, radius_km, extra_fee, multiplier)
select c.id, z.name, z.lat, z.lng, z.radius, z.fee, z.mult
from (values
  ('Ouagadougou',    'Centre-ville',          12.3686, -1.5275, 3.0, 0,   1.00),
  ('Ouagadougou',    'Ouaga 2000',            12.3260, -1.4950, 3.0, 200, 1.00),
  ('Bobo-Dioulasso', 'Centre-ville',          11.1786, -4.2925, 3.0, 0,   1.00),
  ('Bobo-Dioulasso', 'Zone industrielle',     11.1550, -4.2600, 3.0, 200, 1.00),
  ('Banfora',        'Centre',                10.6333, -4.7667, 5.0, 0,   1.00),
  ('Niankorodougou', 'Centre',                10.7350, -5.0880, 5.0, 0,   1.00)
) as z(city, name, lat, lng, radius, fee, mult)
join telima.cities c on c.name = z.city
on conflict (city_id, name) do nothing;

-- Tarifs par défaut (city_id null) — l'administrateur peut créer des tarifs propres à chaque ville
insert into telima.pricing_rules(city_id, vehicle_type, base_price, included_km, price_per_km, min_price,
                                 fragile_fee, size_fee_moyen, size_fee_grand, size_fee_tres_grand, extra_stop_fee) values
  (null, 'moto',       500,  1, 200,  500,  200, 200,  500, 1000, 300),
  (null, 'tricycle',  1500,  1, 350, 1500,  300, 0,    500, 1500, 500),
  (null, 'voiture',   1500,  1, 400, 1500,  300, 0,    500, 1500, 500),
  (null, 'utilitaire',3000,  1, 600, 3000,  500, 0,      0, 1000, 1000);
