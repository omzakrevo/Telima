-- Migration appliquée sur le projet Supabase cloud : telima_05c1_config_log

create or replace function telima.tg_admin_config_log()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if auth.uid() is not null then
    insert into telima.admin_logs(admin_id, action, entity, entity_id, details)
    values (auth.uid(), lower(tg_op), tg_table_name,
            coalesce((case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'id',
                     (case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'key'),
            case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end);
  end if;
  return null;
end $$;
create trigger trg_log_pricing after insert or update or delete on telima.pricing_rules
  for each row execute function telima.tg_admin_config_log();
create trigger trg_log_cities after insert or update or delete on telima.cities
  for each row execute function telima.tg_admin_config_log();
create trigger trg_log_zones after insert or update or delete on telima.delivery_zones
  for each row execute function telima.tg_admin_config_log();
create trigger trg_log_settings after insert or update or delete on telima.app_settings
  for each row execute function telima.tg_admin_config_log();
