-- Migration appliquée sur le projet Supabase cloud : telima_07a_push_secrets

create extension if not exists pg_net with schema extensions;
create table if not exists telima.push_secrets (
  key         text primary key,
  value       text not null,
  updated_at  timestamptz not null default now()
);
alter table telima.push_secrets enable row level security;
grant all on telima.push_secrets to service_role;
insert into telima.push_secrets(key, value)
values ('webhook_secret', replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''))
on conflict (key) do nothing;
