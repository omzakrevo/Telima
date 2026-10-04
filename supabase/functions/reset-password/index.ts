// Récupération de compte : vérifie le code reçu (SMS ou communiqué par le support) et définit le nouveau mot de passe.
// POST { phone, code, new_password }
import { admin, corsHeaders, json, normalizePhone } from "../_shared/common.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { phone, code, new_password } = await req.json();
    if (!new_password || String(new_password).length < 6) {
      return json({ error: "Le mot de passe doit contenir au moins 6 caractères" }, 400);
    }
    const userId = await admin.rpc<string | null>("consume_password_reset", {
      p_phone: normalizePhone(phone),
      p_code: String(code ?? ""),
    });
    if (!userId) return json({ error: "Code incorrect" }, 400);

    await admin.updateAuthUser(userId, { password: new_password });
    return json({ ok: true });
  } catch (e) {
    return json({ error: (e as Error).message }, 400);
  }
});
