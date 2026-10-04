# Telima — Application de livraison

Application complète de gestion et de livraison de colis, pensée pour le Burkina Faso :
**Client** (Android/Web), **Livreur** (Android) et **Administrateur** (tableau de bord Web).
Interface entièrement en français, montants en FCFA.

| Élément | Technologie |
|---|---|
| Application (client, livreur, admin) | Flutter 3.47 — un seul code pour Android, Web/PWA (et iOS plus tard) |
| État / navigation | Riverpod 3, go_router |
| Base de données, authentification, fichiers, temps réel | Supabase (PostgreSQL 17, RLS, Storage, Realtime, fonctions Edge) |
| Cartes | OpenStreetMap (flutter_map), itinéraires OSRM — aucune clé API nécessaire |

---

## 1. Structure du projet

```
telima/
├── app/                         Application Flutter
│   └── lib/
│       ├── config/              env.dart (variables), theme.dart (couleurs, boutons)
│       ├── core/
│       │   ├── services/        GPS, itinéraires, géocodage, cache, file hors-ligne,
│       │   │                    stockage photos, notifications, export CSV
│       │   │   └── payment/     Abstraction des paiements (espèces, portefeuille,
│       │   │                    Mobile Money simulé / réel)
│       │   └── utils/           formatage FCFA/dates/téléphone, validations, erreurs
│       ├── data/
│       │   ├── models/          Livraison, livreur, portefeuille, configuration…
│       │   └── repositories/    Accès Supabase (auth, livraisons, livreur, admin…)
│       ├── providers/           Riverpod : session, données, suivi GPS du livreur
│       ├── routes/              Routage par rôle (client / livreur / admin)
│       ├── screens/             auth · client · business · driver · admin · visitor · common
│       └── widgets/             Composants réutilisables (cartes, formulaires, prix…)
├── supabase/
│   ├── migrations/              4 migrations SQL (schéma, fonctions, RLS, configuration)
│   ├── functions/               admin-create-user, reset-password (fonctions Edge)
│   ├── tests/                   Test SQL des parcours (Postgres local)
│   └── config.toml              Configuration Supabase CLI
├── scripts/
│   ├── seed_accounts.mjs        Crée les comptes de test Client / Livreur / Admin / Opérateur
│   ├── e2e_api_test.mjs         75 vérifications de bout en bout via l'API Supabase
│   └── test_db.sh               Test des migrations sur un Postgres local
└── docs/ARCHITECTURE.md         Architecture, rôles, sécurité, statuts
```

---

## 2. Mise en place de Supabase

### Option A — Supabase en ligne (production / tests réels)

1. Créez un projet sur <https://supabase.com> (région la plus proche : Europe).
2. **Authentication → Providers → Email** : activez Email et **désactivez « Confirm email »**.
   Le numéro de téléphone est l'identifiant ; il est converti en adresse technique
   `22670123456@telima.app` (aucun e-mail n'est envoyé).
3. Installez le CLI puis appliquez les migrations et déployez les fonctions :

```bash
npm i -g supabase
cd telima
supabase login
supabase link --project-ref VOTRE_REF_PROJET
supabase db push                       # applique supabase/migrations/*
supabase functions deploy admin-create-user
supabase functions deploy reset-password --no-verify-jwt
```

4. Créez les comptes de test (la clé `service_role` se trouve dans *Project Settings → API* ;
   ne la mettez **jamais** dans l'application) :

```bash
cd scripts && npm install
SUPABASE_URL=https://VOTRE_REF.supabase.co SUPABASE_SERVICE_ROLE_KEY=xxx node seed_accounts.mjs
```

### Option B — Supabase local (développement, nécessite Docker)

```bash
cd telima
supabase start            # applique automatiquement les migrations
supabase functions serve  # dans un autre terminal
```

### Comptes de test créés par `seed_accounts.mjs`

| Rôle | Téléphone |
|---|---|
| Client | 70 00 00 01 |
| Livreur (approuvé, moto 11 JK 2233) | 70 00 00 02 |
| Administrateur | 70 00 00 03 |
| Opérateur (saisie des commandes, sans accès aux tarifs/paramètres) | 70 00 00 04 |

Le mot de passe est celui passé dans la variable `TEST_PASSWORD` au moment de `node seed_accounts.mjs` (aucun mot de passe n'est écrit dans ce dépôt). Changez-le avant la mise en production.

---

## 3. Lancer l'application

Créez `app/env.json` (non versionné) à partir de `app/env.example.json` :

```json
{ "SUPABASE_URL": "https://VOTRE_REF.supabase.co", "SUPABASE_ANON_KEY": "votre clé anon ou publishable" }
```

```bash
cd app
flutter pub get
flutter run --dart-define-from-file=env.json              # téléphone Android branché
flutter run -d chrome --dart-define-from-file=env.json    # Web (tableau de bord admin)
```

### Compiler

```bash
# APK Android, une par architecture (~20 Mo au lieu de 66 Mo : mieux pour les connexions lentes)
flutter build apk --release --split-per-abi --dart-define-from-file=env.json
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (téléphones récents)

# Web / PWA (dashboard admin) — déployable sur Netlify, Vercel, Firebase Hosting, un serveur Nginx…
flutter build web --release --dart-define-from-file=env.json
# → build/web/
```

Pour publier sur le Play Store, configurez une clé de signature
(<https://docs.flutter.dev/deployment/android#signing-the-app>) ; l'APK actuel est signé avec la clé de débogage.

---

## 4. Ce qui est simulé et comment passer en réel

Toutes les fonctions marchent dès maintenant. Trois services externes sont en **mode simulation**,
réglable dans *Dashboard → Paramètres* :

| Service | Simulation actuelle | Passage en réel |
|---|---|---|
| **Orange Money / Moov Money** (paiements, rechargements) | Le paiement est confirmé par le serveur après une fausse validation USSD (aucun argent réel). | Créer la fonction Edge `mobile-money-init` (reçoit `payment_id`, `provider`, `phone`, appelle l'API de l'opérateur) et un webhook qui appelle `public._confirm_payment(payment_id, reference)` avec la clé service_role. Puis Paramètres → Mobile Money → « Réel ». Le code de l'app (`LiveMobileMoneyProvider`) est déjà prêt. |
| **Retraits des livreurs** | L'admin effectue le transfert Orange/Moov à la main puis saisit la référence. | Automatisable avec l'API de décaissement de l'opérateur. |
| **SMS** (récupération de compte) | Le code à 6 chiffres apparaît dans *Dashboard → Support → Récupération de compte* ; le support le communique au client par téléphone. | Brancher un fournisseur SMS (ex. Twilio, Orange SMS API) dans `request_password_reset`, puis Paramètres → SMS → « fournisseur configuré ». |
| **Notifications push** hors application | Les notifications arrivent en temps réel dans l'application ouverte (bandeau + liste). | Ajouter Firebase (`firebase_messaging`), implémenter `PushTransport`, et un webhook sur la table `notifications` qui envoie via FCM. La table `device_tokens` est prête. |

---

## 5. Tests réalisés

* `scripts/test_db.sh` — migrations + parcours complet en SQL (Postgres 16).
* `scripts/e2e_api_test.mjs` — **75 vérifications réussies** sur une vraie stack Supabase
  (inscription, RLS, photos, création, acceptation, 10 étapes horodatées, GPS temps réel,
  messagerie, OTP, commissions, portefeuille, remboursement, Mobile Money simulé,
  multi-destinations, commande téléphonique, attribution manuelle, retrait, suspension,
  création de livreur par l'admin, récupération de compte, désactivation).
* Parcours testé dans un navigateur : le livreur passe EN LIGNE, le client commande en 4 étapes,
  le livreur accepte, effectue les étapes et termine avec le code ; le client suit sur la carte puis note.
* `flutter analyze` : aucun problème ; build Web et APK Android : OK.

```bash
cd scripts
SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE_KEY=... node e2e_api_test.mjs
```

---

## 6. Limites connues / prochaines étapes

* **Suivi GPS en arrière-plan** : la position du livreur est envoyée tant que l'application est ouverte
  (même écran éteint sur la plupart des téléphones). Pour un envoi garanti application fermée,
  ajouter un service de premier plan Android (ex. `flutter_background_service`).
* **Optimisation automatique de l'itinéraire** multi-destinations : l'ordre est choisi par le client
  (glisser-déposer) ; le schéma est prêt pour une optimisation (`stop_order`).
* **iOS** : le code est compatible (permissions déjà déclarées) ; la compilation nécessite un Mac avec Xcode.
* Le serveur OSRM public et les tuiles OpenStreetMap conviennent aux tests ; pour un usage intensif,
  héberger son propre serveur ou prendre un fournisseur (variables `OSRM_URL` et `TILE_URL`).

---

## Documentation et état du projet

- [`docs/PAIEMENTS_ET_SERVICES.md`](docs/PAIEMENTS_ET_SERVICES.md) — paiement Orange Money / Moov Money manuel, relais des SMS, courses à faire, trajets (VTC), notifications.
- [`docs/MISES_A_JOUR.md`](docs/MISES_A_JOUR.md) — mises à jour Android (mise à jour intégrée + correctifs Shorebird).
- `supabase/migrations/` — schéma de référence (installation d'un nouveau projet).
- `supabase/cloud/migrations/` — les 46 migrations réellement appliquées sur le projet Supabase en production (schéma `telima`), dans l'ordre.
- `supabase/functions/` — fonctions serveur : inscription, création de comptes admin, récupération de mot de passe, notifications push (Firebase), relais SMS Mobile Money.
- `scripts/e2e_api_test.mjs` — 103 vérifications de bout en bout (`SUPABASE_URL=… SUPABASE_ANON_KEY=… TEST_PASSWORD=… node e2e_api_test.mjs`).

**Non inclus volontairement (dépôt public)** : la clé de signature Android `app/android/app/telima-signing.jks`
(à conserver hors ligne : sans elle, plus aucune mise à jour ne s'installe par-dessus l'application),
le fichier `app/env.cloud.json` (copier `app/env.example.json`), les mots de passe et clés API.

Version actuelle : **1.5.0 (2006)** — site web : https://telima-bf.netlify.app
