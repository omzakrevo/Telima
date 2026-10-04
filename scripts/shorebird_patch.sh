#!/usr/bin/env bash
# Envoie une mise à jour invisible (correctif Shorebird) de la version installée sur les téléphones.
# Usage :  SHOREBIRD_TOKEN=sb_api_... ./scripts/shorebird_patch.sh 1.5.0+2006
# Les téléphones l'appliquent seuls au prochain redémarrage de l'application.
set -euo pipefail
RELEASE="${1:?Indiquez la version de base, ex. 1.5.0+2006}"
: "${SHOREBIRD_TOKEN:?Définissez SHOREBIRD_TOKEN (clé API Shorebird)}"
cd "$(dirname "$0")/../app"
shorebird patch --platforms=android --release-version="$RELEASE" --dart-define-from-file=env.cloud.json --allow-asset-diffs
