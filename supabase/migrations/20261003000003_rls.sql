-- =====================================================================
-- TELIMA — Migration 3 : Row Level Security, droits d'exécution,
-- stockage sécurisé et temps réel
-- =====================================================================

-- ---------------------------------------------------------------------
-- Activation de la RLS sur toutes les tables
-- ---------------------------------------------------------------------
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
-- Les fonctions SECURITY DEFINER (propriétaire des tables) contournent la RLS ;
-- elle s'applique aux rôles anon et authenticated utilisés par l'application.

-- ---------------------------------------------------------------------
-- Configuration publique (lecture) / écriture administrateur
-- ---------------------------------------------------------------------
create policy settings_read on telima.app_settings for select
  using (is_public or telima.is_staff());
create policy settings_admin_write on telima.app_settings for all
  using (telima.is_admin()) with check (telima.is_admin());

create policy cities_read on telima.cities for select using (is_active or telima.is_staff());
create policy cities_admin on telima.cities for all using (telima.is_admin()) with check (telima.is_admin());

create policy zones_read on telima.delivery_zones for select using (is_active or telima.is_staff());
create policy zones_admin on telima.delivery_zones for all using (telima.is_admin()) with check (telima.is_admin());

create policy pricing_read on telima.pricing_rules for select using (is_active or telima.is_staff());
create policy pricing_admin on telima.pricing_rules for all using (telima.is_admin()) with check (telima.is_admin());

-- ---------------------------------------------------------------------
-- Utilisateurs
-- ---------------------------------------------------------------------
create policy users_self_read on telima.users for select using (id = auth.uid() or telima.is_staff());
create policy users_self_update on telima.users for update
  using (id = auth.uid() or telima.is_admin()) with check (id = auth.uid() or telima.is_admin());

create policy customers_read on telima.customers for select using (user_id = auth.uid() or telima.is_staff());
create policy customers_update on telima.customers for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Livreurs : lecture de son propre profil ; écritures via fonctions uniquement
create policy drivers_read on telima.drivers for select using (user_id = auth.uid() or telima.is_staff());
create policy drivers_admin on telima.drivers for update using (telima.is_admin()) with check (telima.is_admin());

create policy vehicles_read on telima.vehicles for select using (driver_id = auth.uid() or telima.is_staff());
create policy vehicles_admin on telima.vehicles for all using (telima.is_admin()) with check (telima.is_admin());

-- ---------------------------------------------------------------------
-- Comptes professionnels
-- ---------------------------------------------------------------------
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
create policy business_members_delete on telima.business_members for delete
  using (role <> 'owner' and (telima.is_business_member(business_id, array['owner','manager']::telima.member_role[]) or user_id = auth.uid()));

create policy saved_addresses_all on telima.saved_addresses for all
  using (user_id = auth.uid() or (business_id is not null and telima.is_business_member(business_id)))
  with check ((user_id = auth.uid() and business_id is null)
              or (business_id is not null and telima.is_business_member(business_id)));

-- ---------------------------------------------------------------------
-- Livraisons : un client ne voit que ses commandes, un livreur que ses courses
-- ---------------------------------------------------------------------
create policy deliveries_read on telima.deliveries for select using (
  customer_id = auth.uid()
  or driver_id = auth.uid()
  or (business_id is not null and telima.is_business_member(business_id))
  or telima.is_staff()
);
create policy deliveries_staff_update on telima.deliveries for update
  using (telima.is_staff()) with check (telima.is_staff());

create policy batches_read on telima.delivery_batches for select using (
  customer_id = auth.uid() or driver_id = auth.uid()
  or (business_id is not null and telima.is_business_member(business_id)) or telima.is_staff());

-- delivery_secrets : aucune politique → inaccessible directement (lecture via get_delivery_otp)

create policy status_history_read on telima.delivery_status_history for select
  using (telima.can_access_delivery(delivery_id));

create policy locations_read on telima.delivery_locations for select
  using (telima.can_access_delivery(delivery_id));

create policy declines_read on telima.delivery_declines for select
  using (driver_id = auth.uid() or telima.is_staff());

-- ---------------------------------------------------------------------
-- Paiements, portefeuilles, retraits
-- ---------------------------------------------------------------------
create policy payments_read on telima.payments for select
  using (payer_id = auth.uid() or telima.is_staff()
         or (delivery_id is not null and exists (select 1 from telima.deliveries d where d.id = delivery_id and d.driver_id = auth.uid())));

create policy wallets_read on telima.wallets for select using (user_id = auth.uid() or telima.is_staff());

create policy wallet_tx_read on telima.wallet_transactions for select
  using (exists (select 1 from telima.wallets w where w.id = wallet_id and (w.user_id = auth.uid() or telima.is_staff())));

create policy withdrawals_read on telima.withdrawals for select using (user_id = auth.uid() or telima.is_staff());

-- ---------------------------------------------------------------------
-- Évaluations, messages, notifications
-- ---------------------------------------------------------------------
create policy ratings_read on telima.ratings for select
  using (customer_id = auth.uid() or driver_id = auth.uid() or telima.is_staff());

create policy messages_read on telima.messages for select using (telima.can_access_delivery(delivery_id));
create policy messages_insert on telima.messages for insert with check (
  sender_id = auth.uid()
  and exists (select 1 from telima.deliveries d
               where d.id = delivery_id
                 and (d.customer_id = auth.uid() or d.driver_id = auth.uid() or telima.is_staff())
                 and d.status in ('assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff', 'handed_over'))
);
create policy messages_mark_read on telima.messages for update
  using (telima.can_access_delivery(delivery_id) and sender_id <> auth.uid())
  with check (telima.can_access_delivery(delivery_id));

create policy notifications_read on telima.notifications for select using (user_id = auth.uid());
create policy notifications_update on telima.notifications for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notifications_delete on telima.notifications for delete using (user_id = auth.uid());

create policy device_tokens_own on telima.device_tokens for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Support et journal
-- ---------------------------------------------------------------------
create policy support_read on telima.support_requests for select using (user_id = auth.uid() or telima.is_staff());
create policy support_insert on telima.support_requests for insert
  with check ((auth.uid() is not null and user_id = auth.uid()) or (auth.uid() is null and user_id is null and phone is not null));
create policy support_staff_update on telima.support_requests for update using (telima.is_staff()) with check (telima.is_staff());

create policy pwd_reset_staff on telima.password_reset_requests for select using (telima.is_admin());

create policy admin_logs_read on telima.admin_logs for select using (telima.is_admin());

-- ---------------------------------------------------------------------
-- Droits sur les tables (la RLS filtre ensuite les lignes)
-- ---------------------------------------------------------------------
revoke all on all tables in schema telima from anon, authenticated;
revoke all on all sequences in schema telima from anon, authenticated;

grant select on telima.app_settings, telima.cities, telima.delivery_zones, telima.pricing_rules to anon, authenticated;
grant insert on telima.support_requests to anon;

grant select on all tables in schema telima to authenticated;
revoke select on telima.delivery_secrets, telima.code_counters from authenticated;
grant update (full_name, city_id, avatar_url, is_active, deactivated_at) on telima.users to authenticated;
grant update (role, phone) on telima.users to authenticated;  -- contrôlé par la RLS + tg_users_guard (admin uniquement)
grant update (default_payment_method) on telima.customers to authenticated;
grant update on telima.drivers, telima.vehicles to authenticated;              -- RLS : admin uniquement
grant insert, update, delete on telima.vehicles to authenticated;              -- RLS : admin uniquement
grant insert, update, delete on telima.app_settings, telima.cities, telima.delivery_zones, telima.pricing_rules to authenticated;
grant update on telima.deliveries to authenticated;                            -- RLS : personnel uniquement
grant update (name, type, phone, address, lat, lng, city_id, is_active) on telima.business_accounts to authenticated;
grant delete on telima.business_members to authenticated;
grant select, insert, update, delete on telima.saved_addresses to authenticated;
grant insert on telima.messages to authenticated;
grant update (read_at) on telima.messages to authenticated;
grant update (read_at) on telima.notifications to authenticated;
grant delete on telima.notifications to authenticated;
grant select, insert, update, delete on telima.device_tokens to authenticated;
grant insert on telima.support_requests to authenticated;
grant update (status, admin_reply) on telima.support_requests to authenticated;  -- RLS : personnel
grant usage on all sequences in schema telima to authenticated;

-- ---------------------------------------------------------------------
-- Droits d'exécution des fonctions : tout est fermé, puis ouvert au cas par cas
-- ---------------------------------------------------------------------
revoke execute on all functions in schema telima from public, anon, authenticated;

-- Fonctions d'aide utilisées par la RLS
grant execute on function telima.is_admin(), telima.is_staff(), telima.current_user_role(),
  telima.can_access_delivery(uuid), telima.is_business_member(uuid, telima.member_role[]) to anon, authenticated;

-- Visiteurs : devis et récupération de compte
grant execute on function telima.quote_delivery(double precision, double precision, double precision, double precision,
  telima.vehicle_type, telima.package_size, boolean, numeric, telima.package_category, numeric, boolean) to anon, authenticated;
grant execute on function telima.request_password_reset(text) to anon, authenticated;

-- Utilisateurs connectés
grant execute on function
  telima.update_my_profile(text, uuid, text),
  telima.deactivate_my_account(),
  telima.register_device_token(text, text),
  telima.mark_notifications_read(bigint[]),
  telima.create_delivery(jsonb),
  telima.create_delivery_batch(jsonb),
  telima.confirm_simulated_payment(uuid),
  telima.mark_payment_failed(uuid, text),
  telima.change_payment_method(uuid, telima.payment_method),
  telima.request_wallet_topup(integer, telima.payment_method),
  telima.submit_driver_application(jsonb),
  telima.set_driver_online(boolean, double precision, double precision),
  telima.get_available_requests(),
  telima.accept_delivery(uuid),
  telima.decline_delivery(uuid),
  telima.driver_advance_status(uuid, telima.delivery_status, double precision, double precision),
  telima.driver_release_delivery(uuid, text),
  telima.driver_update_location(double precision, double precision, double precision, double precision),
  telima.complete_delivery(uuid, text, text, text, text, double precision, double precision),
  telima.cancel_delivery(uuid, text),
  telima.get_delivery_driver(uuid),
  telima.get_delivery_otp(uuid),
  telima.rate_delivery(uuid, int, text),
  telima.get_driver_earnings(),
  telima.request_withdrawal(integer, telima.payment_method, text),
  telima.create_business_account(jsonb),
  telima.add_business_member(uuid, text, telima.member_role),
  telima.get_business_summary(uuid, timestamptz, timestamptz),
  -- administration (contrôle du rôle à l'intérieur de chaque fonction)
  telima.admin_create_delivery(jsonb),
  telima.admin_assign_delivery(uuid, uuid),
  telima.admin_set_driver_status(uuid, telima.driver_status, text),
  telima.admin_set_user_active(uuid, boolean),
  telima.admin_set_user_role(uuid, telima.user_role),
  telima.admin_process_withdrawal(uuid, boolean, text, text),
  telima.admin_wallet_adjust(uuid, integer, text),
  telima.admin_confirm_payment(uuid, text),
  telima.admin_dashboard_stats(timestamptz, timestamptz),
  telima.admin_daily_stats(int),
  telima.admin_list_assignable_drivers(uuid)
to authenticated;

-- service_role uniquement (fonction Edge / webhooks fournisseurs)
grant execute on function telima.consume_password_reset(text, text), telima._confirm_payment(uuid, text) to service_role;

-- Les fonctions futures ne sont pas exécutables par défaut
alter default privileges in schema telima revoke execute on functions from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Stockage : compartiments et politiques (chemin = <uid>/<fichier>)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('telima-avatars', 'telima-avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('telima-package-photos', 'telima-package-photos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp']),
  ('telima-proofs', 'telima-proofs', false, 3145728, array['image/jpeg', 'image/png', 'image/webp']),
  ('telima-driver-documents', 'telima-driver-documents', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('telima-vehicle-photos', 'telima-vehicle-photos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy telima_storage_upload_own on storage.objects for insert to authenticated
  with check (bucket_id in ('telima-avatars', 'telima-package-photos', 'telima-proofs', 'telima-driver-documents', 'telima-vehicle-photos')
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy telima_storage_update_own on storage.objects for update to authenticated
  using (bucket_id like 'telima-%' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id like 'telima-%' and (storage.foldername(name))[1] = auth.uid()::text);

create policy telima_storage_delete_own on storage.objects for delete to authenticated
  using (bucket_id like 'telima-%' and (storage.foldername(name))[1] = auth.uid()::text);

create policy telima_storage_avatars_read on storage.objects for select
  using (bucket_id = 'telima-avatars');

create policy telima_storage_private_read on storage.objects for select to authenticated using (
  bucket_id in ('telima-package-photos', 'telima-proofs', 'telima-driver-documents', 'telima-vehicle-photos')
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or telima.is_staff()
    or (bucket_id = 'telima-package-photos' and exists (
          select 1 from telima.deliveries d where d.package_photo_path = name and telima.can_access_delivery(d.id)))
    or (bucket_id = 'telima-proofs' and exists (
          select 1 from telima.deliveries d
           where (d.proof_photo_path = name or d.proof_signature_path = name) and telima.can_access_delivery(d.id)))
  )
);

-- ---------------------------------------------------------------------
-- Temps réel (Supabase Realtime respecte la RLS)
-- ---------------------------------------------------------------------
alter publication supabase_realtime add table
  telima.deliveries, telima.delivery_locations, telima.messages, telima.notifications, telima.drivers;

-- service_role (fonctions Edge, scripts d'administration) : accès complet au schéma telima
grant all on all tables in schema telima to service_role;
grant all on all sequences in schema telima to service_role;
grant execute on all functions in schema telima to service_role;

-- Exposition du schéma telima à l'API REST (en plus des schémas existants)
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, telima';
notify pgrst, 'reload config';
