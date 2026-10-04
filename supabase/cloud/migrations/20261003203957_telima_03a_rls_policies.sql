-- Migration appliquée sur le projet Supabase cloud : telima_03a_rls_policies

do $$
declare t text;
begin
  foreach t in array array[
    'app_settings', 'cities', 'delivery_zones', 'users', 'customers', 'drivers', 'vehicles',
    'business_accounts', 'business_members', 'saved_addresses', 'pricing_rules', 'code_counters',
    'delivery_batches', 'deliveries', 'delivery_secrets', 'delivery_status_history', 'delivery_locations',
    'delivery_declines', 'payments', 'wallets', 'wallet_transactions', 'withdrawals', 'ratings', 'messages',
    'notifications', 'device_tokens', 'support_requests', 'password_reset_requests', 'admin_logs']
  loop
    execute format('alter table telima.%I enable row level security', t);
  end loop;
end $$;

create policy settings_read on telima.app_settings for select using (is_public or telima.is_staff());
create policy settings_admin_write on telima.app_settings for all using (telima.is_admin()) with check (telima.is_admin());
create policy cities_read on telima.cities for select using (is_active or telima.is_staff());
create policy cities_admin on telima.cities for all using (telima.is_admin()) with check (telima.is_admin());
create policy zones_read on telima.delivery_zones for select using (is_active or telima.is_staff());
create policy zones_admin on telima.delivery_zones for all using (telima.is_admin()) with check (telima.is_admin());
create policy pricing_read on telima.pricing_rules for select using (is_active or telima.is_staff());
create policy pricing_admin on telima.pricing_rules for all using (telima.is_admin()) with check (telima.is_admin());

create policy users_self_read on telima.users for select using (id = auth.uid() or telima.is_staff());
create policy users_self_update on telima.users for update
  using (id = auth.uid() or telima.is_admin()) with check (id = auth.uid() or telima.is_admin());
create policy customers_read on telima.customers for select using (user_id = auth.uid() or telima.is_staff());
create policy customers_update on telima.customers for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy drivers_read on telima.drivers for select using (user_id = auth.uid() or telima.is_staff());
create policy drivers_admin on telima.drivers for update using (telima.is_admin()) with check (telima.is_admin());
create policy vehicles_read on telima.vehicles for select using (driver_id = auth.uid() or telima.is_staff());
create policy vehicles_admin on telima.vehicles for all using (telima.is_admin()) with check (telima.is_admin());

create or replace function telima.is_business_member(p_business uuid, p_roles telima.member_role[] default null)
returns boolean language sql stable security definer set search_path = telima, public as $$
  select exists (select 1 from telima.business_members
                  where business_id = p_business and user_id = auth.uid()
                    and (p_roles is null or role = any(p_roles)))
$$;

create policy business_read on telima.business_accounts for select
  using (telima.is_business_member(id) or telima.is_staff());
create policy business_update on telima.business_accounts for update
  using (telima.is_business_member(id, array['owner','manager']::telima.member_role[]) or telima.is_admin())
  with check (telima.is_business_member(id, array['owner','manager']::telima.member_role[]) or telima.is_admin());
create policy business_members_read on telima.business_members for select
  using (user_id = auth.uid() or telima.is_business_member(business_id) or telima.is_staff());
create policy saved_addresses_all on telima.saved_addresses for all
  using (user_id = auth.uid() or (business_id is not null and telima.is_business_member(business_id)))
  with check ((user_id = auth.uid() and business_id is null)
              or (business_id is not null and telima.is_business_member(business_id)));

create policy deliveries_read on telima.deliveries for select using (
  customer_id = auth.uid() or driver_id = auth.uid()
  or (business_id is not null and telima.is_business_member(business_id)) or telima.is_staff());
create policy deliveries_staff_update on telima.deliveries for update using (telima.is_staff()) with check (telima.is_staff());
create policy batches_read on telima.delivery_batches for select using (
  customer_id = auth.uid() or driver_id = auth.uid()
  or (business_id is not null and telima.is_business_member(business_id)) or telima.is_staff());
create policy status_history_read on telima.delivery_status_history for select using (telima.can_access_delivery(delivery_id));
create policy locations_read on telima.delivery_locations for select using (telima.can_access_delivery(delivery_id));
create policy declines_read on telima.delivery_declines for select using (driver_id = auth.uid() or telima.is_staff());

create policy payments_read on telima.payments for select
  using (payer_id = auth.uid() or telima.is_staff()
         or (delivery_id is not null and exists (select 1 from telima.deliveries d where d.id = delivery_id and d.driver_id = auth.uid())));
create policy wallets_read on telima.wallets for select using (user_id = auth.uid() or telima.is_staff());
create policy wallet_tx_read on telima.wallet_transactions for select
  using (exists (select 1 from telima.wallets w where w.id = wallet_id and (w.user_id = auth.uid() or telima.is_staff())));
create policy withdrawals_read on telima.withdrawals for select using (user_id = auth.uid() or telima.is_staff());

create policy ratings_read on telima.ratings for select
  using (customer_id = auth.uid() or driver_id = auth.uid() or telima.is_staff());
create policy messages_read on telima.messages for select using (telima.can_access_delivery(delivery_id));
create policy messages_insert on telima.messages for insert with check (
  sender_id = auth.uid()
  and exists (select 1 from telima.deliveries d
               where d.id = delivery_id
                 and (d.customer_id = auth.uid() or d.driver_id = auth.uid() or telima.is_staff())
                 and d.status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff', 'handed_over')));
create policy messages_mark_read on telima.messages for update
  using (telima.can_access_delivery(delivery_id) and sender_id <> auth.uid())
  with check (telima.can_access_delivery(delivery_id));
create policy notifications_read on telima.notifications for select using (user_id = auth.uid());
create policy notifications_update on telima.notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy device_tokens_own on telima.device_tokens for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy support_read on telima.support_requests for select using (user_id = auth.uid() or telima.is_staff());
create policy support_insert on telima.support_requests for insert
  with check ((auth.uid() is not null and user_id = auth.uid()) or (auth.uid() is null and user_id is null and phone is not null));
create policy support_staff_update on telima.support_requests for update using (telima.is_staff()) with check (telima.is_staff());
create policy pwd_reset_staff on telima.password_reset_requests for select using (telima.is_admin());
create policy admin_logs_read on telima.admin_logs for select using (telima.is_admin());
