{{flutter_js}}
{{flutter_build_config}}

// Pas de service worker Flutter : il recharge la page apres le chargement (boucle de rechargement).
// Le site installe lui-meme un petit sw.js (voir index.html) pour l installation en application.
_flutter.loader.load();
