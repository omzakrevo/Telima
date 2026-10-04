-- Migration appliquée sur le projet Supabase cloud : telima_08f_sms_relay

-- Active le relais des SMS Mobile Money sur le téléphone de l'administrateur (renvoie la clé du téléphone)
create or replace function telima.admin_enable_sms_relay(p_label text default null)
returns text language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin(); v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  insert into telima.sms_relays(token, user_id, label) values (v_token, v_uid, coalesce(nullif(trim(p_label), ''), 'Téléphone administrateur'));
  perform telima.log_admin_action('sms_relay_enable', 'sms_relays', v_uid::text, '{}'::jsonb);
  return v_token;
end $$;

create or replace function telima.admin_disable_sms_relay(p_token text)
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_admin();
begin
  update telima.sms_relays set revoked_at = now() where token = p_token and revoked_at is null;
end $$;

create or replace function telima.admin_sms_relays()
returns jsonb language plpgsql stable security definer set search_path = telima, public as $$
begin
  perform telima.require_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('label', r.label, 'owner', u.full_name, 'created_at', r.created_at,
                                                       'last_seen', r.last_seen) order by r.created_at desc)
                     from telima.sms_relays r join telima.users u on u.id = r.user_id where r.revoked_at is null), '[]'::jsonb);
end $$;

-- Appelée par la fonction Edge telima-sms-relay (service_role) pour chaque SMS Mobile Money reçu
create or replace function telima._relay_sms(p_token text, p_sender text, p_body text, p_received_at timestamptz,
  p_operator text, p_direction text, p_amount integer, p_phone text, p_ref text)
returns jsonb language plpgsql security definer set search_path = telima, public as $$
declare v_relay telima.sms_relays; v_id bigint; v_match bigint; v_phone text;
begin
  select * into v_relay from telima.sms_relays where token = p_token and revoked_at is null;
  if v_relay.token is null then raise exception 'Relais inconnu' using errcode = '42501'; end if;
  update telima.sms_relays set last_seen = now() where token = p_token;
  begin v_phone := telima.normalize_phone(p_phone); exception when others then v_phone := null; end;
  insert into telima.mm_sms(sender, body, received_at, operator, direction, amount, counterpart_phone, txn_ref, relay_user, hash)
  values (left(p_sender, 60), left(p_body, 1000), coalesce(p_received_at, now()), p_operator,
          coalesce(p_direction, 'unknown'), p_amount, v_phone, nullif(upper(trim(coalesce(p_ref, ''))), ''), v_relay.user_id,
          md5(coalesce(p_sender, '') || '|' || coalesce(p_body, '')))
  on conflict (hash) do nothing returning id into v_id;
  if v_id is null then return jsonb_build_object('duplicate', true); end if;
  if coalesce(p_direction, 'unknown') <> 'out' then
    v_match := telima._match_payment_sms(null, v_id);
    if v_match is null then
      perform telima.notify_staff('mm_sms', 'SMS ' || coalesce(p_operator, 'Mobile Money') || ' reçu',
        coalesce(p_amount || ' FCFA', 'Montant ?') || coalesce(' de ' || v_phone, '') || coalesce(' · réf. ' || upper(p_ref), '')
          || ' — aucun paiement déclaré correspondant pour l''instant.',
        jsonb_build_object('sms_id', v_id));
    end if;
  end if;
  return jsonb_build_object('id', v_id, 'matched', v_match is not null);
end $$;
