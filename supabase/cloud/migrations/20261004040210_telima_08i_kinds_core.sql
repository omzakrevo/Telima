-- Migration appliquée sur le projet Supabase cloud : telima_08i_kinds_core

alter table telima.deliveries drop constraint if exists deliveries_kind_check;
alter table telima.deliveries add constraint deliveries_kind_check check (kind in ('parcel', 'errand', 'ride'));
alter table telima.deliveries add column if not exists ride_passengers integer check (ride_passengers is null or ride_passengers between 1 and 6);
alter table telima.drivers add column if not exists services text[] not null default '{parcel,errand}';

insert into telima.app_settings(key, value, description, is_public) values
  ('ride_price_multiplier', '1', 'Multiplicateur du tarif pour le transport de personnes (1 = même tarif que les colis)', true)
on conflict (key) do nothing;

-- Type de commande posé avant l'insertion (lu par les déclencheurs de notification)
create or replace function telima.tg_delivery_kind()
returns trigger language plpgsql as $$
declare v_extra jsonb := nullif(current_setting('telima.new_extra', true), '')::jsonb;
begin
  new.kind := coalesce(nullif(current_setting('telima.new_kind', true), ''), new.kind);
  if v_extra is not null then
    new.errand_items := v_extra->>'items';
    new.errand_category := v_extra->>'category';
    new.errand_budget := nullif(v_extra->>'budget', '')::int;
    new.ride_passengers := nullif(v_extra->>'passengers', '')::int;
  end if;
  return new;
end $$;
create trigger trg_delivery_kind before insert on telima.deliveries
  for each row execute function telima.tg_delivery_kind();

-- Le livreur peut-il prendre cette demande ? (véhicule + services choisis)
create or replace function telima.driver_can_take(p_services text[], p_vehicle telima.vehicle_type,
                                                  p_kind text, p_requested telima.vehicle_type)
returns boolean language sql immutable as $$
  select case when p_kind = 'ride' then 'ride' = any(p_services) and p_vehicle = p_requested
              else coalesce(p_kind, 'parcel') = any(p_services) and telima.vehicle_can_serve(p_vehicle, p_requested) end
$$;

-- Garde-fou course à faire : le montant des achats doit être saisi avant de partir livrer
create or replace function telima.tg_errand_guard()
returns trigger language plpgsql as $$
begin
  if new.kind = 'errand' and new.status = 'picked_up' and old.status is distinct from 'picked_up' and new.purchase_amount is null then
    raise exception 'Indiquez d''abord le montant des achats' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger trg_errand_guard before update of status on telima.deliveries
  for each row execute function telima.tg_errand_guard();
