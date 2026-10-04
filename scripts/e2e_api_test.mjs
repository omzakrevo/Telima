// Test de bout en bout des parcours Client / Livreur / Administrateur via l'API Supabase
// (mêmes appels que l'application Flutter : Auth, RLS, RPC, Storage, Realtime, fonctions Edge).
//
// Usage : SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE_KEY=... node e2e_api_test.mjs
// Prérequis : node seed_accounts.mjs (comptes 70000001..4, mot de passe = TEST_PASSWORD)
import { createClient } from "@supabase/supabase-js";

const URL_ = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const PASSWORD = process.env.TEST_PASSWORD;
if (!PASSWORD) throw new Error("Définissez TEST_PASSWORD (mot de passe des comptes de test)");
let passed = 0;

function ok(cond, label) {
  if (!cond) throw new Error(`ÉCHEC : ${label}`);
  passed++;
  console.log(`  ✓ ${label}`);
}
async function expectError(promise, label) {
  const { error } = await promise;
  ok(!!error, `${label} (refusé : ${error?.message?.slice(0, 70)})`);
}
const email = (phone) => `${phone.replace("+", "")}@telima.app`;
async function login(phone, password = PASSWORD) {
  const c = createClient(URL_, ANON, { db: { schema: "telima" }, auth: { persistSession: false } });
  const { error } = await c.auth.signInWithPassword({ email: email(phone), password });
  if (error) throw new Error(`connexion ${phone} : ${error.message}`);
  return c;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

console.log("\n1. Inscription d'un nouveau client (comme l'écran « Créer un compte »)");
const newPhone = `+2267${String(Date.now()).slice(-7)}`;
const anon = createClient(URL_, ANON, { db: { schema: "telima" }, auth: { persistSession: false } });
const { data: cities } = await anon.from("cities").select("id,name");
ok(cities.length >= 4, `villes visibles par un visiteur (${cities.map((c) => c.name).join(", ")})`);
const { data: visitorQuote } = await anon.rpc("quote_delivery", { p_pickup_lat: 12.3686, p_pickup_lng: -1.5275, p_dropoff_lat: 12.326, p_dropoff_lng: -1.495 });
ok(visitorQuote.total_price > 0, `devis visiteur : ${visitorQuote.distance_km} km → ${visitorQuote.total_price} FCFA`);
const signupRes = await anon.functions.invoke("telima-signup", {
  body: { phone: newPhone, password: "secret123", full_name: "Nouveau Client", city_id: cities[0].id, role: "client" },
});
ok(!signupRes.error && signupRes.data?.ok, "inscription sans e-mail de confirmation (fonction telima-signup)");
const signin = await anon.auth.signInWithPassword({ email: email(newPhone), password: "secret123" });
ok(!signin.error && signin.data.session, "connexion immédiate après inscription");
const { data: newProfile } = await anon.from("users").select("*").single();
ok(newProfile.phone === newPhone && newProfile.role === "client", "profil créé avec le téléphone comme identifiant");
await expectError(anon.from("users").update({ role: "admin" }).eq("id", newProfile.id), "un client ne peut pas se donner le rôle admin");

console.log("\n2. Client : devis, photo du colis, création de la livraison");
const client = await login("+22670000001");
const { data: { user: clientUser } } = await client.auth.getUser();
const { data: quote } = await client.rpc("quote_delivery", {
  p_pickup_lat: 12.3686, p_pickup_lng: -1.5275, p_dropoff_lat: 12.326, p_dropoff_lng: -1.495,
  p_size: "petit", p_fragile: true, p_route_km: 8.4,
});
ok(quote.distance_km === 8.4, `distance routière acceptée : ${quote.distance_km} km, total ${quote.total_price} FCFA`);
const photoPath = `${clientUser.id}/colis-${Date.now()}.png`;
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
const up = await client.storage.from("telima-package-photos").upload(photoPath, png, { contentType: "image/png" });
ok(!up.error, "photo du colis envoyée dans le stockage privé");
await expectError(client.storage.from("telima-package-photos").upload(`autre-utilisateur/x.png`, png, { contentType: "image/png" }), "envoi hors de son dossier interdit");

// le livreur est déjà en ligne quand la commande arrive
const driver = await login("+22670000002");
const { data: { user: driverUser } } = await driver.auth.getUser();
const { data: dOnline } = await driver.rpc("set_driver_online", { p_online: true, p_lat: 12.37, p_lng: -1.52 });
ok(dOnline.is_online, "livreur EN LIGNE");

const { data: delivery, error: cErr } = await client.rpc("create_delivery", {
  p: {
    pickup: { address: "Marché Rood Woko, boutique à côté du marché", lat: 12.3686, lng: -1.5275, contact_name: "Awa", contact_phone: "70000001", instructions: "Appelez-moi en arrivant" },
    dropoff: { address: "Ouaga 2000, maison derrière la station", lat: 12.326, lng: -1.495, contact_name: "Moussa", contact_phone: "76000000" },
    package: { category: "petit_colis", description: "Chaussures", quantity: 2, fragile: true, size: "petit", photo_path: photoPath },
    vehicle_type: "moto", payment_method: "cash", route_km: 8.4,
  },
});
ok(!cErr, `livraison créée : ${delivery?.code} (${delivery?.status}) ${delivery?.total_price} FCFA`);
ok(/^LIV-\d{4}-\d{6}$/.test(delivery.code), "numéro unique au format LIV-2026-000001");
ok(delivery.total_price === quote.total_price, "prix enregistré = prix affiché avant confirmation");
const { data: otp } = await client.rpc("get_delivery_otp", { p_delivery_id: delivery.id });
ok(/^\d{4}$/.test(otp), `code de livraison visible par le client : ${otp}`);

console.log("\n3. Isolation des données (RLS)");
const other = anon; // le nouveau client inscrit
const { data: leaked } = await other.from("deliveries").select("id").eq("id", delivery.id);
ok(leaked.length === 0, "un autre client ne voit pas la livraison");
await expectError(other.rpc("get_delivery_otp", { p_delivery_id: delivery.id }), "un autre client ne peut pas lire le code");
await expectError(other.from("delivery_secrets").select("*"), "table des codes inaccessible");

console.log("\n4. Livreur : demande visible, acceptation");
const { data: reqs } = await driver.rpc("get_available_requests");
const req = reqs.find((r) => r.id === delivery.id);
ok(req && req.distance_to_pickup_km > 0, `demande visible : ${req?.pickup_address} → ${req?.dropoff_address}, ${req?.driver_earning} FCFA, à ${req?.distance_to_pickup_km} km`);
ok(!("pickup_contact_phone" in req), "téléphones masqués avant acceptation");
const { data: driverNotifs } = await driver.from("notifications").select("type").eq("type", "new_request");
ok(driverNotifs.length >= 1, "notification « Nouvelle demande » reçue par le livreur");
const { data: hacked } = await driver.from("deliveries").update({ status: "completed" }).eq("id", delivery.id).select();
ok((hacked ?? []).length === 0, "le livreur ne peut pas modifier le statut directement (0 ligne modifiée)");
const { count: visibleBefore } = await driver.from("deliveries").select("id", { count: "exact", head: true }).eq("id", delivery.id);
ok(visibleBefore === 0, "le livreur ne voit pas la commande avant de l'accepter");

// Le client écoute la position du livreur en temps réel
const positions = [];
const channel = client.channel(`loc-${delivery.id}`).on("postgres_changes",
  { event: "INSERT", schema: "telima", table: "delivery_locations", filter: `delivery_id=eq.${delivery.id}` },
  (p) => positions.push(p.new));
await new Promise((resolve) => channel.subscribe((s) => s === "SUBSCRIBED" && resolve()));
await sleep(5000); // Realtime : l'écoute Postgres devient active quelques secondes après SUBSCRIBED

const { data: accepted, error: aErr } = await driver.rpc("accept_delivery", { p_delivery_id: delivery.id });
ok(!aErr && accepted.status === "assigned", `course acceptée, arrivée estimée ${accepted.eta_minutes} min`);
const driver2 = await login("+22670000003"); // l'admin n'est pas livreur : vérifie le refus
await expectError(driver2.rpc("accept_delivery", { p_delivery_id: delivery.id }), "impossible d'accepter une course déjà prise");
await expectError(driver.rpc("get_delivery_otp", { p_delivery_id: delivery.id }), "le livreur ne peut pas lire le code de livraison");
const { data: canSeePhoto } = await driver.storage.from("telima-package-photos").createSignedUrl(photoPath, 60);
ok(!!canSeePhoto?.signedUrl, "le livreur assigné peut voir la photo du colis");

console.log("\n5. Client : informations du livreur");
const { data: info } = await client.rpc("get_delivery_driver", { p_delivery_id: delivery.id });
ok(info.first_name === "Issa" && info.plate_number === "11 JK 2233", `livreur affiché : ${info.first_name}, ${info.vehicle_type}, ${info.plate_number}, note ${info.rating_avg}`);

console.log("\n6. Étapes de la course + suivi GPS + messagerie");
for (const s of ["to_pickup"]) {
  const { error } = await driver.rpc("driver_advance_status", { p_delivery_id: delivery.id, p_status: s, p_lat: 12.37, p_lng: -1.52 });
  ok(!error, `étape : ${s}`);
}
await expectError(driver.rpc("driver_advance_status", { p_delivery_id: delivery.id, p_status: "in_transit" }), "saut d'étape interdit");
await driver.rpc("driver_update_location", { p_lat: 12.3687, p_lng: -1.5274 });
for (let i = 0; i < 20 && positions.length === 0; i++) await sleep(500);

ok(positions.length >= 1, `position reçue en temps réel par le client (${positions[0]?.lat}, ${positions[0]?.lng})`);
const { data: nearNotif } = await client.from("notifications").select("body").eq("type", "driver_near");
ok(nearNotif.some((n) => n.body.includes("quelques minutes")), "« Votre livreur arrive dans quelques minutes. »");
for (const s of ["at_pickup", "picked_up", "in_transit", "at_dropoff"]) {
  const { error } = await driver.rpc("driver_advance_status", { p_delivery_id: delivery.id, p_status: s });
  ok(!error, `étape : ${s}`);
}
const { error: idem } = await driver.rpc("driver_advance_status", { p_delivery_id: delivery.id, p_status: "at_dropoff" });
ok(!idem, "étape rejouée sans erreur (reprise après coupure réseau)");
await client.from("messages").insert({ delivery_id: delivery.id, sender_id: clientUser.id, body: "Je suis devant le portail bleu" });
await driver.from("messages").insert({ delivery_id: delivery.id, sender_id: driverUser.id, body: "J'arrive" });
const { data: msgs } = await client.from("messages").select("body").eq("delivery_id", delivery.id);
ok(msgs.length === 2, "messagerie client ↔ livreur");
await expectError(anon.from("messages").insert({ delivery_id: delivery.id, sender_id: newProfile.id, body: "spam" }), "un tiers ne peut pas écrire dans la conversation");

console.log("\n7. Preuve de livraison (code OTP) et règlement");
const { data: wrong } = await driver.rpc("complete_delivery", { p_delivery_id: delivery.id, p_otp: otp === "0000" ? "1111" : "0000" });
ok(!wrong || wrong.id === null, "mauvais code refusé");
const { data: w0 } = await driver.from("wallets").select("balance").maybeSingle();
const balanceBefore = w0?.balance ?? 0;
const proofPath = `${driverUser.id}/remise-${Date.now()}.png`;
await driver.storage.from("telima-proofs").upload(proofPath, png, { contentType: "image/png" });
const { data: done, error: dErr } = await driver.rpc("complete_delivery", { p_delivery_id: delivery.id, p_otp: otp, p_receiver_name: "Moussa", p_photo_path: proofPath });
ok(!dErr && done.status === "completed", "« Livraison terminée avec succès. »");
const { data: dWallet } = await driver.from("wallets").select("balance").single();
ok(dWallet.balance === balanceBefore - done.commission_amount, `commission débitée du portefeuille livreur (paiement espèces) : solde ${dWallet.balance} FCFA`);
const { data: hist } = await client.from("delivery_status_history").select("status, created_at").eq("delivery_id", delivery.id);
ok(hist.length === 10, `10 étapes horodatées : ${hist.map((h) => h.status).join(" → ")}`);
const { data: proofUrl } = await client.storage.from("telima-proofs").createSignedUrl(proofPath, 60);
ok(!!proofUrl?.signedUrl, "le client peut voir la photo de remise");
const { data: earnings } = await driver.rpc("get_driver_earnings");
ok(earnings.today >= done.driver_earning, `revenus du jour : ${earnings.today} FCFA (${earnings.count_today} course)`);

console.log("\n8. Évaluation");
const { error: rErr } = await client.rpc("rate_delivery", { p_delivery_id: delivery.id, p_stars: 5, p_comment: "Rapide et poli" });
ok(!rErr, "note 5 étoiles envoyée");
const { data: info2 } = await client.rpc("get_delivery_driver", { p_delivery_id: delivery.id });
ok(Number(info2.rating_avg) > 0, `note moyenne du livreur : ${info2.rating_avg}`);
const { data: clientNotifs } = await client.from("notifications").select("body").order("created_at");
ok(["Un livreur a accepté votre commande.", "Votre colis a été récupéré.", "Votre colis est en route.", "Livraison terminée."]
  .every((t) => clientNotifs.some((n) => n.body === t)), "notifications client du cahier des charges reçues");

console.log("\n9. Portefeuille : rechargement Orange Money (paiement manuel validé par l'administrateur)");
const adminEarly = await login("+22670000003");
const t9 = new Date(Date.now() - 5000).toISOString();
const { data: cw0 } = await client.from("wallets").select("balance").maybeSingle();
const clientBalance0 = cw0?.balance ?? 0;
const { data: topup } = await client.rpc("request_wallet_topup", { p_amount: 5000, p_method: "orange_money" });
await expectError(client.rpc("confirm_simulated_payment", { p_payment_id: topup.id }), "auto-confirmation impossible en mode manuel");
const smsRef = "PP" + Date.now().toString().slice(-8);
const { data: relayToken } = await adminEarly.rpc("admin_enable_sms_relay", { p_label: "Test e2e" });
ok(typeof relayToken === "string" && relayToken.length >= 32, "relais SMS activé sur le téléphone admin");
const { data: declared, error: decErr } = await client.rpc("declare_manual_payment", { p_payment_id: topup.id, p_payer_phone: newPhone, p_txn_ref: smsRef });
ok(!decErr && declared.status === "pending" && declared.metadata.declared_at, "client : « J'ai fait le paiement » enregistré");
const { data: staffN } = await adminEarly.from("notifications").select("type,body").eq("type", "payment_declared").order("created_at", { ascending: false }).limit(1);
ok(staffN.length === 1 && staffN[0].body.includes("5 000") || staffN[0]?.body.includes("5000"), "administrateur notifié du paiement à vérifier");
const smsBody = `Vous avez recu 5 000 FCFA du ${newPhone.replace("+226", "")}. ID Trans: ${smsRef}. Nouveau solde: 12 000 FCFA`;
const relayRes = await fetch(`${URL_}/functions/v1/telima-sms-relay`, { method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ token: relayToken, sender: "OrangeMoney", body: smsBody, received_at: Date.now() }) }).then((r) => r.json());
ok(relayRes.ok && relayRes.parsed.amount === 5000 && relayRes.parsed.ref === smsRef && relayRes.matched === true,
   `SMS Orange Money relayé, analysé et rapproché (${relayRes.parsed?.amount} FCFA, ${relayRes.parsed?.phone}, ${relayRes.parsed?.ref})`);
const badRelay = await fetch(`${URL_}/functions/v1/telima-sms-relay`, { method: "POST", headers: { "content-type": "application/json" },
  body: JSON.stringify({ token: "x".repeat(40), sender: "OrangeMoney", body: smsBody }) });
ok(badRelay.status === 401, "relais refusé sans clé valide");
const { data: stillPending } = await client.from("payments").select("status").eq("id", topup.id).single();
ok(stillPending.status === "pending", "le SMS ne valide jamais seul : décision de l'administrateur");
const { data: counts } = await adminEarly.rpc("admin_pending_counts");
ok(counts.payments_to_verify >= 1, `tableau de bord : ${counts.payments_to_verify} paiement(s) à vérifier`);
await expectError(client.rpc("admin_confirm_payment", { p_payment_id: topup.id, p_provider_ref: smsRef }), "un client ne peut pas valider son paiement");
const { data: paid } = await adminEarly.rpc("admin_confirm_payment", { p_payment_id: topup.id, p_provider_ref: smsRef });
ok(paid.status === "paid", "administrateur : paiement validé → portefeuille crédité");
const { data: topupN } = await client.from("notifications").select("title").in("title", ["Portefeuille rechargé", "Paiement en cours de vérification"]).gte("created_at", t9);
ok(topupN.length === 2, "client notifié : vérification puis rechargement");
const { data: topup2 } = await client.rpc("request_wallet_topup", { p_amount: 1500, p_method: "orange_money" });
await client.rpc("declare_manual_payment", { p_payment_id: topup2.id, p_payer_phone: newPhone, p_txn_ref: null });
const { data: rej } = await adminEarly.rpc("admin_reject_payment", { p_payment_id: topup2.id, p_reason: "Aucun SMS reçu" });
ok(rej.status === "failed", "administrateur : paiement non reçu refusé");
const { data: rejN } = await client.from("notifications").select("body").eq("title", "Paiement refusé").gte("created_at", t9);
ok(rejN.length === 1 && rejN[0].body.includes("Aucun SMS reçu"), "client notifié du refus avec le motif");
const { data: wDel } = await client.rpc("create_delivery", {
  p: { pickup: { address: "A", lat: 12.3686, lng: -1.5275 }, dropoff: { address: "B", lat: 12.35, lng: -1.51, contact_name: "X", contact_phone: "76000000" },
       package: { category: "document" }, payment_method: "wallet" },
});
ok(wDel.payment_status === "paid", `payé par portefeuille (${wDel.total_price} FCFA)`);
await client.rpc("cancel_delivery", { p_delivery_id: wDel.id, p_reason: "Test" });
const { data: cw } = await client.from("wallets").select("balance").single();
ok(cw.balance === clientBalance0 + 5000, "annulation : remboursement automatique dans le portefeuille");
const { data: mmDel } = await client.rpc("create_delivery", {
  p: { pickup: { address: "A", lat: 12.3686, lng: -1.5275 }, dropoff: { address: "B", lat: 12.35, lng: -1.51, contact_name: "X", contact_phone: "76000000" },
       package: { category: "nourriture" }, payment_method: "moov_money" },
});
ok(mmDel.status === "created", "Moov Money : « Nouvelle demande » tant que non payé");

console.log("\n10. Administrateur");
const adminC = await login("+22670000003");
const now = new Date();
const { data: stats } = await adminC.rpc("admin_dashboard_stats", { p_from: new Date(now - 86400000).toISOString(), p_to: new Date(+now + 60000).toISOString() });
ok(stats.completed >= 1 && stats.drivers_online >= 1, `tableau de bord : ${stats.orders} commandes, ${stats.completed} terminée(s), CA ${stats.revenue} FCFA, commissions ${stats.commissions}`);
await expectError(client.rpc("admin_dashboard_stats", { p_from: now.toISOString(), p_to: now.toISOString() }), "statistiques interdites à un client");
const { data: phoneOrder, error: poErr } = await adminC.rpc("admin_create_delivery", {
  p: { customer_phone: "65112233", customer_name: "Mme Kaboré", pickup: { address: "Pharmacie du Progrès", lat: 12.369, lng: -1.525 },
       dropoff: { address: "Gounghin", lat: 12.364, lng: -1.55, contact_name: "Mme Kaboré", contact_phone: "65112233" },
       package: { category: "autre" }, payment_method: "cash_on_delivery" },
});
ok(!poErr && phoneOrder.created_via === "admin", `commande téléphonique ${phoneOrder?.code}`);
const { data: assignable } = await adminC.rpc("admin_list_assignable_drivers", { p_delivery_id: phoneOrder.id });
ok(assignable.length >= 1, `${assignable.length} livreur(s) attribuable(s)`);
const { data: assigned } = await adminC.rpc("admin_assign_delivery", { p_delivery_id: phoneOrder.id, p_driver_id: driverUser.id });
ok(assigned.status === "assigned" && assigned.driver_id === driverUser.id, "attribution manuelle");
await adminC.rpc("cancel_delivery", { p_delivery_id: phoneOrder.id, p_reason: "Test admin" });
const { data: logs } = await adminC.from("admin_logs").select("action");
ok(logs.some((l) => l.action === "assign_delivery"), "action administrative journalisée");
await expectError(client.from("admin_logs").select("*").limit(1).then((r) => ({ error: r.data.length ? null : { message: "aucune ligne" } })), "journal invisible pour un client");

// Commission configurable
await adminC.from("app_settings").update({ value: { type: "percent", value: 20 } }).eq("key", "commission");
const { data: d20 } = await client.rpc("create_delivery", {
  p: { pickup: { address: "A", lat: 12.3686, lng: -1.5275 }, dropoff: { address: "B", lat: 12.35, lng: -1.51, contact_name: "X", contact_phone: "76000000" },
       package: { category: "document" }, payment_method: "cash" },
});
ok(d20.commission_value == 20 && d20.commission_amount === Math.round(d20.total_price * 0.2), `commission modifiée sans toucher au code (20 % → ${d20.commission_amount} FCFA)`);
await adminC.from("app_settings").update({ value: { type: "percent", value: 15 } }).eq("key", "commission");
await client.rpc("cancel_delivery", { p_delivery_id: d20.id, p_reason: "Test" });
await expectError(client.from("pricing_rules").update({ base_price: 1 }).eq("vehicle_type", "moto").select().then((r) => ({ error: r.data?.length ? null : { message: "aucune ligne modifiée" } })), "un client ne peut pas modifier les tarifs");

// Création d'un livreur par l'admin (fonction Edge)
const newDriverPhone = `+2267${String(Date.now() + 7).slice(-7)}`;
const { data: created, error: fnErr } = await adminC.functions.invoke("admin-create-user", {
  body: { phone: newDriverPhone, full_name: "Livreur Créé", password: "secret123", role: "driver", driver: { vehicle_type: "tricycle", plate_number: "22 AB 1234", id_document_number: "B999", approve: true } },
});
ok(!fnErr && created?.role === "driver", "livreur créé par l'administrateur (fonction Edge)");
const { error: forbiddenFn } = await client.functions.invoke("admin-create-user", { body: { phone: "70999999", full_name: "X", password: "secret123" } });
ok(!!forbiddenFn, "création de compte refusée à un client");

// Retrait livreur (Orange Money)
await adminC.rpc("admin_wallet_adjust", { p_user_id: driverUser.id, p_amount: 5000, p_description: "Commissions réglées + bonus" });
const { data: wd } = await driver.rpc("request_withdrawal", { p_amount: 1000, p_method: "orange_money", p_phone: "70000002" });
ok(wd.status === "pending", "demande de retrait Orange Money");
const { data: wdPaid } = await adminC.rpc("admin_process_withdrawal", { p_withdrawal_id: wd.id, p_approve: true, p_provider_ref: "OM-TEST-1" });
ok(wdPaid.status === "paid", "retrait validé par l'administrateur");

// Suspension
await adminC.rpc("admin_set_driver_status", { p_driver_id: driverUser.id, p_status: "suspended", p_note: "Test" });
await expectError(driver.rpc("set_driver_online", { p_online: true }), "livreur suspendu : impossible de passer en ligne");
await adminC.rpc("admin_set_driver_status", { p_driver_id: driverUser.id, p_status: "approved" });

console.log("\n11. Multi-destinations et compte professionnel");
const { data: biz } = await client.rpc("create_business_account", { p: { name: "Boutique Awa", type: "boutique", phone: "70000001", address: "Marché", lat: 12.3686, lng: -1.5275 } });
ok(!!biz.id, "compte professionnel créé");
const { data: batch } = await client.rpc("create_delivery_batch", {
  p: { pickup: { address: "Boutique Awa", lat: 12.3686, lng: -1.5275 }, payment_method: "cash", business_id: biz.id,
       stops: [1, 2, 3].map((i) => ({ dropoff: { address: `Client ${i}`, lat: 12.36 - i * 0.005, lng: -1.52 + i * 0.006, contact_name: `C${i}`, contact_phone: `7600000${i}` }, package: { category: "petit_colis" } })) },
});
ok(batch.length === 3 && batch[0].status === "searching" && batch[1].status === "created", `tournée de 3 arrêts : ${batch.map((b) => b.code).join(", ")}`);
await driver.rpc("set_driver_online", { p_online: true, p_lat: 12.37, p_lng: -1.52 }); // repasse en ligne après réactivation
const { data: accB, error: accErr } = await driver.rpc("accept_delivery", { p_delivery_id: batch[0].id });
ok(!accErr, "le livreur accepte la tournée");
const { data: allB } = await driver.from("deliveries").select("status").eq("batch_id", accB.batch_id);
ok(allB.every((b) => b.status === "assigned"), "un seul livreur pour toute la tournée");
for (const b of batch) await client.rpc("cancel_delivery", { p_delivery_id: b.id, p_reason: "Fin du test" });
await driver.rpc("set_driver_online", { p_online: false });

console.log("\n12. Récupération de compte");
const resetPhone = newPhone;
await anon.auth.signOut();
const anon2 = createClient(URL_, ANON, { db: { schema: "telima" }, auth: { persistSession: false } });
const { data: rq } = await anon2.rpc("request_password_reset", { p_phone: resetPhone });
ok(rq.sent && rq.simulation, "demande de code (mode simulation SMS)");
const { data: codes } = await adminC.from("password_reset_requests").select("code_plain").eq("phone", resetPhone).is("used_at", null);
ok(codes.length === 1, `code visible par l'administrateur : ${codes[0].code_plain}`);
const { error: badReset } = await anon2.functions.invoke("reset-password", { body: { phone: resetPhone, code: "000000", new_password: "nouveau123" } });
ok(!!badReset, "mauvais code refusé");
const { data: goodReset, error: resetErr } = await anon2.functions.invoke("reset-password", { body: { phone: resetPhone, code: codes[0].code_plain, new_password: "nouveau123" } });
ok(!resetErr && goodReset.ok, "mot de passe réinitialisé");
const relog = await login(resetPhone, "nouveau123");
ok(!!relog, "connexion avec le nouveau mot de passe");

console.log("\n13. Désactivation de compte");
const { error: deacErr } = await relog.rpc("deactivate_my_account");
ok(!deacErr, "compte désactivé par l'utilisateur");
const { data: deac } = await adminC.from("users").select("is_active").eq("phone", resetPhone).single();
ok(deac.is_active === false, "compte marqué inactif (connexion refusée par l'application)");

console.log("\n14. Course à faire (achat par le livreur)");
const client2 = await login("+22670000001");
const { data: q } = await client2.rpc("quote_service", { p_kind: "errand", p_from_lat: 12.36, p_from_lng: -1.52, p_to_lat: 12.36, p_to_lng: -1.52, p_vehicle: "moto" });
ok(q.total_price > 0, `prix d'une course à faire : ${q.total_price} FCFA`);
const { data: errand, error: eErr } = await client2.rpc("create_errand", { p: {
  dropoff: { address: "Ouaga 2000, villa 12", lat: 12.3600, lng: -1.5200 }, items: "2 plats de riz gras + 1 Fanta", category: "repas",
  budget: 4000, payment_method: "cash" } });
ok(!eErr && errand.kind === "errand" && errand.errand_items.includes("riz gras") && errand.total_price === q.total_price,
   `course à faire créée : ${errand?.code} · ${errand?.status}`);
const { data: eN } = await client2.from("notifications").select("title").eq("title", "Course enregistrée").gte("created_at", t9);
ok(eN.length >= 1, "client notifié : course enregistrée");
const drv = await login("+22670000002");
await drv.rpc("set_driver_services", { p_services: ["parcel", "errand", "ride"] });
await drv.rpc("set_driver_online", { p_online: true, p_lat: 12.361, p_lng: -1.521 });
const { data: av } = await drv.rpc("get_available_requests_v2");
ok(av.some((r) => r.id === errand.id && r.kind === "errand" && r.errand_items), "livreur : la course à faire apparaît avec la liste d'achats");
const { error: accErr2 } = await drv.rpc("accept_delivery", { p_delivery_id: errand.id });
ok(!accErr2, `livreur : course acceptée ${accErr2?.message ?? ""}`);
for (const st of ["to_pickup", "at_pickup"]) await drv.rpc("driver_advance_status", { p_delivery_id: errand.id, p_status: st });
await expectError(drv.rpc("driver_advance_status", { p_delivery_id: errand.id, p_status: "picked_up" }), "impossible de partir livrer sans saisir les achats");
const { data: bought } = await drv.rpc("driver_set_purchase", { p_delivery_id: errand.id, p_amount: 3500, p_shop: "Maquis Chez Tanti" });
ok(bought.purchase_amount === 3500, "livreur : achats saisis (3 500 FCFA)");
const { data: pN } = await client2.from("notifications").select("body").like("title", "Achats effectués%").order("created_at", { ascending: false }).limit(1);
ok(pN.length === 1 && pN[0].body.includes("Chez Tanti"), "client notifié du montant des achats");
const { error: advErr } = await drv.rpc("driver_advance_status", { p_delivery_id: errand.id, p_status: "picked_up" });
ok(!advErr, "livreur : en route vers le client après les achats");
await adminC.rpc("admin_wallet_adjust", { p_user_id: (await client2.auth.getUser()).data.user.id, p_amount: 3500, p_description: "Test achats" });
const { data: settled, error: sErr } = await client2.rpc("settle_purchase", { p_delivery_id: errand.id, p_method: "wallet" });
ok(!sErr && settled.purchase_settlement === "wallet", "client : achats remboursés au livreur par portefeuille");
await adminC.rpc("cancel_delivery", { p_delivery_id: errand.id, p_reason: "Fin du test" });

console.log("\n15. Transport de personnes (VTC)");
const { data: rq2 } = await client2.rpc("quote_service", { p_kind: "ride", p_from_lat: 12.3686, p_from_lng: -1.5275, p_to_lat: 12.35, p_to_lng: -1.51, p_vehicle: "moto" });
ok(rq2.total_price > 0, `prix moto-taxi : ${rq2.total_price} FCFA (${rq2.distance_km} km)`);
await expectError(client2.rpc("create_ride", { p: { pickup: { address: "A", lat: 12.3686, lng: -1.5275 }, dropoff: { address: "B", lat: 12.35, lng: -1.51 },
  vehicle_type: "moto", passengers: 2, payment_method: "cash" } }), "moto-taxi : un seul passager");
const { data: ride, error: rideErr } = await client2.rpc("create_ride", { p: { pickup: { address: "Rond-point des Nations Unies", lat: 12.3686, lng: -1.5275 },
  dropoff: { address: "Gare de l'Est", lat: 12.35, lng: -1.51 }, vehicle_type: "moto", passengers: 1, payment_method: "cash" } });
ok(!rideErr && ride.kind === "ride" && ride.status === "searching", `trajet demandé : ${ride?.code}`);
const { data: av2 } = await drv.rpc("get_available_requests_v2");
const hasRide = av2.some((r) => r.id === ride.id && r.kind === "ride");
const { data: myVeh } = await drv.from("vehicles").select("type").eq("is_active", true).maybeSingle();
ok(myVeh?.type === "moto" ? hasRide : !hasRide, `chauffeur (${myVeh?.type}) : trajet ${hasRide ? "proposé" : "non proposé (véhicule différent)"}`);
await drv.rpc("set_driver_services", { p_services: ["parcel", "errand"] });
const { data: av3 } = await drv.rpc("get_available_requests_v2");
ok(!av3.some((r) => r.id === ride.id), "sans l'option transport de personnes, le trajet n'est pas proposé");
await drv.rpc("set_driver_services", { p_services: ["parcel", "errand", "ride"] });
await client2.rpc("cancel_delivery", { p_delivery_id: ride.id, p_reason: "Fin du test" });
await adminEarly.rpc("admin_disable_sms_relay", { p_token: relayToken });

await client.removeAllChannels();
console.log(`\n✅ ${passed} vérifications réussies`);
process.exit(0);
