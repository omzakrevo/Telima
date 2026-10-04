-- Identifiants Google (publics par nature : ils apparaissent dans le code de la page) :
-- ga_id = mesure Google Analytics 4 (G-XXXXXXXXXX), adsense_id = éditeur AdSense (ca-pub-XXXXXXXXXXXXXXXX),
-- ad_slot = identifiant du bloc publicitaire, ads_enabled = afficher les publicités.
insert into telima.app_settings (key, value, description, is_public)
values ('google', '{"ga_id":"","adsense_id":"","ad_slot":"","ads_enabled":false}'::jsonb,
        'Google Analytics et AdSense (site web)', true)
on conflict (key) do nothing;
