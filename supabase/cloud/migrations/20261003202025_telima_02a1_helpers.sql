-- Migration appliquée sur le projet Supabase cloud : telima_02a1_helpers

create or replace function telima.current_user_role()
returns telima.user_role
language sql stable security definer set search_path = telima, public as $$
  select role from telima.users where id = auth.uid() and is_active
$$;

create or replace function telima.is_admin()
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (select 1 from telima.users where id = auth.uid() and role = 'admin' and is_active)
$$;

create or replace function telima.is_staff()
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (select 1 from telima.users where id = auth.uid() and role in ('admin', 'operator') and is_active)
$$;
