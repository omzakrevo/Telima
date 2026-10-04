-- Migration appliquée sur le projet Supabase cloud : telima_08l_grants

revoke all on function telima._match_payment_sms(uuid, bigint), telima._relay_sms(text, text, text, timestamptz, text, text, integer, text, text) from public, anon, authenticated;
grant execute on function telima._relay_sms(text, text, text, timestamptz, text, text, integer, text, text) to service_role;
revoke all on function telima.declare_manual_payment(uuid, text, text), telima.admin_reject_payment(uuid, text), telima.admin_pending_counts(),
  telima.admin_enable_sms_relay(text), telima.admin_disable_sms_relay(text), telima.admin_sms_relays(),
  telima.quote_service(text, float8, float8, float8, float8, telima.vehicle_type, numeric), telima.create_errand(jsonb), telima.create_ride(jsonb),
  telima.driver_set_purchase(uuid, integer, text, text), telima.settle_purchase(uuid, text), telima.set_driver_services(text[]),
  telima.get_available_requests_v2() from public, anon;
grant execute on function telima.declare_manual_payment(uuid, text, text), telima.admin_reject_payment(uuid, text), telima.admin_pending_counts(),
  telima.admin_enable_sms_relay(text), telima.admin_disable_sms_relay(text), telima.admin_sms_relays(),
  telima.quote_service(text, float8, float8, float8, float8, telima.vehicle_type, numeric), telima.create_errand(jsonb), telima.create_ride(jsonb),
  telima.driver_set_purchase(uuid, integer, text, text), telima.settle_purchase(uuid, text), telima.set_driver_services(text[]),
  telima.get_available_requests_v2() to authenticated, service_role;
grant execute on function telima.quote_service(text, float8, float8, float8, float8, telima.vehicle_type, numeric) to anon;
