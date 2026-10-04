-- Migration appliquée sur le projet Supabase cloud : telima_02b8_triggers

create or replace function telima.tg_delivery_status_change()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare
  v_lat float8 := nullif(current_setting('telima.status_lat', true), '')::float8;
  v_lng float8 := nullif(current_setting('telima.status_lng', true), '')::float8;
  v_note text := nullif(current_setting('telima.status_note', true), '');
  v_body text;
begin
  if tg_op = 'INSERT' then
    insert into telima.delivery_status_history(delivery_id, status, changed_by, note)
    values (new.id, 'created', auth.uid(), null);
    if new.status <> 'created' then
      insert into telima.delivery_status_history(delivery_id, status, changed_by)
      values (new.id, new.status, auth.uid());
    end if;
    return null;
  end if;

  if new.status is distinct from old.status then
    insert into telima.delivery_status_history(delivery_id, status, changed_by, note, lat, lng)
    values (new.id, new.status, auth.uid(), v_note, v_lat, v_lng);

    v_body := case new.status
      when 'searching'   then case when old.status in ('assigned', 'to_pickup', 'at_pickup')
                                   then 'Le livreur s''est désisté. Nous recherchons un autre livreur.'
                                   else 'Recherche d''un livreur disponible…' end
      when 'assigned'    then 'Un livreur a accepté votre commande.'
      when 'to_pickup'   then 'Votre livreur est en route vers le point de récupération.'
      when 'at_pickup'   then 'Votre livreur est arrivé au point de récupération.'
      when 'picked_up'   then 'Votre colis a été récupéré.'
      when 'in_transit'  then 'Votre colis est en route.'
      when 'at_dropoff'  then 'Le livreur est arrivé à destination.'
      when 'completed'   then 'Livraison terminée.'
      when 'cancelled'   then 'Votre livraison a été annulée.'
      else null end;
    if v_body is not null and new.customer_id is not null
       and not (new.batch_id is not null and new.stop_order > 1 and new.status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up')) then
      perform telima.notify_user(new.customer_id, 'delivery_status', new.code, v_body,
                                 jsonb_build_object('delivery_id', new.id, 'status', new.status));
    end if;
    if new.status = 'cancelled' and new.driver_id is not null and new.cancelled_by is distinct from new.driver_id then
      perform telima.notify_user(new.driver_id, 'delivery_cancelled', new.code, 'La course a été annulée.',
                                 jsonb_build_object('delivery_id', new.id));
    end if;
  end if;
  return null;
end $$;
create trigger trg_delivery_status after insert or update of status on telima.deliveries
  for each row execute function telima.tg_delivery_status_change();

create or replace function telima.tg_message_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_del telima.deliveries; v_target uuid;
begin
  select * into v_del from telima.deliveries where id = new.delivery_id;
  v_target := case when new.sender_id = v_del.driver_id then v_del.customer_id else v_del.driver_id end;
  if v_target is not null and v_target <> new.sender_id then
    perform telima.notify_user(v_target, 'message', 'Nouveau message · ' || v_del.code, left(new.body, 140),
                               jsonb_build_object('delivery_id', new.delivery_id));
  end if;
  return null;
end $$;
create trigger trg_message_notify after insert on telima.messages
  for each row execute function telima.tg_message_notify();
