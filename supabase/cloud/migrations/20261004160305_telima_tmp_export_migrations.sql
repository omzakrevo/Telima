-- Migration appliquée sur le projet Supabase cloud : telima_tmp_export_migrations

create or replace function telima.admin_export_migrations()
returns table (version text, name text, sql text)
language plpgsql stable security definer set search_path = telima, public as $$
begin
  perform telima.require_admin();
  return query select m.version::text, m.name::text, array_to_string(m.statements, E';\n\n')
    from supabase_migrations.schema_migrations m where m.name like 'telima%' order by m.version;
end $$;
revoke all on function telima.admin_export_migrations() from public, anon;
grant execute on function telima.admin_export_migrations() to authenticated;
