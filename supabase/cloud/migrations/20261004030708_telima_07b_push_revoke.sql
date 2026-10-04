-- Migration appliquée sur le projet Supabase cloud : telima_07b_push_revoke

revoke all on telima.push_secrets from anon, authenticated;
