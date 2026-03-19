package com.vakust.notifierv3.net

import com.vakust.notifierv3.model.CommandResponse
import com.vakust.notifierv3.model.EventItem
import com.vakust.notifierv3.model.FeedResponse
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant

class ApiClient {
    fun checkHealth(baseUrl: String): Boolean {
        val url = URL(baseUrl.trimEnd('/') + "/health")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 2500
            readTimeout = 2500
            setRequestProperty("Accept", "application/json")
        }
        return conn.useResponse { body ->
            JSONObject(body).optBoolean("ok", false)
        }
    }

    fun fetchFeed(baseUrl: String, token: String, limit: Int = 30): FeedResponse {
        val url = URL(baseUrl.trimEnd('/') + "/v1/mobile/feed?limit=$limit")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 6000
            readTimeout = 6000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
        }
        return conn.useResponse { body ->
            val json = JSONObject(body)
            val items = json.optJSONArray("items") ?: JSONArray()
            FeedResponse(
                ok = json.optBoolean("ok", false),
                items = parseItems(items),
                next_cursor = json.optString("next_cursor", "").ifBlank { null }
            )
        }
    }

    fun sendCommand(baseUrl: String, token: String, target: String, action: String): CommandResponse {
        val url = URL(baseUrl.trimEnd('/') + "/v1/mobile/commands")
        val payload = JSONObject(
            mapOf(
                "target" to target,
                "action" to action,
                "metadata" to mapOf(
                    "client" to "android-app",
                    "ts" to Instant.now().toString()
                )
            )
        )

        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 6000
            readTimeout = 6000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }

        OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(payload.toString()) }
        return conn.useResponse { body ->
            val json = JSONObject(body)
            CommandResponse(
                ok = json.optBoolean("ok", false),
                command_id = json.optString("command_id", ""),
                status = json.optString("status", "unknown")
            )
        }
    }

    private fun parseItems(raw: JSONArray): List<EventItem> {
        val out = mutableListOf<EventItem>()
        for (i in 0 until raw.length()) {
            val obj = raw.optJSONObject(i) ?: continue
            val payload = obj.optJSONObject("payload") ?: JSONObject()
            val payloadMap = mutableMapOf<String, Any?>()
            payload.keys().forEach { key -> payloadMap[key] = payload.opt(key) }

            out += EventItem(
                event_id = obj.optString("event_id", ""),
                ts = obj.optString("ts", ""),
                source = obj.optString("source", ""),
                type = obj.optString("type", ""),
                payload = payloadMap
            )
        }
        return out
    }

    private inline fun <T> HttpURLConnection.useResponse(block: (String) -> T): T {
        val code = responseCode
        val stream = if (code in 200..299) inputStream else (errorStream ?: inputStream)
        val body = BufferedReader(stream.reader(Charsets.UTF_8)).use { it.readText() }
        if (code !in 200..299) {
            throw IllegalStateException("HTTP $code: $body")
        }
        return block(body)
    }
}
