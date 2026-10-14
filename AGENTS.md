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
Branche **`codex/reprise`** = `main` + tout le travail ci-dessous, **pas encore fusionnée dans `main`** (PR ouverte).

Fait, testé (`flutter analyze` propre, 45 tests verts) :
1. **QR code des liens** restaurants et boutiques : afficher et télécharger en PNG, côté commerçant et côté client
   (`lib/widgets/qr_link_sheet.dart`, paquet `qr_flutter`, `exportBytesFile` dans `core/services/file_export_*.dart`).
2. **Module Voyages** complet (voir `docs/module-voyages.md`) : compagnies inscrites ou gérées par l'équipe Telima,
   départs, réservation avec places bloquées, confirmation par la compagnie, e-ticket QR (`TELIMA-VOY:<code>:<secret>`),
   livraison du ticket papier par un livreur Telima, contrôle à l'embarquement, administration `/admin/transport`.
   Migration **`telima_18_voyages` + `telima_18b_voyages_search_path` déjà appliquées en production** (14/10/2026) ;
   scénario complet vérifié sur la base réelle dans une transaction annulée. Aucune compagnie ni départ réel n'existe encore.
3. **Vidéo Boutiques** 9:16 avec voix off (`video/src/BoutiqueVideo.tsx`, `video/public/voix-off-boutiques.mp3`, 35 s).

Migrations en production (les plus récentes) : 13 restaurants, 14 suppression utilisateur, 15 boutiques,
16 téléphone facultatif (appliquée hors historique), 17 galerie et avis boutiques, 18 voyages, 18b search_path.

## À faire ensuite
1. **Relire et fusionner** la PR `codex/reprise` → `main`.
2. **Mise à jour des téléphones.** Versions de base Shorebird publiées : 1.7.0+2009 et **1.8.0+2010** (la plus récente).
   * Patch possible sur 1.8.0+2010 : seul changement natif depuis = la ligne `/v/` dans `AndroidManifest.xml`
     (Shorebird le signale ; le reste part dans le patch, les liens `/v/` s'ouvrent alors dans le navigateur).
   * Version complète **1.9.0+2011** recommandée pour activer les liens `/v/` dans l'application :
     `shorebird release android --artifact apk --target-platform android-arm,android-arm64 --dart-define-from-file=env.cloud.json`
     sur le PC du propriétaire (il a la clé de signature et la clé API), puis publication dans Admin → Mises à jour appli.
3. **Site web** : redéployer (workflow GitHub « Deploy web (LWS) », déclenchement manuel) pour publier QR code et Voyages.
4. Idées listées dans les docs des modules : lecture du QR à la caméra pour le contrôle des tickets, plan des places,
   départs réguliers automatiques, Mobile Money, promotions et guide des tailles pour les boutiques.
