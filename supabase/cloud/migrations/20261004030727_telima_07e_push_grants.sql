-- Migration appliquée sur le projet Supabase cloud : telima_07e_push_grants

revoke all on function telima.admin_set_firebase(jsonb, jsonb), telima.admin_push_status(), telima.send_test_notification() from public, anon;
grant execute on function telima.admin_set_firebase(jsonb, jsonb), telima.admin_push_status(), telima.send_test_notification() to authenticated, service_role;
