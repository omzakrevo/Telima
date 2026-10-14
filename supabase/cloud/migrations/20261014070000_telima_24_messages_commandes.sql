-- Telima 24 : messages automatiques (SMS et WhatsApp) à la nouvelle commande, au livreur et au client.
-- Les SMS passent par la passerelle SMSBus existante (telima.send_sms). WhatsApp passe par l'API WhatsApp Cloud (Meta).
-- Les identifiants restent en base, dans une table sans aucune politique : jamais lisibles par les applications.
-- Tout est désactivé par défaut : l'administrateur active les messages dans « Paramètres ».

-- ─────────────────────────────────────────────────────────────
-- 1. Passerelle WhatsApp (API Cloud de Meta)
-- ─────────────────────────────────────────────────────────────
create table if not exists telima.whatsapp_gateway (
  id              int primary key default 1 check (id = 1),
  phone_number_id text,
  access_token    text,
  template_name   text,                       -- modèle de message approuvé par Meta (1 variable : le texte)
  template_lang   text not null default 'fr',
  api_version     text not null default 'v21.0',
  updated_at      timestamptz not null default now()
);
alter table telima.whatsapp_gateway enable row level security;   -- aucune politique : réservé au serveur
insert into telima.whatsapp_gateway(id) values (1) on conflict do nothing;

create table if not exists telima.whatsapp_outbox (
  id         bigint generated always as identity primary key,
  phone      text not null,
  body       text not null,
  purpose    text not null default 'info',
  request_id bigint,
  status     text not null default 'queued',   -- queued | sent | failed
  response   text,
  created_at timestamptz not null default now()
);
alter table telima.whatsapp_outbox enable row level security;
create policy whatsapp_outbox_admin on telima.whatsapp_outbox for select using (telima.is_admin());
grant select on telima.whatsapp_outbox to authenticated;

-- Envoie un message WhatsApp (interne). Sans passerelle configurée, ne fait rien et renvoie false.
create or replace function telima.send_whatsapp(p_phone text, p_body text, p_purpose text default 'info')
returns boolean language plpgsql security definer set search_path = telima, public as $$
declare
  g telima.whatsapp_gateway;
  v_to text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_text text := left(regexp_replace(coalesce(p_body, ''), '\s+', ' ', 'g'), 900);
  v_id bigint; v_req bigint; v_payload jsonb;
begin
  select * into g from telima.whatsapp_gateway where id = 1;
  if coalesce(g.phone_number_id, '') = '' or coalesce(g.access_token, '') = '' or length(v_to) < 8 then return false; end if;
  if coalesce(g.template_name, '') <> '' then
    v_payload := jsonb_build_object('messaging_product', 'whatsapp', 'to', v_to, 'type', 'template',
      'template', jsonb_build_object('name', g.template_name, 'language', jsonb_build_object('code', g.template_lang),
        'components', jsonb_build_array(jsonb_build_object('type', 'body',
          'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_text))))));
  else
    -- sans modèle : message libre (accepté par WhatsApp seulement si le destinataire a écrit dans les dernières 24 h)
    v_payload := jsonb_build_object('messaging_product', 'whatsapp', 'to', v_to, 'type', 'text',
      'text', jsonb_build_object('body', v_text));
  end if;
  insert into telima.whatsapp_outbox(phone, body, purpose) values (v_to, v_text, p_purpose) returning id into v_id;
  select net.http_post(
           url := 'https://graph.facebook.com/' || g.api_version || '/' || g.phone_number_id || '/messages',
           body := v_payload,
           headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || g.access_token),
           timeout_milliseconds := 15000) into v_req;
  update telima.whatsapp_outbox set request_id = v_req where id = v_id;
  return true;
end $$;
revoke all on function telima.send_whatsapp(text, text, text) from public, anon, authenticated;

create or replace function telima._whatsapp_refresh() returns void language plpgsql security definer set search_path = telima, public as $$
begin
  update telima.whatsapp_outbox o
     set status = case when r.status_code between 200 and 299 then 'sent' else 'failed' end,
         response = left(coalesce(r.content, r.error_msg, 'HTTP ' || r.status_code), 300)
    from net._http_response r
   where o.request_id = r.id and o.status = 'queued';
end $$;
revoke all on function telima._whatsapp_refresh() from public, anon, authenticated;

create or replace function telima.admin_set_whatsapp_gateway(p_phone_number_id text, p_access_token text, p_template text, p_lang text default null)
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  update telima.whatsapp_gateway set
    phone_number_id = case when coalesce(trim(p_phone_number_id), '') = '' then phone_number_id else trim(p_phone_number_id) end,
    access_token    = case when coalesce(trim(p_access_token), '') = '' then access_token else trim(p_access_token) end,
    template_name   = trim(coalesce(p_template, '')),
    template_lang   = coalesce(nullif(trim(p_lang), ''), template_lang),
    updated_at = now()
   where id = 1;
end $$;

create or replace function telima.admin_whatsapp_status() returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare g telima.whatsapp_gateway;
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  perform telima._whatsapp_refresh();
  select * into g from telima.whatsapp_gateway where id = 1;
  return jsonb_build_object(
    'configured', coalesce(g.phone_number_id, '') <> '' and coalesce(g.access_token, '') <> '',
    'phone_number_id', g.phone_number_id,
    'token_hint', case when coalesce(g.access_token, '') = '' then null else '…' || right(g.access_token, 4) end,
    'template', coalesce(g.template_name, ''),
    'lang', g.template_lang,
    'sent', (select count(*) from telima.whatsapp_outbox where status = 'sent'),
    'failed', (select count(*) from telima.whatsapp_outbox where status = 'failed'),
    'recent', coalesce((select jsonb_agg(x) from (select phone, purpose, status, response, created_at from telima.whatsapp_outbox order by id desc limit 10) x), '[]'::jsonb));
end $$;

create or replace function telima.admin_send_test_whatsapp(p_phone text) returns boolean language plpgsql security definer set search_path = telima, public as $$
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  return telima.send_whatsapp(p_phone, 'Telima : message de test WhatsApp. La passerelle fonctionne.', 'test');
end $$;

-- ─────────────────────────────────────────────────────────────
-- 2. Réglages des messages automatiques
-- ─────────────────────────────────────────────────────────────
-- { enabled, sms, whatsapp, admin, driver, client, driver_requests, admin_phone }
create or replace function telima._messaging_settings() returns jsonb language sql stable security definer set search_path = telima, public as $$
  select '{"enabled":false,"sms":true,"whatsapp":false,"admin":true,"driver":true,"client":true,"driver_requests":false,"admin_phone":""}'::jsonb
         || coalesce(telima.get_setting('order_messaging', '{}'::jsonb), '{}'::jsonb)
$$;
revoke all on function telima._messaging_settings() from public, anon, authenticated;

create or replace function telima.admin_get_order_messaging() returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  return telima._messaging_settings();
end $$;

create or replace function telima.admin_set_order_messaging(p_settings jsonb) returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare v jsonb;
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  v := telima._messaging_settings() || coalesce(p_settings, '{}'::jsonb);
  insert into telima.app_settings(key, value) values ('order_messaging', v)
    on conflict (key) do update set value = excluded.value;
  return v;
end $$;

-- ─────────────────────────────────────────────────────────────
-- 3. Envoi à un utilisateur par les canaux activés (ne lève jamais d'erreur)
-- ─────────────────────────────────────────────────────────────
create or replace function telima._message_to(p_phone text, p_body text, p_purpose text, p_settings jsonb)
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  if coalesce(p_phone, '') = '' then return; end if;
  begin
    if (p_settings ->> 'sms')::boolean and coalesce(telima.get_setting('sms_mode', '"simulation"') #>> '{}', 'simulation') = 'live' then
      perform telima.send_sms(p_phone, p_body, p_purpose);
    end if;
  exception when others then null;
  end;
  begin
    if (p_settings ->> 'whatsapp')::boolean then
      perform telima.send_whatsapp(p_phone, p_body, p_purpose);
    end if;
  exception when others then null;
  end;
end $$;
revoke all on function telima._message_to(text, text, text, jsonb) from public, anon, authenticated;

-- Une notification de l'application devient aussi un SMS / WhatsApp pour les cas choisis :
--   administrateur : nouvelle commande · livreur : course acceptée (et nouvelles demandes si activé)
--   client : livreur trouvé, colis en route, livraison terminée
create or replace function telima.tg_notification_messaging() returns trigger
language plpgsql security definer set search_path = telima, public as $$
declare
  s jsonb := telima._messaging_settings();
  v_role text; v_phone text; v_text text; v_extra text;
begin
  if not (s ->> 'enabled')::boolean then return new; end if;
  if new.type not in ('new_order', 'new_request', 'delivery_status') then return new; end if;
  select role::text, phone into v_role, v_phone from telima.users where id = new.user_id;
  if v_phone is null then return new; end if;

  if new.type = 'new_order' and v_role = 'admin' and (s ->> 'admin')::boolean then
    v_text := 'Telima - Nouvelle commande ' || new.body;
    perform telima._message_to(v_phone, v_text, 'new_order', s);
    v_extra := nullif(trim(s ->> 'admin_phone'), '');
    -- numéro supplémentaire de l'administrateur : une seule fois, même s'il y a plusieurs comptes admin
    if v_extra is not null and new.user_id = (select id from telima.users where role = 'admin' order by created_at limit 1) then
      perform telima._message_to(v_extra, v_text, 'new_order', s);
    end if;
  elsif new.type = 'delivery_status' and v_role = 'driver' and new.title = 'Course acceptée' and (s ->> 'driver')::boolean then
    perform telima._message_to(v_phone, 'Telima - ' || new.title || ' : ' || new.body, 'driver_assigned', s);
  elsif new.type = 'new_request' and v_role = 'driver' and (s ->> 'driver_requests')::boolean then
    perform telima._message_to(v_phone, 'Telima - Nouvelle demande : ' || new.body, 'driver_request', s);
  elsif new.type = 'delivery_status' and v_role = 'client' and (s ->> 'client')::boolean
        and new.body in ('Un livreur a accepté votre commande.', 'Votre colis est en route.', 'Livraison terminée.') then
    perform telima._message_to(v_phone, 'Telima ' || new.title || ' : ' || new.body, 'client_status', s);
  end if;
  return new;
exception when others then
  return new;   -- un échec de message ne doit jamais bloquer la commande
end $$;
revoke all on function telima.tg_notification_messaging() from public, anon, authenticated;

grant execute on function telima.admin_set_whatsapp_gateway(text, text, text, text), telima.admin_whatsapp_status(),
  telima.admin_send_test_whatsapp(text), telima.admin_get_order_messaging(), telima.admin_set_order_messaging(jsonb) to authenticated;

-- Le déclencheur est créé dans une migration séparée (telima_24b) : un CREATE TRIGGER groupé bloque l'outil de migration.
create trigger trg_notification_messaging after insert on telima.notifications
  for each row execute function telima.tg_notification_messaging();
