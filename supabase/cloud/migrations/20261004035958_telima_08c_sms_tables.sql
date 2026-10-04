-- Migration appliquée sur le projet Supabase cloud : telima_08c_sms_tables

create table if not exists telima.sms_relays (
  token       text primary key,
  user_id     uuid not null references telima.users(id) on delete cascade,
  label       text,
  created_at  timestamptz not null default now(),
  last_seen   timestamptz,
  revoked_at  timestamptz
);
alter table telima.sms_relays enable row level security;
grant all on telima.sms_relays to service_role;

create table if not exists telima.mm_sms (
  id                bigint generated always as identity primary key,
  sender            text not null,
  body              text not null,
  received_at       timestamptz not null default now(),
  operator          text,
  direction         text not null default 'unknown' check (direction in ('in', 'out', 'unknown')),
  amount            integer,
  counterpart_phone text,
  txn_ref           text,
  payment_id        uuid references telima.payments(id) on delete set null,
  relay_user        uuid references telima.users(id) on delete set null,
  hash              text unique,
  created_at        timestamptz not null default now()
);
create index if not exists idx_mm_sms_received on telima.mm_sms(received_at desc);
alter table telima.mm_sms enable row level security;
create policy mm_sms_staff_read on telima.mm_sms for select using (telima.is_staff());
grant select on telima.mm_sms to authenticated;
grant all on telima.mm_sms to service_role;
