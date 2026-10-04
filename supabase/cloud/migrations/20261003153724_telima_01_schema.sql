-- Migration appliquée sur le projet Supabase cloud : telima_01_schema

create schema if not exists extensions;
create schema if not exists telima;
grant usage on schema telima to anon, authenticated, service_role;
create extension if not exists pgcrypto with schema extensions;

create type telima.user_role as enum ('client', 'driver', 'admin', 'operator');
create type telima.driver_status as enum ('pending', 'approved', 'suspended', 'rejected');
create type telima.vehicle_type as enum ('moto', 'voiture', 'tricycle', 'utilitaire');
create type telima.package_category as enum ('document', 'nourriture', 'petit_colis', 'colis_moyen', 'gros_colis', 'courses', 'autre');
create type telima.package_size as enum ('petit', 'moyen', 'grand', 'tres_grand');
create type telima.delivery_status as enum ('created','searching','assigned','to_pickup','at_pickup','picked_up','in_transit','at_dropoff','handed_over','completed','cancelled');
create type telima.payment_method as enum ('cash', 'orange_money', 'moov_money', 'cash_on_delivery', 'wallet');
create type telima.payment_status as enum ('pending', 'paid', 'failed', 'refunded', 'cancelled');
create type telima.wallet_tx_type as enum ('earning', 'commission', 'withdrawal', 'withdrawal_refund', 'topup', 'payment', 'refund', 'adjustment');
create type telima.withdrawal_status as enum ('pending', 'paid', 'rejected');
create type telima.proof_type as enum ('otp', 'photo', 'signature', 'name');
create type telima.business_type as enum ('boutique', 'restaurant', 'pharmacie', 'entreprise', 'vendeur_en_ligne', 'autre');
create type telima.member_role as enum ('owner', 'manager', 'member');
create type telima.commission_type as enum ('percent', 'fixed');

create or replace function telima.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create table telima.app_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  is_public   boolean not null default true,
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);

create table telima.cities (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  center_lat  double precision not null check (center_lat between -90 and 90),
  center_lng  double precision not null check (center_lng between -180 and 180),
  radius_km   numeric(6,2) not null default 25 check (radius_km > 0),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create trigger trg_cities_updated before update on telima.cities
  for each row execute function telima.tg_set_updated_at();

create table telima.delivery_zones (
  id          uuid primary key default gen_random_uuid(),
  city_id     uuid not null references telima.cities(id) on delete cascade,
  name        text not null,
  center_lat  double precision not null check (center_lat between -90 and 90),
  center_lng  double precision not null check (center_lng between -180 and 180),
  radius_km   numeric(6,2) not null default 3 check (radius_km > 0),
  extra_fee   integer not null default 0 check (extra_fee >= 0),
  multiplier  numeric(4,2) not null default 1.00 check (multiplier > 0),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (city_id, name)
);
create index idx_zones_city on telima.delivery_zones(city_id) where is_active;
create trigger trg_zones_updated before update on telima.delivery_zones
  for each row execute function telima.tg_set_updated_at();

create table telima.users (
  id              uuid primary key references auth.users(id) on delete cascade,
  phone           text not null unique check (phone ~ '^\+[0-9]{8,15}$'),
  full_name       text not null check (char_length(full_name) between 2 and 120),
  city_id         uuid references telima.cities(id) on delete set null,
  avatar_url      text,
  role            telima.user_role not null default 'client',
  is_active       boolean not null default true,
  deactivated_at  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index idx_users_role on telima.users(role);
create index idx_users_city on telima.users(city_id);
create trigger trg_users_updated before update on telima.users
  for each row execute function telima.tg_set_updated_at();

create table telima.customers (
  user_id                 uuid primary key references telima.users(id) on delete cascade,
  default_payment_method  telima.payment_method not null default 'cash',
  total_deliveries        integer not null default 0,
  created_at              timestamptz not null default now()
);

create table telima.drivers (
  user_id             uuid primary key references telima.users(id) on delete cascade,
  status              telima.driver_status not null default 'pending',
  is_online           boolean not null default false,
  city_id             uuid references telima.cities(id) on delete set null,
  id_document_number  text,
  id_document_path    text,
  license_number      text,
  license_path        text,
  rating_avg          numeric(3,2) not null default 0 check (rating_avg between 0 and 5),
  rating_count        integer not null default 0,
  total_deliveries    integer not null default 0,
  current_lat         double precision,
  current_lng         double precision,
  last_location_at    timestamptz,
  approved_at         timestamptz,
  approved_by         uuid references telima.users(id) on delete set null,
  status_note         text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index idx_drivers_online on telima.drivers(is_online, status) where is_online;
create index idx_drivers_city on telima.drivers(city_id);
create trigger trg_drivers_updated before update on telima.drivers
  for each row execute function telima.tg_set_updated_at();

create table telima.vehicles (
  id            uuid primary key default gen_random_uuid(),
  driver_id     uuid not null references telima.drivers(user_id) on delete cascade,
  type          telima.vehicle_type not null,
  brand         text,
  model         text,
  color         text,
  plate_number  text,
  photo_path    text,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index idx_vehicles_driver on telima.vehicles(driver_id);
create unique index uq_vehicle_active_per_driver on telima.vehicles(driver_id) where is_active;
create trigger trg_vehicles_updated before update on telima.vehicles
  for each row execute function telima.tg_set_updated_at();

create table telima.business_accounts (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 2 and 120),
  type        telima.business_type not null default 'boutique',
  owner_id    uuid not null references telima.users(id) on delete restrict,
  phone       text check (phone is null or phone ~ '^\+[0-9]{8,15}$'),
  address     text,
  lat         double precision,
  lng         double precision,
  city_id     uuid references telima.cities(id) on delete set null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_business_owner on telima.business_accounts(owner_id);
create trigger trg_business_updated before update on telima.business_accounts
  for each row execute function telima.tg_set_updated_at();

create table telima.business_members (
  business_id uuid not null references telima.business_accounts(id) on delete cascade,
  user_id     uuid not null references telima.users(id) on delete cascade,
  role        telima.member_role not null default 'member',
  created_at  timestamptz not null default now(),
  primary key (business_id, user_id)
);
create index idx_business_members_user on telima.business_members(user_id);

create table telima.saved_addresses (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references telima.users(id) on delete cascade,
  business_id   uuid references telima.business_accounts(id) on delete cascade,
  label         text not null,
  contact_name  text,
  contact_phone text,
  address       text not null,
  lat           double precision not null,
  lng           double precision not null,
  instructions  text,
  created_at    timestamptz not null default now(),
  check (user_id is not null or business_id is not null)
);
create index idx_saved_addr_user on telima.saved_addresses(user_id);
create index idx_saved_addr_business on telima.saved_addresses(business_id);

create table telima.pricing_rules (
  id               uuid primary key default gen_random_uuid(),
  city_id          uuid references telima.cities(id) on delete cascade,
  vehicle_type     telima.vehicle_type not null,
  base_price       integer not null check (base_price >= 0),
  included_km      numeric(5,2) not null default 0 check (included_km >= 0),
  price_per_km     integer not null check (price_per_km >= 0),
  min_price        integer not null default 0 check (min_price >= 0),
  fragile_fee      integer not null default 0 check (fragile_fee >= 0),
  size_fee_moyen   integer not null default 0 check (size_fee_moyen >= 0),
  size_fee_grand   integer not null default 0 check (size_fee_grand >= 0),
  size_fee_tres_grand integer not null default 0 check (size_fee_tres_grand >= 0),
  extra_stop_fee   integer not null default 0 check (extra_stop_fee >= 0),
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index uq_pricing_city_vehicle
  on telima.pricing_rules (coalesce(city_id, '00000000-0000-0000-0000-000000000000'::uuid), vehicle_type)
  where is_active;
create trigger trg_pricing_updated before update on telima.pricing_rules
  for each row execute function telima.tg_set_updated_at();

create table telima.code_counters (
  scope   text not null,
  year    integer not null,
  last    integer not null default 0,
  primary key (scope, year)
);

create table telima.delivery_batches (
  id            uuid primary key default gen_random_uuid(),
  code          text not null unique,
  customer_id   uuid references telima.users(id) on delete set null,
  business_id   uuid references telima.business_accounts(id) on delete set null,
  driver_id     uuid references telima.drivers(user_id) on delete set null,
  stops_count   integer not null check (stops_count >= 1),
  total_price   integer not null default 0,
  created_at    timestamptz not null default now()
);

create table telima.deliveries (
  id                  uuid primary key default gen_random_uuid(),
  code                text not null unique,
  status              telima.delivery_status not null default 'created',
  customer_id         uuid references telima.users(id) on delete set null,
  customer_name       text not null,
  customer_phone      text not null,
  business_id         uuid references telima.business_accounts(id) on delete set null,
  created_by          uuid references telima.users(id) on delete set null,
  created_via         text not null default 'app' check (created_via in ('app', 'admin', 'business')),
  driver_id           uuid references telima.drivers(user_id) on delete set null,
  vehicle_id          uuid references telima.vehicles(id) on delete set null,
  vehicle_type        telima.vehicle_type not null,
  city_id             uuid references telima.cities(id) on delete set null,
  zone_id             uuid references telima.delivery_zones(id) on delete set null,
  batch_id            uuid references telima.delivery_batches(id) on delete set null,
  stop_order          integer not null default 1 check (stop_order >= 1),
  pickup_address      text not null,
  pickup_lat          double precision not null check (pickup_lat between -90 and 90),
  pickup_lng          double precision not null check (pickup_lng between -180 and 180),
  pickup_contact_name text not null,
  pickup_contact_phone text not null,
  pickup_instructions text,
  dropoff_address      text not null,
  dropoff_lat          double precision not null check (dropoff_lat between -90 and 90),
  dropoff_lng          double precision not null check (dropoff_lng between -180 and 180),
  dropoff_contact_name text not null,
  dropoff_contact_phone text not null,
  dropoff_instructions text,
  package_category    telima.package_category not null,
  package_description text,
  package_photo_path  text,
  package_quantity    integer not null default 1 check (package_quantity between 1 and 999),
  package_fragile     boolean not null default false,
  package_size        telima.package_size not null default 'petit',
  package_weight_kg   numeric(7,2) check (package_weight_kg is null or package_weight_kg >= 0),
  distance_km         numeric(7,2) not null check (distance_km >= 0),
  price_base          integer not null default 0,
  price_distance      integer not null default 0,
  price_extras        integer not null default 0,
  price_zone          integer not null default 0,
  total_price         integer not null check (total_price >= 0),
  commission_type     telima.commission_type not null,
  commission_value    numeric(10,2) not null,
  commission_amount   integer not null check (commission_amount >= 0),
  driver_earning      integer not null check (driver_earning >= 0),
  payment_method      telima.payment_method not null,
  payment_status      telima.payment_status not null default 'pending',
  proof_type          telima.proof_type,
  proof_photo_path    text,
  proof_signature_path text,
  receiver_name       text,
  eta_minutes         integer,
  near_notified       boolean not null default false,
  cancel_reason       text,
  cancelled_by        uuid references telima.users(id) on delete set null,
  searching_at        timestamptz,
  assigned_at         timestamptz,
  picked_up_at        timestamptz,
  delivered_at        timestamptz,
  completed_at        timestamptz,
  cancelled_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (commission_amount + driver_earning = total_price)
);
create index idx_deliveries_customer on telima.deliveries(customer_id, created_at desc);
create index idx_deliveries_driver on telima.deliveries(driver_id, created_at desc);
create index idx_deliveries_status on telima.deliveries(status);
create index idx_deliveries_searching on telima.deliveries(vehicle_type, created_at) where status = 'searching';
create index idx_deliveries_business on telima.deliveries(business_id, created_at desc);
create index idx_deliveries_batch on telima.deliveries(batch_id, stop_order);
create index idx_deliveries_created on telima.deliveries(created_at desc);
create index idx_deliveries_city on telima.deliveries(city_id);
create trigger trg_deliveries_updated before update on telima.deliveries
  for each row execute function telima.tg_set_updated_at();

create table telima.delivery_secrets (
  delivery_id   uuid primary key references telima.deliveries(id) on delete cascade,
  otp_code      text not null check (otp_code ~ '^[0-9]{4}$'),
  attempts      integer not null default 0,
  locked        boolean not null default false,
  created_at    timestamptz not null default now()
);

create table telima.delivery_status_history (
  id           bigint generated always as identity primary key,
  delivery_id  uuid not null references telima.deliveries(id) on delete cascade,
  status       telima.delivery_status not null,
  changed_by   uuid references telima.users(id) on delete set null,
  note         text,
  lat          double precision,
  lng          double precision,
  created_at   timestamptz not null default now()
);
create index idx_status_history_delivery on telima.delivery_status_history(delivery_id, created_at);

create table telima.delivery_locations (
  id           bigint generated always as identity primary key,
  delivery_id  uuid not null references telima.deliveries(id) on delete cascade,
  driver_id    uuid not null references telima.drivers(user_id) on delete cascade,
  lat          double precision not null check (lat between -90 and 90),
  lng          double precision not null check (lng between -180 and 180),
  heading      double precision,
  speed        double precision,
  recorded_at  timestamptz not null default now()
);
create index idx_locations_delivery on telima.delivery_locations(delivery_id, recorded_at desc);

create table telima.delivery_declines (
  delivery_id  uuid not null references telima.deliveries(id) on delete cascade,
  driver_id    uuid not null references telima.drivers(user_id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (delivery_id, driver_id)
);

create table telima.payments (
  id            uuid primary key default gen_random_uuid(),
  delivery_id   uuid references telima.deliveries(id) on delete set null,
  payer_id      uuid references telima.users(id) on delete set null,
  amount        integer not null check (amount >= 0),
  method        telima.payment_method not null,
  provider      text not null default 'internal',
  provider_ref  text,
  status        telima.payment_status not null default 'pending',
  metadata      jsonb not null default '{}'::jsonb,
  paid_at       timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index idx_payments_delivery on telima.payments(delivery_id);
create index idx_payments_payer on telima.payments(payer_id, created_at desc);
create index idx_payments_created on telima.payments(created_at desc);
create trigger trg_payments_updated before update on telima.payments
  for each row execute function telima.tg_set_updated_at();

create table telima.wallets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references telima.users(id) on delete cascade,
  balance     integer not null default 0,
  currency    text not null default 'XOF',
  updated_at  timestamptz not null default now()
);

create table telima.wallet_transactions (
  id            bigint generated always as identity primary key,
  wallet_id     uuid not null references telima.wallets(id) on delete cascade,
  type          telima.wallet_tx_type not null,
  amount        integer not null check (amount <> 0),
  balance_after integer not null,
  delivery_id   uuid references telima.deliveries(id) on delete set null,
  withdrawal_id uuid,
  reference     text,
  description   text,
  created_by    uuid references telima.users(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index idx_wallet_tx_wallet on telima.wallet_transactions(wallet_id, created_at desc);
create index idx_wallet_tx_delivery on telima.wallet_transactions(delivery_id);

create table telima.withdrawals (
  id            uuid primary key default gen_random_uuid(),
  wallet_id     uuid not null references telima.wallets(id) on delete cascade,
  user_id       uuid not null references telima.users(id) on delete cascade,
  amount        integer not null check (amount > 0),
  method        telima.payment_method not null check (method in ('orange_money', 'moov_money', 'cash')),
  phone         text not null,
  status        telima.withdrawal_status not null default 'pending',
  provider_ref  text,
  note          text,
  processed_by  uuid references telima.users(id) on delete set null,
  processed_at  timestamptz,
  created_at    timestamptz not null default now()
);
create index idx_withdrawals_user on telima.withdrawals(user_id, created_at desc);
create index idx_withdrawals_status on telima.withdrawals(status);
alter table telima.wallet_transactions
  add constraint fk_wallet_tx_withdrawal foreign key (withdrawal_id) references telima.withdrawals(id) on delete set null;

create table telima.ratings (
  id           uuid primary key default gen_random_uuid(),
  delivery_id  uuid not null unique references telima.deliveries(id) on delete cascade,
  customer_id  uuid not null references telima.users(id) on delete cascade,
  driver_id    uuid not null references telima.drivers(user_id) on delete cascade,
  stars        smallint not null check (stars between 1 and 5),
  comment      text check (comment is null or char_length(comment) <= 1000),
  created_at   timestamptz not null default now()
);
create index idx_ratings_driver on telima.ratings(driver_id, created_at desc);

create table telima.messages (
  id           bigint generated always as identity primary key,
  delivery_id  uuid not null references telima.deliveries(id) on delete cascade,
  sender_id    uuid not null references telima.users(id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 1000),
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index idx_messages_delivery on telima.messages(delivery_id, created_at);

create table telima.notifications (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references telima.users(id) on delete cascade,
  type         text not null default 'info',
  title        text not null,
  body         text not null,
  data         jsonb not null default '{}'::jsonb,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index idx_notifications_user on telima.notifications(user_id, created_at desc);
create index idx_notifications_unread on telima.notifications(user_id) where read_at is null;

create table telima.device_tokens (
  token       text primary key,
  user_id     uuid not null references telima.users(id) on delete cascade,
  platform    text not null check (platform in ('android', 'ios', 'web')),
  updated_at  timestamptz not null default now()
);
create index idx_device_tokens_user on telima.device_tokens(user_id);

create table telima.support_requests (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references telima.users(id) on delete set null,
  phone        text,
  delivery_id  uuid references telima.deliveries(id) on delete set null,
  subject      text not null,
  message      text not null check (char_length(message) between 1 and 2000),
  status       text not null default 'open' check (status in ('open', 'in_progress', 'closed')),
  admin_reply  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index idx_support_status on telima.support_requests(status, created_at desc);
create trigger trg_support_updated before update on telima.support_requests
  for each row execute function telima.tg_set_updated_at();

create table telima.password_reset_requests (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references telima.users(id) on delete cascade,
  phone       text not null,
  code_hash   text not null,
  code_plain  text,
  attempts    integer not null default 0,
  used_at     timestamptz,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);
create index idx_pwd_reset_user on telima.password_reset_requests(user_id, created_at desc);

create table telima.admin_logs (
  id          bigint generated always as identity primary key,
  admin_id    uuid references telima.users(id) on delete set null,
  action      text not null,
  entity      text not null,
  entity_id   text,
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
create index idx_admin_logs_created on telima.admin_logs(created_at desc);
create index idx_admin_logs_entity on telima.admin_logs(entity, entity_id);
