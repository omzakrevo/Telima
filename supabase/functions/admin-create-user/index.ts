// Création d'un compte (client, livreur, opérateur, admin) par un administrateur.
// POST { phone, full_name, password, role, city_id?, driver?: { vehicle_type, plate_number, id_document_number, license_number, approve } }
import { admin, corsHeaders, json, normalizePhone, phoneToAuthEmail } from "../_shared/common.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const caller = await admin.getUserFromJwt(jwt);
    if (!caller) return json({ error: "Non authentifié" }, 401);

    const [me] = await admin.select<{ role: string; is_active: boolean }>("users", `id=eq.${caller.id}&select=role,is_active`);
    if (!me || !me.is_active || me.role !== "admin") return json({ error: "Accès réservé aux administrateurs" }, 403);

    const body = await req.json();
    const phone = normalizePhone(body.phone);
    const role: string = body.role ?? "client";
    if (!["client", "driver", "operator", "admin"].includes(role)) return json({ error: "Rôle invalide" }, 400);
    if (!body.full_name || String(body.full_name).trim().length < 2) return json({ error: "Nom obligatoire" }, 400);
    if (!body.password || String(body.password).length < 6) return json({ error: "Mot de passe : 6 caractères minimum" }, 400);

    let created: { id: string };
    try {
      created = await admin.createAuthUser({
        email: phoneToAuthEmail(phone),
        password: body.password,
        email_confirm: true,
        user_metadata: {
          phone,
          full_name: String(body.full_name).trim(),
          city_id: body.city_id ?? null,
          role: role === "driver" ? "driver" : "client",
        },
      });
    } catch (e) {
      const msg = (e as Error).message;
      return json({ error: /already|registered|exists/i.test(msg) ? "Un compte existe déjà avec ce numéro" : msg }, 400);
    }
    const uid = created.id;

    if (role === "operator" || role === "admin") {
      await admin.update("users", `id=eq.${uid}`, { role });
    }

    if (role === "driver" && body.driver) {
      const d = body.driver;
      await admin.update("drivers", `user_id=eq.${uid}`, {
        id_document_number: d.id_document_number ?? null,
        license_number: d.license_number ?? null,
        status: d.approve ? "approved" : "pending",
        approved_at: d.approve ? new Date().toISOString() : null,
        approved_by: d.approve ? caller.id : null,
      });
      if (d.vehicle_type) {
        await admin.insert("vehicles", {
          driver_id: uid,
          type: d.vehicle_type,
          plate_number: d.plate_number ? String(d.plate_number).toUpperCase() : null,
          brand: d.brand ?? null,
          model: d.model ?? null,
          is_active: true,
        });
      }
    }

    await admin.insert("admin_logs", {
      admin_id: caller.id,
      action: "create_user",
      entity: "users",
      entity_id: uid,
      details: { phone, role },
    });

    return json({ id: uid, phone, role });
  } catch (e) {
    return json({ error: (e as Error).message }, 400);
  }
});
