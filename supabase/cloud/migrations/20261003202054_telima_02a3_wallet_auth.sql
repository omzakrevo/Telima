-- Migration appliquée sur le projet Supabase cloud : telima_02a3_wallet_auth

create or replace function telima.ensure_wallet(p_user_id uuid)
returns uuid language plpgsql security definer set search_path = telima, public as $$
declare v_id uuid;
begin
  select id into v_id from telima.wallets where user_id = p_user_id;
  if v_id is null then
    insert into telima.wallets(user_id) values (p_user_id)
    on conflict (user_id) do nothing returning id into v_id;
    if v_id is null then select id into v_id from telima.wallets where user_id = p_user_id; end if;
  end if;
  return v_id;
end $$;

create or replace function telima.wallet_apply(
  p_user_id uuid, p_type telima.wallet_tx_type, p_amount integer,
  p_delivery_id uuid default null, p_withdrawal_id uuid default null,
  p_description text default null, p_allow_negative boolean default false)
returns integer language plpgsql security definer set search_path = telima, public as $$
declare
  v_wallet uuid := telima.ensure_wallet(p_user_id);
  v_balance integer;
begin
  if p_amount = 0 then
    select balance into v_balance from telima.wallets where id = v_wallet;
    return v_balance;
  end if;
  select balance into v_balance from telima.wallets where id = v_wallet for update;
  if not p_allow_negative and v_balance + p_amount < 0 then
    raise exception 'Solde insuffisant (solde : % FCFA)', v_balance using errcode = 'P0001';
  end if;
  update telima.wallets set balance = balance + p_amount, updated_at = now()
   where id = v_wallet returning balance into v_balance;
  insert into telima.wallet_transactions(wallet_id, type, amount, balance_after, delivery_id, withdrawal_id, description, created_by)
  values (v_wallet, p_type, p_amount, v_balance, p_delivery_id, p_withdrawal_id, p_description, auth.uid());
  return v_balance;
end $$;

create or replace function telima.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare
  v_meta  jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_phone text;
  v_role  telima.user_role := 'client';
  v_city  uuid;
begin
  v_phone := telima.normalize_phone(coalesce(v_meta->>'phone', new.phone, split_part(new.email, '@', 1)));
  if v_meta->>'role' = 'driver' then v_role := 'driver'; end if;
  if v_meta ? 'city_id' and nullif(v_meta->>'city_id', '') is not null then
    select id into v_city from telima.cities where id = (v_meta->>'city_id')::uuid;
  end if;

  insert into telima.users(id, phone, full_name, city_id, avatar_url, role)
  values (new.id, v_phone, coalesce(nullif(trim(v_meta->>'full_name'), ''), 'Utilisateur'), v_city,
          nullif(v_meta->>'avatar_url', ''), v_role);
  insert into telima.customers(user_id) values (new.id);
  perform telima.ensure_wallet(new.id);
  if v_role = 'driver' then
    insert into telima.drivers(user_id, city_id) values (new.id, v_city);
  end if;
  return new;
end $$;

create or replace function telima.tg_users_guard()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if auth.uid() is null or telima.is_admin() then
    return new;
  end if;
  if new.role is distinct from old.role
     or new.phone is distinct from old.phone
     or (new.is_active is distinct from old.is_active and not (old.id = auth.uid() and new.is_active = false))
     or new.id is distinct from old.id then
    raise exception 'Modification non autorisée' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_users_guard before update on telima.users
  for each row execute function telima.tg_users_guard();
