-- Migration appliquée sur le projet Supabase cloud : telima_05e_function_grants

grant execute on function telima.is_admin(), telima.is_staff(), telima.current_user_role(),
  telima.can_access_delivery(uuid), telima.is_business_member(uuid, telima.member_role[]) to anon, authenticated;
grant execute on function telima.quote_delivery(double precision, double precision, double precision, double precision,
  telima.vehicle_type, telima.package_size, boolean, numeric, telima.package_category, numeric, boolean) to anon, authenticated;
grant execute on function telima.request_password_reset(text) to anon, authenticated;
grant execute on function
  telima.update_my_profile(text, uuid, text),
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
grant execute on all functions in schema telima to service_role;
