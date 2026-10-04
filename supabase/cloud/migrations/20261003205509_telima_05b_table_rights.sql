-- Migration appliquée sur le projet Supabase cloud : telima_05b_table_rights

revoke all on all tables in schema telima from anon, authenticated;
revoke all on all sequences in schema telima from anon, authenticated;
grant select on telima.app_settings, telima.cities, telima.delivery_zones, telima.pricing_rules to anon, authenticated;
grant insert on telima.support_requests to anon;
grant select on all tables in schema telima to authenticated;
revoke select on telima.delivery_secrets, telima.code_counters from authenticated;
grant update (full_name, city_id, avatar_url, is_active, deactivated_at) on telima.users to authenticated;
grant update (role, phone) on telima.users to authenticated;
grant update (default_payment_method) on telima.customers to authenticated;
grant update on telima.drivers, telima.vehicles to authenticated;
grant insert, update, delete on telima.vehicles to authenticated;
grant insert, update, delete on telima.app_settings, telima.cities, telima.delivery_zones, telima.pricing_rules to authenticated;
grant update on telima.deliveries to authenticated;
grant update (name, type, phone, address, lat, lng, city_id, is_active) on telima.business_accounts to authenticated;
grant delete on telima.business_members to authenticated;
grant select, insert, update, delete on telima.saved_addresses to authenticated;
grant insert on telima.messages to authenticated;
grant update (read_at) on telima.messages to authenticated;
grant update (read_at) on telima.notifications to authenticated;
grant delete on telima.notifications to authenticated;
grant select, insert, update, delete on telima.device_tokens to authenticated;
grant insert on telima.support_requests to authenticated;
grant update (status, admin_reply) on telima.support_requests to authenticated;
grant usage on all sequences in schema telima to authenticated;
