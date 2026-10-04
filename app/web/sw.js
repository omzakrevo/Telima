// Service worker de Telima : rend la version web installable comme une application.
// Il ne met rien en cache : chaque visite charge la dernière version du site.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
self.addEventListener("fetch", (event) => {
  if (event.request.mode !== "navigate") return;
  event.respondWith(
    fetch(event.request).catch(() => new Response(
      "<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Telima</title>" +
      "<body style='font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#F6FAF7;color:#1C2420;text-align:center;padding:16px'>" +
      "<div><h2>Pas de connexion Internet</h2><p>Telima a besoin d'Internet. Vérifiez votre connexion puis réessayez.</p>" +
      "<button onclick='location.reload()' style='background:#3D8B5F;color:#fff;border:0;border-radius:999px;padding:12px 22px;font-size:15px'>Réessayer</button></div></body>",
      { headers: { "Content-Type": "text/html; charset=utf-8" } }))
  );
});
