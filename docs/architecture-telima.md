# Architecture technique — Telima

## Vue d'ensemble

```
 Application Flutter (Android / Web)                 Supabase
 ┌───────────────────────────────┐        ┌──────────────────────────────────┐
 │ screens  ─ widgets             │        │ Auth (téléphone → identifiant)   │
 │    │                            │  HTTPS │ PostgREST + fonctions SQL (RPC)  │
 │ providers (Riverpod)            │◄──────►│ Row Level Security               │
 │    │                            │  WSS   │ Realtime (livraisons, GPS,       │
 │ repositories ─ services         │◄──────►│   messages, notifications)       │
 │ (cache, file hors-ligne, GPS,   │        │ Storage (photos, documents)      │
 │  paiements, itinéraires)        │        │ Edge Functions (admin, mot passe)│
 └───────────────────────────────┘        └──────────────────────────────────┘
          │ OpenStreetMap (tuiles) · OSRM (itinéraires) · Nominatim (adresses)
```

**Principe de sécurité :** l'application n'écrit presque jamais directement dans les tables.
Toutes les opérations sensibles (prix, création, acceptation, étapes, preuve, argent, administration)
passent par des **fonctions PostgreSQL `SECURITY DEFINER`** qui vérifient l'utilisateur (`auth.uid()`),
son rôle et l'état de la livraison. Le prix est **recalculé côté serveur** : le client ne peut pas le modifier.

## Rôles et permissions

| Rôle | Peut | Ne peut pas |
|---|---|---|
| Visiteur (sans compte) | Estimer un prix, écrire au support, demander un code de récupération | Voir une livraison |
| Client | Créer/suivre/annuler (avant récupération) ses livraisons, lire son code OTP, noter, discuter avec son livreur, gérer son portefeuille, créer un compte pro | Voir les commandes des autres, modifier un statut, son rôle ou les tarifs |
| Membre d'un compte pro | Envoyer et suivre les livraisons du compte, carnet de clients, relevés CSV | Voir les autres comptes |
| Livreur | Passer en ligne (si approuvé), voir les demandes proches (sans téléphones avant acceptation), accepter/refuser, avancer étape par étape, terminer avec preuve, revenus, retraits | Lire le code OTP, sauter une étape, voir des courses qui ne sont pas les siennes |
| Opérateur | Tableau de bord, commandes, commandes téléphoniques, attribution manuelle, annulation, support | Tarifs, paramètres, rôles, retraits, journal |
| Administrateur | Tout, dont tarifs, villes/zones, commission, paramètres, utilisateurs, retraits, journal | — |

## Statuts d'une livraison (11 étapes)

`created` Nouvelle demande → `searching` Recherche de livreur → `assigned` Livreur trouvé →
`to_pickup` En route vers le client → `at_pickup` Livreur arrivé → `picked_up` Colis récupéré →
`in_transit` Livraison en cours → `at_dropoff` Arrivé à destination → `handed_over` Colis remis →
`completed` Livraison terminée · `cancelled` Annulée

Chaque changement est enregistré dans `delivery_status_history` (date, heure, auteur, position GPS)
par un déclencheur, qui crée aussi la notification du client.

Paiement Mobile Money : la commande reste en `created` jusqu'à confirmation du paiement, puis passe en `searching`.

## Tarification

```
prix = arrondi_sup( (prix_départ + max(0, distance − km_inclus) × prix_km + options) × coef_zone + frais_zone , arrondi )
       avec un minimum par véhicule
options = supplément taille + supplément fragile ; arrêt supplémentaire = frais d'arrêt + distance × prix_km
```

* Distance : distance routière OSRM transmise par l'application **si elle est plausible**
  (entre 0,95× et 2,5× le vol d'oiseau), sinon vol d'oiseau × coefficient (1,3 par défaut).
* Tarifs par véhicule, par défaut ou propres à une ville ; zones (centre + rayon) avec frais fixes et coefficient.
* Véhicule conseillé selon taille/poids/catégorie ; un véhicule trop petit est refusé.
* Commission (pourcentage ou fixe) lue dans `app_settings` à la création de chaque commande et figée sur la commande.

## Règlement financier à la clôture

| Paiement | Effet |
|---|---|
| Espèces / à la livraison | Le livreur encaisse le total ; la commission est **débitée** de son portefeuille (solde négatif possible jusqu'au plafond `driver_max_debt`, au-delà il ne peut plus passer en ligne). |
| Portefeuille / Mobile Money (payés d'avance) | La part livreur est **créditée** sur son portefeuille. |
| Annulation d'une commande payée | Remboursement automatique sur le portefeuille du client. |

Retrait : le montant est réservé (débité) à la demande, recrédité en cas de refus.

## Mode connexion faible

* Cache local (SharedPreferences) des livraisons, profil, villes, paramètres, revenus : affichage hors ligne.
* File d'attente hors ligne : les étapes du livreur et sa dernière position sont rejouées automatiquement
  (fonctions serveur idempotentes). Bandeau « Hors connexion / Synchronisation ».
* Brouillon de commande conservé si l'application se ferme.
* GPS : filtre 25 m + intervalle minimal configurable (10 s) + battement toutes les 2 min à l'arrêt ;
  le serveur limite aussi l'enregistrement. Itinéraire recalculé seulement au changement d'étape,
  après 300 m de déplacement ou toutes les 2 min (sinon estimation locale).
* Photos réduites à 1280 px / qualité 70 % avant envoi.

## Tables

users, customers, drivers, vehicles, deliveries, delivery_secrets (OTP), delivery_status_history,
delivery_locations, delivery_declines, delivery_batches, payments, wallets, wallet_transactions,
withdrawals, ratings, messages, notifications, device_tokens, pricing_rules, cities, delivery_zones,
business_accounts, business_members, saved_addresses, support_requests, password_reset_requests,
admin_logs, app_settings, code_counters.

## Stockage

| Compartiment | Accès |
|---|---|
| avatars | public en lecture |
| package-photos | propriétaire, personnel, participants de la livraison |
| proofs | livreur auteur, personnel, client de la livraison |
| driver-documents (CNIB, permis) | livreur concerné et personnel uniquement |
| vehicle-photos | livreur concerné et personnel |

Chaque utilisateur n'écrit que dans son dossier `<uid>/…`.
