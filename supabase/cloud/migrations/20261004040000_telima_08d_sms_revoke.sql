-- Migration appliquée sur le projet Supabase cloud : telima_08d_sms_revoke

revoke all on telima.sms_relays from anon, authenticated;
