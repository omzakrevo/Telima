-- Migration appliquée sur le projet Supabase cloud : telima_08b_columns_settings

alter table telima.deliveries
  add column if not exists kind text not null default 'parcel' check (kind in ('parcel', 'errand')),
  add column if not exists errand_items text,
  add column if not exists errand_category text,
  add column if not exists errand_budget integer check (errand_budget is null or errand_budget > 0),
  add column if not exists purchase_amount integer check (purchase_amount is null or purchase_amount >= 0),
  add column if not exists purchase_shop text,
  add column if not exists purchase_receipt_path text,
  add column if not exists purchase_at timestamptz,
  add column if not exists purchase_settlement text check (purchase_settlement is null or purchase_settlement in ('cash', 'wallet')),
  add column if not exists purchase_settled_at timestamptz;

insert into telima.app_settings(key, value, description, is_public) values
  ('mobile_money_accounts', '{"orange_money": {"number": "", "name": ""}, "moov_money": {"number": "", "name": ""}}',
   'Numéros Mobile Money sur lesquels les clients envoient leurs paiements (mode manuel)', true),
  ('errand_service_fee', '500', 'Frais de service ajoutés aux courses à faire (achat par le livreur), en FCFA', true)
on conflict (key) do nothing;

update telima.app_settings set value = '"manual"',
  description = 'Mobile Money : manual (validation par l''administrateur), simulation ou live (API fournisseur)'
 where key = 'payment_mode';
