---
name: publier-web
description: Publier le site web Telima (Flutter web) sur l'hébergement LWS par SFTP depuis GitHub, sans ordinateur. À utiliser quand le propriétaire dit « déploie / publie / mets en ligne le site », « relance le déploiement web », ou veut le même système dans un autre projet.
---

# Publier le site web depuis GitHub

Workflow **« Deploy web (LWS) »** (`.github/workflows/deploy_web.yml`, script `scripts/deploy_lws.py`) : compile Flutter web (3.47.6) puis envoie par SFTP.
Le propriétaire ne fait rien sur son ordinateur. Répondre en français, simplement.

## Marche à suivre
1. Pousser les changements sur `main` (après `flutter analyze` et `flutter test` propres).
2. Lancer le workflow `deploy_web.yml` (`ref: main`) avec `actions_run_trigger` ; il dure ~3 min. Programmer un rappel (`send_later`), puis `list_workflow_runs` / `get_job_logs`.
3. Dire au propriétaire de recharger avec **Ctrl+F5** (ou fenêtre privée) pour passer le cache. Le site de production n'est pas joignable depuis le bac à sable : ne pas prétendre l'avoir vu.

## Secrets du dépôt (une seule fois)
`LWS_HOST`, `LWS_USER`, `LWS_PASS`, `LWS_DIR` (ex. `/htdocs`), `LWS_PORT` (facultatif), `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
Le workflow imprime les longueurs (jamais les valeurs). Ne jamais demander de secret dans la conversation.

## Pièges déjà rencontrés
* Secrets dans le mauvais dépôt (Colis-Tracker au lieu de Telima).
* `LWS_DIR` manquant → « Permission denied » au premier `mkdir`.
* `SUPABASE_URL` vide ou avec un chemin (`/rest/v1/`) → site cassé (« Invalid path specified in request URL ») : le workflow nettoie l'adresse.

## Autre projet
Copier `deploy_web.yml.modele` en `.github/workflows/deploy_web.yml` et `deploy_lws.py.modele` en `scripts/deploy_lws.py`, adapter le dossier de l'application et les secrets.
