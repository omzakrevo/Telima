-- Migration appliquée sur le projet Supabase cloud : telima_08h_notify_triggers2

create or replace function telima.tg_rating_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_code text;
begin
  select code into v_code from telima.deliveries where id = new.delivery_id;
  perform telima.notify_user(new.driver_id, 'rating', 'Nouvelle évaluation : ' || repeat('★', new.stars) || repeat('☆', 5 - new.stars),
    coalesce(v_code, '') || coalesce(' · « ' || left(new.comment, 120) || ' »', ''), jsonb_build_object('delivery_id', new.delivery_id));
  return null;
end $$;
create trigger trg_rating_notify after insert on telima.ratings for each row execute function telima.tg_rating_notify();

create or replace function telima.tg_user_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if tg_op = 'INSERT' then
    perform telima.notify_user(new.id, 'account', 'Bienvenue sur Telima 👋',
      'Votre compte est prêt. Envoyez un colis ou faites faire vos courses en quelques secondes.');
    perform telima.notify_staff('new_user', 'Nouvel inscrit',
      coalesce(new.full_name, '') || ' · ' || coalesce(new.phone, '') || ' · ' || new.role::text, jsonb_build_object('user_id', new.id));
    return null;
  end if;
  if new.role is distinct from old.role then
    perform telima.notify_user(new.id, 'account', 'Rôle du compte modifié',
      'Votre compte est maintenant : ' || case new.role::text when 'admin' then 'administrateur' when 'operator' then 'opérateur'
        when 'driver' then 'livreur' else 'client' end || '. Reconnectez-vous pour voir votre nouvel espace.');
  end if;
  if new.is_active is distinct from old.is_active and new.is_active then
    perform telima.notify_user(new.id, 'account', 'Compte réactivé', 'Votre compte Telima est de nouveau actif.');
  end if;
  return null;
end $$;
create trigger trg_user_notify after insert or update of role, is_active on telima.users
  for each row execute function telima.tg_user_notify();

create or replace function telima.tg_support_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if tg_op = 'INSERT' then
    perform telima.notify_staff('support', 'Nouvelle demande d''assistance', new.subject || ' — ' || left(new.message, 100),
                                jsonb_build_object('support_id', new.id));
    if new.user_id is not null then
      perform telima.notify_user(new.user_id, 'support', 'Demande d''assistance reçue', new.subject || ' · nous vous répondons rapidement.');
    end if;
  elsif new.admin_reply is distinct from old.admin_reply and new.admin_reply is not null and new.user_id is not null then
    perform telima.notify_user(new.user_id, 'support', 'Réponse du support', left(new.admin_reply, 200),
                               jsonb_build_object('support_id', new.id));
  end if;
  return null;
end $$;
create trigger trg_support_notify after insert or update of admin_reply on telima.support_requests
  for each row execute function telima.tg_support_notify();

create or replace function telima.tg_business_member_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
declare v_name text;
begin
  select name into v_name from telima.business_accounts where id = new.business_id;
  perform telima.notify_user(new.user_id, 'business', 'Compte professionnel',
    'Vous avez été ajouté au compte « ' || coalesce(v_name, '') || ' ».', jsonb_build_object('business_id', new.business_id));
  return null;
end $$;
create trigger trg_business_member_notify after insert on telima.business_members
  for each row execute function telima.tg_business_member_notify();

-- Code de récupération de compte : aussi envoyé en notification sur les téléphones du compte
create or replace function telima.tg_password_reset_notify()
returns trigger language plpgsql security definer set search_path = telima, public as $$
begin
  if new.code_plain is not null then
    perform telima.notify_user(new.user_id, 'security', 'Code de récupération',
      'Votre code : ' || new.code_plain || ' (valable 30 minutes). Ne le communiquez à personne.');
  end if;
  return null;
end $$;
create trigger trg_password_reset_notify after insert on telima.password_reset_requests
  for each row execute function telima.tg_password_reset_notify();
