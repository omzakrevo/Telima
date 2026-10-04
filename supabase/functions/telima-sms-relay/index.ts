// Relais des SMS Mobile Money reçus sur le téléphone de l'administrateur.
// Le récepteur Android de l'application envoie : POST { token, sender, body, received_at }.
// Le SMS est analysé (montant, numéro, référence) puis rapproché d'un paiement déclaré par un client.
// Il ne valide JAMAIS un paiement seul : l'administrateur garde la décision.
import { admin, json } from "../_shared/common.ts";

function parse(sender: string, body: string) {
  const text = body.replace(/ /g, " ");
  const operator = /moov|flooz/i.test(sender + " " + text) ? "Moov Money" : "Orange Money";
  const amountMatch = text.match(/(\d[\d\s.,]*\d|\d)\s*(?:F\s?CFA|FCFA|XOF|F\b)/i);
  const amount = amountMatch ? parseInt(amountMatch[1].replace(/[\s.,]/g, ""), 10) : null;
  const phoneMatch = text.match(/(?:du|de|par|from|vers|au|à|num[ée]ro|exp[ée]diteur)\s*:?\s*(?:\+?226)?\s*((?:\d\s?){8})(?!\d)/i);
  const phone = phoneMatch ? phoneMatch[1].replace(/\s/g, "") : null;
  const refMatch = text.match(/(?:ID\s*(?:de\s*)?(?:trans(?:action)?)?|Trans(?:action)?\s*(?:ID)?|R[ée]f(?:[ée]rence)?|Txn)\s*[:.#]?\s*([A-Z0-9][A-Z0-9.\-]{5,})/i);
  const ref = refMatch ? refMatch[1].replace(/[.\-]+$/, "") : null;
  let direction = "unknown";
  if (/re[çc]u|reception|r[ée]ception|cr[ée]dit|vous avez re/i.test(text)) direction = "in";
  else if (/envoy|transf[ée]r[ée]?\s+(?:de\s+\S+\s+)?vers|d[ée]bit|paiement effectu|retrait|achat/i.test(text)) direction = "out";
  return { operator, amount: Number.isFinite(amount) ? amount : null, phone, ref, direction };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  try {
    const { token, sender, body, received_at } = await req.json();
    if (typeof token !== "string" || token.length < 32) return json({ error: "Non autorisé" }, 401);
    if (typeof body !== "string" || !body.trim()) return json({ error: "SMS vide" }, 400);
    const s = String(sender ?? "").slice(0, 60);
    const p = parse(s, body);
    const ts = typeof received_at === "number" ? new Date(received_at).toISOString()
      : typeof received_at === "string" ? received_at : null;
    const res = await admin.rpc<Record<string, unknown>>("_relay_sms", {
      p_token: token, p_sender: s, p_body: body.slice(0, 1000), p_received_at: ts,
      p_operator: p.operator, p_direction: p.direction, p_amount: p.amount, p_phone: p.phone, p_ref: p.ref,
    });
    return json({ ok: true, parsed: p, ...res });
  } catch (e) {
    const msg = (e as Error).message;
    return json({ error: msg }, /Relais inconnu/.test(msg) ? 401 : 500);
  }
});
