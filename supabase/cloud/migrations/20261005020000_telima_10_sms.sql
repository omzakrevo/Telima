-- Envoi de SMS réels via SMSBus (3MI) depuis la base, avec pg_net. L'identifiant API reste en base (table non lisible par les clients).
create extension if not exists pg_net;

create table if not exists telima.sms_gateway (
  id        int primary key default 1 check (id = 1),
  api_id    text,
  sender_id text not null default 'TELIMA',
  base_url  text not null default 'https://www.lesmsbus.com:7170/ines.smsbus',
  updated_at timestamptz not null default now()
);
alter table telima.sms_gateway enable row level security;   -- aucune politique : réservé au serveur
insert into telima.sms_gateway(id) values (1) on conflict do nothing;

create table if not exists telima.sms_outbox (
  id         bigint generated always as identity primary key,
  phone      text not null,
  body       text not null,
  purpose    text not null default 'info',
  request_id bigint,
  status     text not null default 'queued',   -- queued | sent | failed
  response   text,
  created_at timestamptz not null default now()
);
alter table telima.sms_outbox enable row level security;
create policy sms_outbox_admin on telima.sms_outbox for select using (telima.is_admin());
grant select on telima.sms_outbox to authenticated;

create or replace function telima._urlenc(t text) returns text language plpgsql immutable as $$
declare b bytea := convert_to(coalesce(t, ''), 'UTF8'); r text := ''; c int; i int;
begin
  for i in 0 .. length(b) - 1 loop
    c := get_byte(b, i);
    if (c between 48 and 57) or (c between 65 and 90) or (c between 97 and 122) or c in (45, 46, 95, 126) then r := r || chr(c);
    else r := r || '%' || upper(lpad(to_hex(c), 2, '0')); end if;
  end loop;
  return r;
end $$;

-- Envoie un SMS (interne). Sans passerelle configurée, ne fait rien et renvoie false.
create or replace function telima.send_sms(p_phone text, p_body text, p_purpose text default 'info')
returns boolean language plpgsql security definer set search_path = telima, public as $$
declare g telima.sms_gateway; v_to text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'); v_id bigint; v_req bigint;
begin
  select * into g from telima.sms_gateway where id = 1;
  if g.api_id is null or g.api_id = '' or length(v_to) < 8 then return false; end if;
  insert into telima.sms_outbox(phone, body, purpose) values (v_to, left(p_body, 640), p_purpose) returning id into v_id;
  select net.http_get(url := g.base_url || '/smsbusMt?to=' || v_to || '&from=' || telima._urlenc(g.sender_id)
                          || '&id=' || telima._urlenc(g.api_id) || '&text=' || telima._urlenc(left(p_body, 640)),
                      timeout_milliseconds := 15000) into v_req;
  update telima.sms_outbox set request_id = v_req where id = v_id;
  return true;
end $$;
revoke all on function telima.send_sms(text, text, text) from public, anon, authenticated;

-- Met à jour le statut des SMS à partir des réponses SMSBus (0000|OK-… = envoyé).
create or replace function telima._sms_refresh() returns void language plpgsql security definer set search_path = telima, public as $$
begin
  update telima.sms_outbox o
     set status = case when r.status_code = 200 and r.content like '0000%' then 'sent' else 'failed' end,
         response = left(coalesce(r.content, r.error_msg, 'HTTP ' || r.status_code), 300)
    from net._http_response r
   where o.request_id = r.id and o.status = 'queued';
end $$;
revoke all on function telima._sms_refresh() from public, anon, authenticated;

create or replace function telima.admin_set_sms_gateway(p_api_id text, p_sender text, p_base_url text default null)
returns void language plpgsql security definer set search_path = telima, public as $$
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  if p_sender is not null and length(trim(p_sender)) > 11 then raise exception 'Identifiant d''expéditeur : 11 caractères maximum' using errcode = 'P0001'; end if;
  update telima.sms_gateway set
    api_id = case when coalesce(trim(p_api_id), '') = '' then api_id else trim(p_api_id) end,
    sender_id = coalesce(nullif(trim(p_sender), ''), sender_id),
    base_url = coalesce(nullif(trim(p_base_url), ''), base_url),
    updated_at = now()
   where id = 1;
end $$;

create or replace function telima.admin_sms_status() returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare g telima.sms_gateway;
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  perform telima._sms_refresh();
  select * into g from telima.sms_gateway where id = 1;
  return jsonb_build_object('configured', coalesce(g.api_id, '') <> '', 'sender_id', g.sender_id,
    'api_id_hint', case when coalesce(g.api_id, '') = '' then null else '…' || right(g.api_id, 4) end,
    'sent', (select count(*) from telima.sms_outbox where status = 'sent'),
    'failed', (select count(*) from telima.sms_outbox where status = 'failed'),
    'recent', coalesce((select jsonb_agg(x) from (select phone, purpose, status, response, created_at from telima.sms_outbox order by id desc limit 10) x), '[]'::jsonb));
end $$;

-- Envoi de test à un numéro saisi par l'administrateur.
create or replace function telima.admin_send_test_sms(p_phone text) returns boolean language plpgsql security definer set search_path = telima, public as $$
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  return telima.send_sms(p_phone, 'Telima : SMS de test. La passerelle fonctionne.', 'test');
end $$;

-- Solde du compte SMSBus (résultat lu ensuite dans admin_sms_balance_result).
create or replace function telima.admin_sms_balance_request() returns bigint language plpgsql security definer set search_path = telima, public as $$
declare g telima.sms_gateway;
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  select * into g from telima.sms_gateway where id = 1;
  if coalesce(g.api_id, '') = '' then raise exception 'Passerelle non configurée' using errcode = 'P0001'; end if;
  return net.http_get(url := g.base_url || '/Balance?id=' || telima._urlenc(g.api_id), timeout_milliseconds := 15000);
end $$;

create or replace function telima.admin_sms_balance_result(p_request bigint) returns text language plpgsql security definer set search_path = telima, public as $$
declare v text;
begin
  if not telima.is_admin() then raise exception 'Réservé à l''administrateur' using errcode = '42501'; end if;
  select left(coalesce(content, error_msg, 'HTTP ' || status_code), 100) into v from net._http_response where id = p_request;
  return v;   -- null tant que la réponse n'est pas arrivée
end $$;

grant execute on function telima.admin_set_sms_gateway(text, text, text), telima.admin_sms_status(), telima.admin_send_test_sms(text),
  telima.admin_sms_balance_request(), telima.admin_sms_balance_result(bigint) to authenticated;

-- Récupération de compte : envoi réel du code en mode « live ».
create or replace function telima.request_password_reset(p_phone text)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare
  v_phone text := telima.normalize_phone(p_phone);
  v_user telima.users;
  v_code text := lpad((floor(random() * 1000000))::int::text, 6, '0');
  v_sim boolean := coalesce(telima.get_setting('sms_mode', '"simulation"') #>> '{}', 'simulation') = 'simulation';
begin
  select * into v_user from telima.users where phone = v_phone;
  if v_user.id is not null and v_user.is_active then
    if (select count(*) from telima.password_reset_requests
         where user_id = v_user.id and created_at > now() - interval '1 hour') >= 3 then
      raise exception 'Trop de demandes. Réessayez dans une heure.' using errcode = 'P0001';
    end if;
    insert into telima.password_reset_requests(user_id, phone, code_hash, code_plain, expires_at)
    values (v_user.id, v_phone, extensions.crypt(v_code, extensions.gen_salt('bf')), case when v_sim then v_code end, now() + interval '30 minutes');
    if v_sim then
      perform telima.notify_staff('password_reset', 'Demande de récupération de compte',
        v_user.full_name || ' (' || v_phone || ') — code : ' || v_code, jsonb_build_object('user_id', v_user.id));
    elsif not telima.send_sms(v_phone, 'Telima : votre code de récupération est ' || v_code || ' (valable 30 min). Ne le partagez pas.', 'password_reset') then
      perform telima.notify_staff('password_reset', 'SMS non envoyé (passerelle non configurée)',
        v_user.full_name || ' (' || v_phone || ') a demandé un code de récupération.', jsonb_build_object('user_id', v_user.id));
    end if;
  end if;
  return jsonb_build_object('sent', true, 'simulation', v_sim);
end $$;
