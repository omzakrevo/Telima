// Crée les comptes de test Client, Livreur (approuvé, avec moto) et Administrateur.
//
// Usage :
//   SUPABASE_URL=https://xxx.supabase.co SUPABASE_SERVICE_ROLE_KEY=xxx node seed_accounts.mjs
//
// La clé service_role ne doit JAMAIS être mise dans l'application : uniquement sur votre poste.
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("Définissez SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}
const admin = createClient(url, key, { db: { schema: "telima" }, auth: { persistSession: false, autoRefreshToken: false } });

const PASSWORD = process.env.TEST_PASSWORD;
if (!PASSWORD) throw new Error("Définissez TEST_PASSWORD (mot de passe des comptes de test)");
const accounts = [
  { phone: "+22670000001", full_name: "Awa Ouédraogo", role: "client" },
  { phone: "+22670000002", full_name: "Issa Sawadogo", role: "driver" },
  { phone: "+22670000003", full_name: "Admin Telima", role: "admin" },
  { phone: "+22670000004", full_name: "Opérateur Telima", role: "operator" },
];

const { data: city } = await admin.from("cities").select("id").eq("name", "Ouagadougou").single();

for (const a of accounts) {
  const email = `${a.phone.replace("+", "")}@telima.app`;
  let userId;
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password: PASSWORD,
    email_confirm: true,
    user_metadata: { phone: a.phone, full_name: a.full_name, city_id: city?.id, role: a.role === "driver" ? "driver" : "client" },
  });
  if (error) {
    if (!/already/i.test(error.message)) throw error;
    const { data: existing } = await admin.from("users").select("id").eq("phone", a.phone).single();
    userId = existing.id;
    await admin.auth.admin.updateUserById(userId, { password: PASSWORD });
    console.log(`• ${a.role.padEnd(8)} existe déjà : ${a.phone}`);
  } else {
    userId = data.user.id;
    console.log(`✓ ${a.role.padEnd(8)} créé : ${a.phone}`);
  }

  if (a.role === "admin" || a.role === "operator") {
    await admin.from("users").update({ role: a.role }).eq("id", userId);
  }
  if (a.role === "driver") {
    await admin.from("drivers").update({
      status: "approved",
      approved_at: new Date().toISOString(),
      id_document_number: "B12345678",
      city_id: city?.id,
      // position initiale au centre de Ouagadougou (mise à jour par le GPS dès la connexion)
      current_lat: 12.3700,
      current_lng: -1.5200,
      last_location_at: new Date().toISOString(),
    }).eq("user_id", userId);
    const { data: v } = await admin.from("vehicles").select("id").eq("driver_id", userId).eq("is_active", true).maybeSingle();
    if (!v) {
      await admin.from("vehicles").insert({ driver_id: userId, type: "moto", brand: "Haojue", model: "HJ125", color: "Rouge", plate_number: "11 JK 2233", is_active: true });
    }
  }
}

console.log(`\nMot de passe de tous les comptes : ${PASSWORD}`);
console.log("Connexion dans l'application avec le numéro (ex. 70 00 00 01) et ce mot de passe.");
