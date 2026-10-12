-- Le téléphone d'un restaurant ou d'une boutique est facultatif : un champ vide ne doit plus faire échouer la création.
-- (telima.normalize_phone('') lève une erreur ; on ne l'appelle que si un numéro est saisi.)
-- Appliquée en production sous le nom telima_16_telephone_facultatif.
do $$
declare
  v_old text := 'nullif(telima.normalize_phone(coalesce(p->>''phone'', '''')), '''')';
  v_new text := 'case when coalesce(trim(p->>''phone''), '''') <> '''' then telima.normalize_phone(p->>''phone'') end';
  v_def text; v_fn text;
begin
  foreach v_fn in array array['telima.register_shop(jsonb)', 'telima.register_restaurant(jsonb)'] loop
    v_def := pg_get_functiondef(v_fn::regprocedure);
    if position(v_old in v_def) > 0 then execute replace(v_def, v_old, v_new); end if;
  end loop;
end $$;
