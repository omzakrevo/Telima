-- Migration appliquée sur le projet Supabase cloud : telima_07c_push_trigger

create or replace function telima.tg_notification_push()
returns trigger language plpgsql security definer set search_path = telima, public, extensions as $$
declare v_secret text;
begin
  if not exists (select 1 from telima.device_tokens where user_id = new.user_id) then return new; end if;
  select value into v_secret from telima.push_secrets where key = 'webhook_secret';
  perform net.http_post(
    url := 'https://jsiorslrikkosfocgpuo.supabase.co/functions/v1/telima-push',
    body := jsonb_build_object('id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-telima-secret', v_secret),
    timeout_milliseconds := 8000
  );
  return new;
exception when others then
  return new;
end $$;

create trigger trg_notification_push after insert on telima.notifications
  for each row execute function telima.tg_notification_push();
