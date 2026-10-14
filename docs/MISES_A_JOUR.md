# Mises à jour de l'application Android Telima

Deux mécanismes complémentaires.

## 1. Mise à jour intégrée (déjà active, aucun compte externe)

**Pour l'administrateur**

1. Dans `app/pubspec.yaml`, augmentez la version : `version: 1.5.0+2006`. Le numéro après `+` s'écrit **2000 + n** (n = 6, 7, 8…) et doit toujours augmenter ; dans le tableau de bord on saisit seulement **n**.
2. Construisez les fichiers :
   ```bash
   cd app
   flutter build apk --release --split-per-abi --target-platform android-arm64,android-arm \
     --dart-define-from-file=env.cloud.json
   ```
   Fichiers produits dans `build/app/outputs/flutter-apk/` :
   `app-arm64-v8a-release.apk` (téléphones récents) et `app-armeabi-v7a-release.apk` (téléphones anciens).
3. Tableau de bord → **Mises à jour appli** → **Publier une nouvelle version** :
   version `1.5.0`, numéro `6`, nouveautés, déposez les deux APK, cochez « obligatoire » si besoin → **Publier**.

**Côté utilisateurs** : à l'ouverture (et au retour dans l'application), Telima voit la nouvelle version,
télécharge seule le fichier adapté au téléphone, puis Android affiche la fenêtre « Mettre à jour » :
un seul appui. Android impose cette confirmation pour toute application installée hors Play Store.
Une version obligatoire bloque l'application jusqu'à l'installation. « Retirer » arrête la distribution.

## Clé de signature — À CONSERVER

`app/android/app/telima-signing.jks` signe toutes les versions. Si elle est perdue, plus aucune mise à jour
ne pourra s'installer par-dessus l'application existante (les utilisateurs devraient la désinstaller).
Gardez-en une copie hors de l'ordinateur (clé USB, Drive privé). Pour changer les mots de passe par défaut,
utilisez les variables `TELIMA_STORE_PASSWORD`, `TELIMA_KEY_ALIAS`, `TELIMA_KEY_PASSWORD`.

## 2. Mise à jour invisible avec Shorebird (ACTIVÉE)

Shorebird est installé et relié à votre compte (application « Telima », identifiant dans `app/shorebird.yaml`).
Version de base publiée : **1.5.0+2006** (elle est aussi distribuée automatiquement par la mise à jour intégrée).

Pour toute modification du code de l'application (écrans, textes, couleurs, logique) **sans changement natif** :
```bash
export SHOREBIRD_TOKEN=sb_api_...        # votre clé API Shorebird
./scripts/shorebird_patch.sh 1.5.0+2006
```
Aucune action des utilisateurs : le correctif se télécharge à l'ouverture et s'applique au redémarrage suivant.

Pour un changement natif (nouveau paquet avec code Android, permission, icône, version de Flutter) :
nouvelle version de base `shorebird release android --artifact apk --target-platform android-arm,android-arm64 --dart-define-from-file=env.cloud.json`
avec le numéro suivant (ex. `1.5.0+2006`), puis publication dans « Mises à jour appli » (fichier universel `build/app/outputs/flutter-apk/app-release.apk`).

Installation de l'outil sur un nouvel ordinateur :
```bash
curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | bash
```

## 3. Notifications (bannière en haut de l'écran)

- Au premier lancement, l'application demande l'autorisation d'afficher les notifications (Android 13+)
  et crée le canal « Alertes Telima » (importance maximale : bannière, son, vibration).
- Application ouverte ou en arrière-plan : chaque notification arrive en temps réel et s'affiche en bannière.
- Application fermée : envoi par Firebase Cloud Messaging (fonction serveur `telima-push`, déclenchée
  automatiquement à chaque ligne ajoutée dans `telima.notifications`).
- Brancher Firebase : tableau de bord → **Notifications push** → déposer `google-services.json`
  (package `app.telima.telima`) et la clé du compte de service. Aucune reconstruction de l'application.
- Bouton « M'envoyer une notification d'essai » pour vérifier.


## 4. Tout depuis GitHub, sans ordinateur (workflow « Android (Shorebird) »)
GitHub > Actions > **Android (Shorebird)** > Run workflow :
* **release** : nouvelle version complète (version lue dans `app/pubspec.yaml`), signée avec la clé Telima, envoyée à Shorebird, gardée comme fichier téléchargeable du run,
  puis publiée dans « Mises à jour appli » si la case est cochée (les téléphones proposent la mise à jour à l'ouverture).
* **patch** : correctif invisible du code Dart pour la version déjà installée.

Secrets à ajouter une seule fois (Settings > Secrets and variables > Actions > Repository secrets) :
`SHOREBIRD_TOKEN`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `TELIMA_KEYSTORE_BASE64` (contenu du fichier `telima-signing.jks` en base64, une seule ligne),
`TELIMA_STORE_PASSWORD`, `TELIMA_KEY_ALIAS`, `TELIMA_KEY_PASSWORD`, et pour la publication automatique `SUPABASE_SERVICE_ROLE_KEY`.
Le workflow dit précisément quel secret manque (longueurs seulement, jamais les valeurs) et vérifie le mot de passe de la clé avant de compiler.
La clé de signature doit être **la même** que celle des versions déjà installées, sinon Android refuse la mise à jour.
