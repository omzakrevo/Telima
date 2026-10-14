# AGENTS.md — Telima

Consignes pour les agents de code (Codex, Claude Code…) qui travaillent sur ce dépôt.
Le propriétaire du projet communique en **français** : réponses, textes de l'interface, commentaires et messages de commit en français.

## Le projet
Telima : application de livraison et de services pour le Burkina Faso (FCFA, interface en français).
Livraison de colis, courses à faire, trajets (VTC), gaz et carburant, **restaurants**, **boutiques** et **voyages (tickets de car)**.
Rôles : client, livreur, administrateur, opérateur. Web : https://telimatchi.com (LWS) et https://telima-bf-3q2h.netlify.app.

* `app/` : application Flutter (Riverpod 3, go_router 18, supabase_flutter). Android + web.
* `supabase/cloud/migrations/` : **migrations réellement appliquées en production**, dans l'ordre (schéma `telima`).
  `supabase/migrations/` = schéma de référence pour un nouveau projet.
* `supabase/functions/` : fonctions Edge (inscription, comptes admin, mot de passe, push Firebase, relais SMS).
* `video/` : vidéos promotionnelles en Remotion (React) : `RestaurantsVertical`, `BoutiquesVertical`.
* `docs/` : documentation fonctionnelle (voir plus bas). `docs/COORDINATION.md` : échanges entre agents.

## Commandes
```bash
cd app
flutter pub get
flutter analyze            # doit rester à « No issues found »
flutter test               # 45 tests, tous doivent passer
flutter run -d chrome --dart-define-from-file=env.json      # env.json : copier env.example.json (URL + clé anon publique)
```
* Flutter **3.47.x** (Dart ^3.13.5). Les versions Shorebird publiées utilisent Flutter 3.47.6.
* `app/test/travel_screens_test.dart` affiche les écrans Voyages avec des données fictives et échoue au moindre débordement.
  Captures : `flutter test test/travel_screens_test.dart --update-goldens --dart-define=SHOTS_DIR=/chemin/absolu`.
* Vidéos : `cd video && npm install && npx remotion render src/index.ts BoutiquesVertical out/x.mp4`
  (police chargée depuis `public/fonts`, pas besoin d'Internet).

## Conventions
* Style : écrans sobres et modernes, couleurs et composants de `lib/config/theme.dart` et `lib/widgets/common.dart`.
* Chaque module suit le même découpage : `data/models/<module>.dart`, `data/repositories/<module>_repository.dart`,
  `providers/<module>_providers.dart`, `screens/<module>/…`, `screens/admin/admin_<module>_screen.dart`, `docs/module-<module>.md`.
* Côté serveur, la logique sensible (prix, places, stock, statuts) est dans des fonctions SQL `SECURITY DEFINER`
  avec `set search_path = telima, public`, et l'accès aux tables est protégé par RLS. L'application ne fait jamais confiance aux prix envoyés par le client.
* Nouvelle migration : fichier `supabase/cloud/migrations/AAAAMMJJHHMMSS_telima_NN_nom.sql`, sans casser l'existant
  (vérifier les noms déjà pris : il reste d'anciennes tables `menu_*`, `food_orders`…). Tester un scénario complet
  dans une transaction annulée avant de conclure, puis vérifier les alertes de sécurité Supabase.
* Liens publics partagés : `/r/<lien>` restaurant, `/b/<lien>` boutique, `/v/<lien>` compagnie de voyage (lisibles sans compte) ;
  les commandes ou réservations demandent une connexion (`pendingRouteProvider` ramène l'utilisateur après connexion).
* Paiement : espèces (à la remise, au livreur ou au guichet). Mobile Money manuel pour les livraisons (voir `docs/PAIEMENTS_ET_SERVICES.md`).
* Ne jamais committer de secret : clé de signature `app/android/app/telima-signing.jks`, `app/env.cloud.json`,
  clés API Shorebird, mots de passe. Le dépôt est **public**.

## Documentation des modules
* `docs/module-restaurants.md`, `docs/module-boutiques.md`, `docs/module-voyages.md`
* `docs/ARCHITECTURE.md`, `docs/PAIEMENTS_ET_SERVICES.md`, `docs/MISES_A_JOUR.md` (APK, Shorebird)

## État au 14 octobre 2026 (passation de Claude Code)
Tout le travail ci-dessous est **fusionné dans `main`** (PR n°3, 14/10/2026) ; `app/pubspec.yaml` est en version **1.9.0+2011**.

Fait, testé (`flutter analyze` propre, 45 tests verts) :
1. **QR code des liens** restaurants et boutiques : afficher et télécharger en PNG, côté commerçant et côté client
   (`lib/widgets/qr_link_sheet.dart`, paquet `qr_flutter`, `exportBytesFile` dans `core/services/file_export_*.dart`).
2. **Module Voyages** complet (voir `docs/module-voyages.md`) : compagnies inscrites ou gérées par l'équipe Telima,
   départs, réservation avec places bloquées, confirmation par la compagnie, e-ticket QR (`TELIMA-VOY:<code>:<secret>`),
   livraison du ticket papier par un livreur Telima, contrôle à l'embarquement, administration `/admin/transport`.
   Migration **`telima_18_voyages` + `telima_18b_voyages_search_path` déjà appliquées en production** (14/10/2026) ;
   scénario complet vérifié sur la base réelle dans une transaction annulée. Aucune compagnie ni départ réel n'existe encore.
3. **Vidéo Boutiques** 9:16 avec voix off (`video/src/BoutiqueVideo.tsx`, `video/public/voix-off-boutiques.mp3`, 35 s).

Durcissement après relecture (migration **`telima_19_voyages_durcissement`**, **appliquée en production le 14/10/2026** en deux temps :
`telima_19_voyages_durcissement` puis `telima_19b_voyages_trigger_horaire` pour le déclencheur `trg_travel_trips_notify_move` — le fichier du dépôt contient les deux) :
inscription d'une compagnie « en attente » jusqu'à validation par l'équipe, expiration des réservations non confirmées après 2 h (max 3 en attente par client),
messages de remboursement à l'annulation d'un départ, voyageurs prévenus si l'horaire change, contrôle d'un ticket par son seul numéro.
`pg_cron` n'est pas activé sur le projet : l'expiration se fait à la prochaine réservation sur le même départ (activer l'extension puis relancer le bloc `cron.schedule` de la migration pour l'automatiser).

Migrations en production (les plus récentes) : 13 restaurants, 14 suppression utilisateur, 15 boutiques,
16 téléphone facultatif (appliquée hors historique), 17 galerie et avis boutiques, 18 voyages, 18b search_path.

Compagnies saisies par l'équipe (admin « Zachari SOME »), approuvées, sans livraison de ticket, d'après les affiches fournies par le propriétaire :
Rahimo Transport, Saramaya Transport (mêmes départs qu'Elitis), Elitis Express, TSR Express, Rakieta Transport (tarifs normaux, affiches de 2023),
STAF Transport (tarifs de Rakieta). Départs générés pour 10 jours (à renouveler : aucune génération automatique tant que `pg_cron` n'est pas actif).
Positions des gares approximatives (centre-ville) à préciser dans Admin → Voyages. Horaires « indicatifs » : confirmés par téléphone par l'équipe.
Page Voyages refaite (choix ville/compagnie/heure, bandeau des compagnies, page compagnie avec photos, animations ; migration `telima_21`, voir `docs/module-voyages.md`).
Frais de réservation 500 F par réservation payés en Mobile Money (activés en production, partie B appliquée) : migration `telima_20_voyages_frais_reservation` (voir `docs/module-voyages.md`).

## À faire ensuite
1. ~~Relire et fusionner la PR `codex/reprise`~~ : fait (PR n°3 fusionnée dans `main`, version portée à 1.9.0+2011).
2. ~~Redéployer le site~~ : workflow « Deploy web (LWS) » lancé le 14/10/2026 sur `main` (avant le passage en 1.9.0, sans effet sur le web).
   Vérifier sur https://telimatchi.com : « Voyages » et « Ma compagnie » à l'accueil, QR code sur une page restaurant ou boutique.
3. **Version complète 1.9.0+2011 — à faire sur le PC du propriétaire** (clé de signature `telima-signing.jks`, `env.cloud.json`, clé API Shorebird) :
   ```bash
   git pull origin main
   cd app && flutter analyze && flutter test
   shorebird release android --artifact apk --target-platform android-arm,android-arm64 --dart-define-from-file=env.cloud.json
   ```
   Puis Admin → Mises à jour appli → Publier : version `1.9.0`, numéro `11`, fichier `build/app/outputs/flutter-apk/app-release.apk`.
   Elle active l'ouverture des liens `/v/` dans l'application (filtre ajouté à `AndroidManifest.xml`).
   Le patch Shorebird sur 1.8.0+2010 reste possible mais les liens `/v/` s'ouvrent alors dans le navigateur.
4. **Vérifier le contrôle automatique** `build-and-test` de la PR n°3 / de `main` : la PR a été fusionnée avant sa fin et
   les modifications de la migration 19 côté Flutter (statut « en attente » des compagnies, test `travel_test.dart`) n'ont pas été exécutées localement.
5. **Expiration automatique des réservations** : activer l'extension `pg_cron` dans Supabase puis relancer
   `select cron.schedule('telima-expire-travel-bookings', '*/15 * * * *', 'select telima.expire_stale_travel_bookings()');`.
6. **Circuit de l'argent des tickets** : les billets sont maintenant **payés en ligne** à Telima (migration `telima_22`, voir `docs/module-voyages.md`) ;
   le reversement aux compagnies n'est suivi nulle part (table, écran, règle). À définir avec le propriétaire avant les premières ventes réelles.
   Remboursement : règle « frais gardés si le voyageur annule lui-même » à confirmer.
7. Idées listées dans les docs des modules : lecture du QR à la caméra pour le contrôle des tickets, plan des places,
   départs réguliers automatiques, Mobile Money, promotions et guide des tailles pour les boutiques.
