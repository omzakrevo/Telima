# Liens profonds Android : telimatchi.com/r/<slug>

## Configuration intégrée dans cette PR
- `app/android/app/src/main/AndroidManifest.xml` : configuration d'intent-filter avec `autoVerify="true"` pour `telimatchi.com/r/*` et `flutter_deeplinking_enabled`.
- `app/lib/main.dart` : activation de `usePathUrlStrategy()` pour avoir des URLs propres côté Web.
- `app/web/.well-known/assetlinks.json` : déclaration d'association de domaine pour `app.telima.telima`.
- `app/web/_headers` et `_redirects` : configuration Netlify pour servir le JSON `.well-known`.

## Étapes post-merge
1. Récupérer l'empreinte SHA-256 de votre clé `telima-signing.jks` et mettre à jour `app/web/.well-known/assetlinks.json`.
2. Déployer le Web sur Netlify.
3. Compiler et publier la nouvelle version Android (`shorebird release android` ou build classique).
