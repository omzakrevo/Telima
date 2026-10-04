-- Migration appliquée sur le projet Supabase cloud : telima_05a_revoke_functions

revoke execute on all functions in schema telima from public, anon, authenticated;
alter default privileges in schema telima revoke execute on functions from public, anon, authenticated;
