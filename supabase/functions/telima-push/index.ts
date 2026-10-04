// Envoi des notifications push (Firebase Cloud Messaging) aux téléphones d'un utilisateur.
// Appelée par le déclencheur telima.tg_notification_push à chaque nouvelle notification.
// POST { id } + en-tête x-telima-secret (secret partagé stocké dans telima.push_secrets).
// La notification s'affiche en bannière même application fermée (canal « telima_alerts »).
import { admin, json } from "../_shared/common.ts";

type ServiceAccount = { project_id: string; client_email: string; private_key: string; token_uri?: string };

let cachedToken: { value: string; exp: number } | null = null;
let cachedSecrets: { at: number; webhook?: string; sa?: ServiceAccount } | null = null;

async function secrets() {
  if (cachedSecrets && Date.now() - cachedSecrets.at < 60_000) return cachedSecrets;
  const rows = await admin.select<{ key: string; value: string }>("push_secrets", "select=key,value");
  const map = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  cachedSecrets = {
    at: Date.now(),
    webhook: map["webhook_secret"],
    sa: map["fcm_service_account"] ? JSON.parse(map["fcm_service_account"]) : undefined,
  };
  return cachedSecrets;
}

const b64url = (data: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

/** Jeton d'accès Google (OAuth2, compte de service, signature RS256). */
async function accessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.exp - 120 > Date.now() / 1000) return cachedToken.value;
  const now = Math.floor(Date.now() / 1000);
  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(sig)}`,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`OAuth Google : ${data.error_description ?? data.error ?? res.status}`);
  cachedToken = { value: data.access_token, exp: now + (data.expires_in ?? 3600) };
  return cachedToken.value;
}

function routeFor(type: string, data: Record<string, unknown>): string {
  const delivery = data?.delivery_id ? String(data.delivery_id) : null;
  if (type === "message" && delivery) return `/chat/${delivery}`;
  return "/notifications";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  try {
    const s = await secrets();
    if (!s.webhook || req.headers.get("x-telima-secret") !== s.webhook) return json({ error: "Non autorisé" }, 401);
    if (!s.sa) return json({ skipped: "Firebase non configuré" });

    const { id } = await req.json();
    const [n] = await admin.select<{ id: number; user_id: string; type: string; title: string; body: string; data: Record<string, unknown> }>(
      "notifications", `select=id,user_id,type,title,body,data&id=eq.${Number(id)}`);
    if (!n) return json({ skipped: "notification introuvable" });
    const devices = await admin.select<{ token: string }>("device_tokens", `select=token&user_id=eq.${n.user_id}`);
    if (!devices.length) return json({ sent: 0 });

    const token = await accessToken(s.sa);
    const tag = `telima-${n.id}`;
    const route = routeFor(n.type, n.data);
    let sent = 0;
    const removed: string[] = [];
    await Promise.all(devices.map(async ({ token: device }) => {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${s.sa!.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: device,
            notification: { title: n.title, body: n.body },
            data: { route, type: n.type, notification_id: String(n.id) },
            android: {
              priority: "HIGH",
              ttl: "86400s",
              notification: {
                channel_id: "telima_alerts",
                tag,
                icon: "ic_stat_telima",
                color: "#3D8B5F",
                default_sound: true,
                default_vibrate_timings: true,
                notification_priority: "PRIORITY_MAX",
                visibility: "PUBLIC",
              },
            },
          },
        }),
      });
      if (res.ok) { sent++; return; }
      const err = await res.json().catch(() => ({}));
      const code = err?.error?.details?.find((d: { errorCode?: string }) => d.errorCode)?.errorCode ?? err?.error?.status;
      // téléphone désinstallé ou jeton périmé : on l'oublie
      if (res.status === 404 || code === "UNREGISTERED" || code === "INVALID_ARGUMENT") {
        removed.push(device);
        await admin.remove("device_tokens", `token=eq.${encodeURIComponent(device)}`);
      } else {
        console.error("FCM", res.status, JSON.stringify(err));
      }
    }));
    return json({ sent, removed: removed.length });
  } catch (e) {
    console.error(e);
    return json({ error: (e as Error).message }, 500);
  }
});
