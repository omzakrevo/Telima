// Inscription d'un client ou d'un livreur (écran « Créer un compte »).
// Le téléphone est l'identifiant : le compte est créé directement confirmé, aucun e-mail n'est envoyé.
// POST { phone, password, full_name, city_id?, role: "client" | "driver" }
import { admin, corsHeaders, json, normalizePhone, phoneToAuthEmail } from "../_shared/common.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  try {
    const body = await req.json();
    const phone = normalizePhone(String(body.phone ?? ""));
    const fullName = String(body.full_name ?? "").trim();
    const password = String(body.password ?? "");
    const role = body.role === "driver" ? "driver" : "client";
    const cityId = typeof body.city_id === "string" && UUID.test(body.city_id) ? body.city_id : null;

    if (fullName.length < 2 || fullName.length > 80) return json({ error: "Nom complet obligatoire" }, 400);
    if (password.length < 6 || password.length > 72) return json({ error: "Mot de passe : 6 caractères minimum" }, 400);

    try {
      await admin.createAuthUser({
        email: phoneToAuthEmail(phone),
        password,
        email_confirm: true,
        user_metadata: { phone, full_name: fullName, city_id: cityId, role },
      });
    } catch (e) {
      const msg = (e as Error).message;
      return json({ error: /already|registered|exists/i.test(msg) ? "Un compte existe déjà avec ce numéro" : msg }, 400);
    }
    return json({ ok: true, phone });
  } catch (e) {
    return json({ error: (e as Error).message }, 400);
  }
});
