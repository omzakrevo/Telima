// Service worker de Telima : rend la version web installable comme une application
// et décompresse le fichier principal (main.dart.js) à partir de sa copie compressée main.dart.gzbin.
// L'hébergeur n'envoie pas le JavaScript compressé : 5,7 Mo à télécharger au lieu d'environ 1,6 Mo.
// En cas de problème (copie absente, navigateur ancien…), le fichier normal est utilisé : rien ne casse.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

let memo = null; // la même page demande le fichier deux fois de suite : on garde la version décompressée 1 minute

function scriptResponse(js) {
  return new Response(js, { status: 200, headers: { "Content-Type": "text/javascript; charset=utf-8", "Cache-Control": "no-cache" } });
}

async function mainScript(request) {
  if (memo && Date.now() - memo.at < 60000) return scriptResponse(memo.js);
  try {
    if (typeof DecompressionStream !== "function") throw new Error("pas de décompression");
    const res = await fetch("main.dart.gzbin", { cache: "no-cache" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const buf = await res.arrayBuffer();
    const b = new Uint8Array(buf);
    let js = buf;
    if (b[0] === 0x1f && b[1] === 0x8b) {
      js = await new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
    }
    const head = new Uint8Array(js, 0, Math.min(4, js.byteLength));
    // une page HTML (copie absente, redirigée vers l'application) n'est pas du JavaScript
    if (head[0] === 0x3c || js.byteLength < 100000) throw new Error("contenu inattendu");
    memo = { at: Date.now(), js };
    return scriptResponse(js);
  } catch (e) {
    return fetch(request);
  }
}

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method === "GET" && req.mode !== "navigate") {
    const url = new URL(req.url);
    if (url.origin === self.location.origin && url.pathname.endsWith("/main.dart.js")) {
      event.respondWith(mainScript(req));
      return;
    }
  }
  if (req.mode !== "navigate") return;
  event.respondWith(
    fetch(req).catch(() => new Response(
      "<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Telima</title>" +
      "<body style='font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#FAFAF8;color:#1C2420;text-align:center;padding:16px'>" +
      "<div><h2>Pas de connexion Internet</h2><p>Telima a besoin d'Internet. Vérifiez votre connexion puis réessayez.</p>" +
      "<button onclick='location.reload()' style='background:#F08A3C;color:#fff;border:0;border-radius:999px;padding:12px 22px;font-size:15px'>Réessayer</button></div></body>",
      { headers: { "Content-Type": "text/html; charset=utf-8" } }))
  );
});
