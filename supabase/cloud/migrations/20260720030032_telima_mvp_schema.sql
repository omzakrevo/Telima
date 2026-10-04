-- Migration appliquée sur le projet Supabase cloud : telima_mvp_schema


create type public.user_role as enum ('customer', 'driver', 'admin');
create type public.order_type as enum ('parcel', 'errand');
create type public.order_status as enum ('pending_driver', 'accepted', 'to_pickup', 'picked_up', 'delivering', 'delivered', 'cancelled');
create type public.payment_method as enum ('cash');
create type public.payment_status as enum ('pending', 'paid');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(trim(full_name)) >= 2),
  phone text,
  role public.user_role not null default 'customer',
  created_at timestamptz not null default now()
);

create table public.drivers (
  id uuid primary key references public.profiles(id) on delete cascade,
  vehicle_type text,
  is_available boolean not null default false,
  is_verified boolean not null default false,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz not null default now(),
  constraint valid_latitude check (latitude is null or latitude between -90 and 90),
  constraint valid_longitude check (longitude is null or longitude between -180 and 180)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  driver_id uuid references public.drivers(id),
  order_type public.order_type not null,
  pickup_address text,
  pickup_latitude double precision,
  pickup_longitude double precision,
  delivery_address text not null,
  delivery_latitude double precision,
  delivery_longitude double precision,
  item_description text not null,
  recipient_phone text,
  instructions text,
  estimated_purchase_budget numeric(12,2),
  total_price numeric(12,2) not null default 2000 check (total_price >= 0),
  driver_amount numeric(12,2) not null default 1500 check (driver_amount >= 0),
  platform_commission numeric(12,2) not null default 500 check (platform_commission >= 0),
  payment_method public.payment_method not null default 'cash',
  payment_status public.payment_status not null default 'pending',
  status public.order_status not null default 'pending_driver',
  otp_code text not null check (otp_code ~ '^[0-9]{4}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint parcel_requires_pickup check (order_type <> 'parcel' or pickup_address is not null),
  constraint valid_pickup_latitude check (pickup_latitude is null or pickup_latitude between -90 and 90),
  constraint valid_pickup_longitude check (pickup_longitude is null or pickup_longitude between -180 and 180),
  constraint valid_delivery_latitude check (delivery_latitude is null or delivery_latitude between -90 and 90),
  constraint valid_delivery_longitude check (delivery_longitude is null or delivery_longitude between -180 and 180)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index orders_customer_idx on public.orders(customer_id, created_at desc);
create index orders_driver_idx on public.orders(driver_id, created_at desc);
create index notifications_user_idx on public.notifications(user_id, created_at desc);
create index drivers_assignment_idx on public.drivers(is_verified, is_available);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role public.user_role;
begin
  requested_role := case
    when new.raw_user_meta_data ->> 'requested_role' = 'driver' then 'driver'::public.user_role
    else 'customer'::public.user_role
  end;

  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 'Utilisateur'),
    nullif(trim(new.raw_user_meta_data ->> 'phone'), ''),
    requested_role
  );

  if requested_role = 'driver' then
    insert into public.drivers (id, vehicle_type) values (new.id, nullif(trim(new.raw_user_meta_data ->> 'vehicle_type'), ''));
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = (select auth.uid()) and role = 'admin'
  );
$$;

create function public.set_driver_availability(p_available boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.drivers
  set is_available = p_available, updated_at = now()
  where id = (select auth.uid()) and is_verified = true;
  if not found then
    raise exception 'Driver account is not verified';
  end if;
end;
$$;

create function public.update_driver_location(p_latitude double precision, p_longitude double precision)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'Invalid location';
  end if;
  update public.drivers
  set latitude = p_latitude, longitude = p_longitude, updated_at = now()
  where id = (select auth.uid()) and is_verified = true;
  if not found then
    raise exception 'Driver account is not verified';
  end if;
end;
$$;

create function public.create_order(
  p_order_type public.order_type,
  p_pickup_address text,
  p_pickup_latitude double precision,
  p_pickup_longitude double precision,
  p_delivery_address text,
  p_delivery_latitude double precision,
  p_delivery_longitude double precision,
  p_item_description text,
  p_recipient_phone text default null,
  p_instructions text default null,
  p_estimated_purchase_budget numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  assigned_driver uuid;
  order_id uuid;
  origin_lat double precision := coalesce(p_pickup_latitude, p_delivery_latitude);
  origin_lng double precision := coalesce(p_pickup_longitude, p_delivery_longitude);
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  if p_order_type = 'parcel' and nullif(trim(coalesce(p_pickup_address, '')), '') is null then
    raise exception 'A pickup address is required for parcel deliveries';
  end if;

  select d.id into assigned_driver
  from public.drivers d
  where d.is_verified and d.is_available and d.latitude is not null and d.longitude is not null
  order by case when origin_lat is null or origin_lng is null then 0
    else power(d.latitude - origin_lat, 2) + power(d.longitude - origin_lng, 2)
  end
  limit 1;

  insert into public.orders (
    customer_id, driver_id, order_type, pickup_address, pickup_latitude, pickup_longitude,
    delivery_address, delivery_latitude, delivery_longitude, item_description, recipient_phone,
    instructions, estimated_purchase_budget, otp_code
  ) values (
    (select auth.uid()), assigned_driver, p_order_type, nullif(trim(p_pickup_address), ''),
    p_pickup_latitude, p_pickup_longitude, p_delivery_address, p_delivery_latitude,
    p_delivery_longitude, p_item_description, nullif(trim(p_recipient_phone), ''),
    nullif(trim(p_instructions), ''), p_estimated_purchase_budget,
    lpad((floor(random() * 10000))::int::text, 4, '0')
  ) returning id into order_id;

  insert into public.notifications (user_id, title, message)
  values ((select auth.uid()), 'Commande créée', 'Votre commande a été enregistrée.');

  if assigned_driver is not null then
    insert into public.notifications (user_id, title, message)
    values (assigned_driver, 'Nouvelle commande', 'Une commande vous est proposée.');
  end if;
  return order_id;
end;
$$;

create function public.transition_order(p_order_id uuid, p_status public.order_status, p_otp_code text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_order public.orders;
  actor_id uuid := (select auth.uid());
begin
  select * into current_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;

  if (select public.is_admin()) then
    update public.orders set status = p_status, updated_at = now() where id = p_order_id;
  elsif current_order.driver_id = actor_id then
    if p_status = 'delivered' and p_otp_code is distinct from current_order.otp_code then
      raise exception 'Invalid delivery code';
    end if;
    if p_status not in ('accepted', 'to_pickup', 'picked_up', 'delivering', 'delivered', 'cancelled') then
      raise exception 'Invalid driver status';
    end if;
    update public.orders set status = p_status, payment_status = case when p_status = 'delivered' then 'paid'::public.payment_status else payment_status end, updated_at = now()
    where id = p_order_id;
  elsif current_order.customer_id = actor_id and p_status = 'cancelled'
    and current_order.status in ('pending_driver', 'accepted') then
    update public.orders set status = 'cancelled', updated_at = now() where id = p_order_id;
  else
    raise exception 'Not allowed';
  end if;

  insert into public.notifications (user_id, title, message)
  values (current_order.customer_id, 'Commande mise à jour', 'Le statut de votre commande a changé.');
end;
$$;

create function public.mark_notification_read(p_notification_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.notifications set is_read = true
  where id = p_notification_id and user_id = (select auth.uid());
$$;

alter table public.profiles enable row level security;
alter table public.drivers enable row level security;
alter table public.orders enable row level security;
alter table public.notifications enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.drivers, public.orders, public.notifications to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.set_driver_availability(boolean) to authenticated;
grant execute on function public.update_driver_location(double precision, double precision) to authenticated;
grant execute on function public.create_order(public.order_type, text, double precision, double precision, text, double precision, double precision, text, text, text, numeric) to authenticated;
grant execute on function public.transition_order(uuid, public.order_status, text) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;

create policy "profiles visible to owner or admin" on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select public.is_admin()));

create policy "drivers visible to authenticated users" on public.drivers for select to authenticated using (true);

create policy "orders visible to customer driver or admin" on public.orders for select to authenticated
using (
  customer_id = (select auth.uid())
  or driver_id = (select auth.uid())
  or (select public.is_admin())
);

create policy "notifications visible to recipient" on public.notifications for select to authenticated
using (user_id = (select auth.uid()));
;
