package app.telima.telima

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Relais des SMS Mobile Money (Orange Money / Moov Money) reçus sur le téléphone de l'administrateur.
 * Actif uniquement si l'administrateur l'a activé dans Telima (clé de relais enregistrée) et a autorisé
 * la réception des SMS. Seuls les SMS Mobile Money sont transmis ; ils ne valident jamais un paiement seuls.
 * Fonctionne application fermée. En cas d'échec réseau, le SMS est gardé et renvoyé plus tard.
 */
class SmsRelayReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getString(KEY_TOKEN, null).isNullOrEmpty()) return
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        val grouped = LinkedHashMap<String, StringBuilder>()
        var timestamp = System.currentTimeMillis()
        for (m in messages) {
            val sender = m.originatingAddress ?: "?"
            grouped.getOrPut(sender) { StringBuilder() }.append(m.messageBody ?: "")
            timestamp = m.timestampMillis
        }
        val toSend = grouped.filter { (sender, body) -> isMobileMoney(sender, body.toString()) }
        if (toSend.isEmpty()) return
        val pending = goAsync()
        Thread {
            try {
                for ((sender, body) in toSend) enqueue(context, sender, body.toString(), timestamp)
                flushQueue(context)
            } finally {
                pending.finish()
            }
        }.start()
    }

    companion object {
        const val PREFS = "telima_sms_relay"
        const val KEY_TOKEN = "token"
        const val KEY_URL = "url"
        private const val KEY_QUEUE = "queue"
        private val SENDER = Regex("orange|moov|flooz|money|\\bom\\b", RegexOption.IGNORE_CASE)
        private val BODY = Regex("orange money|moov money|flooz|transfert|re[çc]u|fcfa", RegexOption.IGNORE_CASE)

        fun isMobileMoney(sender: String, body: String): Boolean =
            SENDER.containsMatchIn(sender) || (BODY.containsMatchIn(body) && Regex("\\d").containsMatchIn(body) &&
                Regex("orange|moov|om\\b|money", RegexOption.IGNORE_CASE).containsMatchIn(body))

        @Synchronized
        private fun enqueue(context: Context, sender: String, body: String, ts: Long) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
            queue.put(JSONObject().put("sender", sender).put("body", body).put("received_at", ts))
            val trimmed = JSONArray()
            val start = maxOf(0, queue.length() - 50)
            for (i in start until queue.length()) trimmed.put(queue.get(i))
            prefs.edit().putString(KEY_QUEUE, trimmed.toString()).apply()
        }

        /** Envoie les SMS en attente ; ceux qui échouent restent dans la file. */
        @Synchronized
        fun flushQueue(context: Context) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val token = prefs.getString(KEY_TOKEN, null) ?: return
            val url = prefs.getString(KEY_URL, null) ?: return
            val queue = JSONArray(prefs.getString(KEY_QUEUE, "[]"))
            val remaining = JSONArray()
            for (i in 0 until queue.length()) {
                val item = queue.getJSONObject(i)
                val code = post(url, JSONObject(item.toString()).put("token", token))
                // 2xx : transmis ; 400/401 : refusé définitivement (clé révoquée, SMS vide) → abandonné
                if (code !in 200..299 && code != 400 && code != 401) remaining.put(item)
            }
            prefs.edit().putString(KEY_QUEUE, remaining.toString()).apply()
        }

        private fun post(url: String, payload: JSONObject): Int = try {
            val c = URL(url).openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 10000
            c.readTimeout = 15000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json")
            c.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }
            val code = c.responseCode
            c.disconnect()
            code
        } catch (e: Exception) {
            -1
        }
    }
}
