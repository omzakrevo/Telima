// Outils partagés des fonctions Edge Telima.
// Aucune dépendance externe : appels directs aux API REST et Auth de Supabase (fetch natif).

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
/** Schéma PostgreSQL de Telima (projet Supabase partagé avec d'autres applications). */
const DB_SCHEMA = Deno.env.get("TELIMA_DB_SCHEMA") ?? "telima";

function serviceHeaders(extra: Record<string, string> = {}): Record<string, string> {
  return {
    apikey: SERVICE_KEY,
    Authorization: `Bearer ${SERVICE_KEY}`,
    "Content-Type": "application/json",
    "Accept-Profile": DB_SCHEMA,
    "Content-Profile": DB_SCHEMA,
    ...extra,
  };
}

async function call<T>(method: string, path: string, body?: unknown, extraHeaders: Record<string, string> = {}): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    method,
    headers: serviceHeaders(extraHeaders),
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const msg = data?.msg ?? data?.message ?? data?.error_description ?? data?.error ?? `Erreur ${res.status}`;
    throw new Error(String(msg));
  }
  return data as T;
}

/** Accès service_role (contourne la RLS) — uniquement côté serveur. */
export const admin = {
  /** Utilisateur correspondant au jeton de l'appelant. */
  async getUserFromJwt(jwt: string): Promise<{ id: string } | null> {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${jwt}` } });
    if (!res.ok) return null;
    return await res.json();
  },
  createAuthUser(payload: Record<string, unknown>) {
    return call<{ id: string }>("POST", "/auth/v1/admin/users", payload);
  },
  updateAuthUser(id: string, payload: Record<string, unknown>) {
    return call<{ id: string }>("PUT", `/auth/v1/admin/users/${id}`, payload);
  },
  select<T>(table: string, query: string) {
    return call<T[]>("GET", `/rest/v1/${table}?${query}`);
  },
  insert(table: string, row: Record<string, unknown>) {
    return call("POST", `/rest/v1/${table}`, row, { Prefer: "return=minimal" });
  },
  update(table: string, query: string, patch: Record<string, unknown>) {
    return call("PATCH", `/rest/v1/${table}?${query}`, patch, { Prefer: "return=minimal" });
  },
  remove(table: string, query: string) {
    return call("DELETE", `/rest/v1/${table}?${query}`, undefined, { Prefer: "return=minimal" });
  },
  rpc<T>(fn: string, args: Record<string, unknown>) {
    return call<T>("POST", `/rest/v1/rpc/${fn}`, args);
  },
};

/** Même règle que public.normalize_phone() : +226 par défaut pour un numéro à 8 chiffres. */
export function normalizePhone(input: string): string {
  let v = (input ?? "").replace(/[^0-9+]/g, "");
  if (v.startsWith("00")) v = "+" + v.slice(2);
  if (/^[0-9]{8}$/.test(v)) v = "+226" + v;
  if (/^226[0-9]{8}$/.test(v)) v = "+" + v;
  if (!/^\+[0-9]{8,15}$/.test(v)) throw new Error("Numéro de téléphone invalide");
  return v;
}

/** Le téléphone est l'identifiant : il est converti en adresse technique pour Supabase Auth. */
export function phoneToAuthEmail(phone: string): string {
  return `${normalizePhone(phone).replace("+", "")}@telima.app`;
}
