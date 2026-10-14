---
name: publier-android
description: Publier une nouvelle version de l'application Android (Telima) depuis GitHub, sans ordinateur : release Shorebird signée, publication dans « Mises à jour appli » (Supabase), ou correctif invisible. À utiliser quand le propriétaire dit « publie / déploie / sors la nouvelle version Android », « lance la release », « envoie sur Shorebird », ou veut le même système dans un autre projet.
---

# Publier l'application Android depuis GitHub

Le propriétaire ne doit rien faire sur son ordinateur : tout passe par le workflow **« Android (Shorebird) »**
(`.github/workflows/android_release.yml`). Réponds-lui en français, simplement, sans jargon.

## Marche à suivre (dépôt Telima)
1. **Version** : dans `app/pubspec.yaml`, `version: X.Y.Z+NNNN`. Le numéro après `+` doit **augmenter** à chaque release complète
   (n = NNNN − 2000 dans « Mises à jour appli »). Un simple correctif Dart garde la même version (mode patch).
2. **Contrôles avant d'envoyer** : `flutter analyze` et `flutter test` propres (Flutter 3.47.6 ; le télécharger si absent :
   `https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.6-stable.tar.xz`).
   Commit + push sur `main`.
3. **Choisir le mode** :
   * `release` : nouvelle version complète. **Obligatoire** si des images/assets, des paquets, des permissions ou le natif ont changé
     (un patch Shorebird ne transporte pas les assets). Compile, signe, envoie à Shorebird, garde l'APK, puis publie dans « Mises à jour appli » (`publish_in_app: true`).
   * `patch` : correctif invisible du code Dart pour la version déjà installée (aucune action des utilisateurs, appliqué au redémarrage).
   * `publish` + `from_run` : publier dans « Mises à jour appli » l'APK d'un run `release` précédent (si la publication avait été décochée).
4. **Lancer** (outil GitHub `actions_run_trigger`, workflow `android_release.yml`, `ref: main`, `inputs` : `mode`, `publish_in_app`, `notes`, `mandatory`, `from_run`).
5. **Suivre** avec `actions_list list_workflow_jobs` puis `get_job_logs` en cas d'échec (une release prend ~15 min : programmer un rappel avec `send_later`, ne pas boucler).
6. **Vérifier** la table `telima.app_releases` (version, `is_published`) et annoncer le résultat au propriétaire.

## Secrets du dépôt (ajoutés une seule fois par le propriétaire dans Settings > Secrets and variables > Actions)
`SHOREBIRD_TOKEN`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `TELIMA_KEYSTORE_BASE64`, `TELIMA_STORE_PASSWORD`, `TELIMA_KEY_ALIAS`,
`TELIMA_KEY_PASSWORD`, `SUPABASE_SERVICE_ROLE_KEY` (publication automatique). Le workflow affiche les longueurs (jamais les valeurs) et dit lequel manque.
**Ne jamais demander de coller un secret dans la conversation** : guider vers `https://github.com/<proprietaire>/<depot>/settings/secrets/actions/new`.

## Pièges déjà rencontrés
* Secrets ajoutés dans le **mauvais dépôt** (Colis-Tracker au lieu de Telima) → longueurs à 0.
* `SUPABASE_URL` copiée avec `/rest/v1/` : le workflow garde seulement `https://<projet>.supabase.co`.
* Le fichier de clé `telima-signing.jks` est dans `app/android/app/` sur l'ordinateur du propriétaire (hors dépôt). PowerShell : utiliser un **chemin complet**
  (`[IO.File]` lit depuis `C:\Windows\system32` sinon) : `[Convert]::ToBase64String([IO.File]::ReadAllBytes($f)) | Set-Clipboard`.
  Valeurs par défaut du projet : mot de passe `android`, alias `androiddebugkey`. La clé doit être **la même** que celle des versions installées.
* L'outil SQL de Supabase bloque sur certains `DROP` / `CREATE TRIGGER` : utiliser `apply_migration` (un déclencheur seul).
* Une release Shorebird d'un même numéro de version ne peut pas être refaite : augmenter le `+NNNN` ou utiliser `patch`.

## Réutiliser dans un autre projet (Flutter + Supabase + Shorebird)
Copier `modele/android_release.yml` dans `.github/workflows/` et `modele/publish_release.py` dans `scripts/`, puis adapter :
dossier de l'application (`app/`), version Flutter, nom du fichier de clé et des variables `*_STORE_PASSWORD` / `*_KEY_ALIAS` (voir `android/app/build.gradle.kts`),
`app_id` de `shorebird.yaml`, bucket et table des mises à jour (`telima-releases` / `telima.app_releases`) et règle « n = build − 2000 ».
Sans mises à jour intégrées, supprimer l'étape « Publier ». Créer les mêmes secrets dans le nouveau dépôt.
