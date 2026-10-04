-- TELIMA — dernier petit bloc à exécuter dans Supabase > SQL Editor (projet TELIMA)
-- Fonction « Supprimer / désactiver mon compte » (elle retire aussi les jetons de notification du téléphone).
-- Copier tout, coller dans « New query », puis « Run ».

create or replace function telima.deactivate_my_account()
returns void language plpgsql security definer set search_path = telima, public as $$
declare v_uid uuid := telima.require_active_user();
begin
  if exists (select 1 from telima.deliveries
             where (customer_id = v_uid or driver_id = v_uid)
               and status not in ('completed', 'cancelled')) then
    raise exception 'Impossible : vous avez une livraison en cours' using errcode = 'P0001';
  end if;
  update telima.users set is_active = false, deactivated_at = now() where id = v_uid;
  update telima.drivers set is_online = false where user_id = v_uid;
  delete from telima.device_tokens where user_id = v_uid;
end $$;

revoke execute on function telima.deactivate_my_account() from public, anon;
grant execute on function telima.deactivate_my_account() to authenticated, service_role;

select 'Telima : bloc final appliqué' as resultat;
