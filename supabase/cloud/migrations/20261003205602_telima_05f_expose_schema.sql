-- Migration appliquée sur le projet Supabase cloud : telima_05f_expose_schema

alter role authenticator set pgrst.db_schemas = 'public, graphql_public, telima';
notify pgrst, 'reload config';
